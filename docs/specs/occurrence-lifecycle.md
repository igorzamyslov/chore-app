# Spec: Occurrence Lifecycle Service

*Application-layer orchestration between the recurrence engine
(lib/domain/recurrence/) and the data layer (lib/data/). Owns every rule
about when occurrences are created, closed, missed, and who they're
assigned to.*

## Placement

| What | Where |
|---|---|
| Rotation logic (pure) | `lib/domain/rotation.dart` |
| Service | `lib/application/chore_service.dart` |
| Tests | `test/domain/rotation_test.dart`, `test/application/chore_service_test.dart` |

`lib/domain/rotation.dart` is pure Dart, zero deps (same standard as the
recurrence engine). `chore_service.dart` may import the domain, the data
layer, and `package:clock` — nothing else (no Flutter).

## 1. Rotation (pure)

```dart
/// The member who takes the next turn in a rotation.
///
/// [orderedMemberIds] is the rotation order (non-empty).
/// Returns the member after [lastAssignedMemberId] (wrapping around).
/// If [lastAssignedMemberId] is null or no longer in the list (e.g. the
/// chore's assignees were edited), returns the first member.
String nextRotationAssignee({
  required List<String> orderedMemberIds,
  required String? lastAssignedMemberId,
});
```
Throws `ArgumentError` on an empty list.

## 2. ChoreService

```dart
class ChoreService {
  ChoreService({
    required AppDatabase database,   // for transactions
    required ChoreRepository chores,
    Clock clock = const Clock(),     // package:clock
  });
}
```

"Today" is always `PlainDate.fromDateTime(clock.now())` — the device's
local calendar day, computed exactly once per public method call. Every
public method that performs more than one write runs inside
`database.transaction(...)`.

### createChore(...)
Same parameters as `ChoreRepository.createChore`. Creates the chore via the
repository, then inserts the FIRST pending occurrence:

- due date: `recurrence == null` (one-off) → `startDate`;
  otherwise → `firstDueDate(recurrence, startDate)`.
- assigned member: `fixed` → the single assignee; `rotation` → assignees
  position 0; `anyone` → null.

### completeOccurrence(String occurrenceId, {required String completedBy})
### skipOccurrence(String occurrenceId)
Both "close" the pending occurrence with `closedOn = today`:

- `complete` → status `done`, `completed_by = completedBy`.
- `skip` → status `skipped`, `completed_by` stays null.
- Throws `StateError` if the occurrence is not pending.
- If the chore is recurring, insert the next pending occurrence:
  - due = `nextDueDateAfterClosing(rule, startDate, closedDueDate: <closed
    occurrence's due>, closedOn: today)`.
  - assignee — THE product rule: **done advances the rotation, skip
    sticks**:
    - `fixed` → the single assignee, always.
    - `rotation` + done → `nextRotationAssignee(order, closed.assignedMemberId)`.
    - `rotation` + skip → `closed.assignedMemberId` (unchanged; if null or
      no longer an assignee, fall back to `nextRotationAssignee`).
    - `anyone` → null.
- One-off chores get no next occurrence.

### catchUpOverdue(String householdId)
Runs on app start and on day change. For every active, unpaused,
**schedule-anchored recurring** chore with a pending occurrence where at
least one later series slot is ≤ today:

- close the pending occurrence as `missed` (`closedOn = today`),
- insert a new pending occurrence at the **latest** series slot ≤ today,
  keeping the SAME assigned member (missed turns don't advance rotation —
  otherwise procrastination would pass your turn to someone else).

This maintains the product invariant: at most ONE visible overdue
occurrence per chore, at its most recent missed slot. Completion-anchored
and one-off chores are never auto-missed — they just stay overdue.
Idempotent: a second call the same day changes nothing.

### pauseChore(String choreId)
`setPaused(true)` + delete pending occurrences. History untouched.

### unpauseChore(String choreId)
`setPaused(false)` + insert a fresh pending occurrence:

- schedule anchor → `nextScheduledOnOrAfter(rule, startDate, today)`
- completion anchor → `today`
- one-off → `startDate` if ≥ today, else `today`
- assignee: `fixed` → the assignee; `anyone` → null; `rotation` → continue
  from history: `nextRotationAssignee(order,
  latestClosedOccurrence?.assignedMemberId)`.

Both throw `StateError` if the chore doesn't exist or is soft-deleted;
`pauseChore` on a paused chore (and unpause on unpaused) is a no-op.

### reopenOccurrence(String occurrenceId)
The undo path for `completeOccurrence`/`skipOccurrence` (spec
`docs/specs/ux-round-2.md` A3/A4: the "Done today" section's Reopen action
and the complete/skip snackbars' UNDO action). In one transaction:

- delete the chore's current pending occurrence (if any) — a chore has at
  most one pending occurrence at a time, so this is exactly the occurrence
  that was inserted when [occurrenceId] was closed;
- reset [occurrenceId] itself back to `pending`, clearing `closed_on` and
  `completed_by`, while leaving `assigned_member_id` untouched (the
  occurrence is restored with the same assignee it had before closing).

Throws `StateError` if the chore has been deleted, or if [occurrenceId]
isn't currently closed with `closed_on == today` — i.e. it's still
`pending`, or it was closed on an earlier day. **This "closed today"
restriction is enforced at the SERVICE level**, per spec A3:
`ChoreRepository` has no notion of "today" — [occurrenceId]'s `closed_on`
is compared against `_today` (this service's usual clock-derived value),
computed once per call like every other public method here.

Note this is more permissive about occurrence *status* than the UI that
calls it: the chores list only ever offers Reopen on `done`/`skipped` rows
(the "Done today" section excludes `missed`), but this method itself
accepts any non-pending status, so long as `closed_on` is today.

## 3. Testing requirements

Integration-style over a real in-memory `AppDatabase` (no mocks), fixed
injected clock (`Clock.fixed`) advanced explicitly per scenario, counter
ids. Cover at minimum:

1. Rotation function: wrap-around; null last; removed-member fallback;
   single-member rotation; empty list throws.
2. createChore: first due per anchor (schedule with pinned weekday ahead of
   startDate; completion → startDate; one-off → startDate); assignee per
   mode.
3. complete: done advances rotation across 4 closes (full wrap); skip
   sticks (same member twice, then done advances); fixed unaffected;
   anyone stays null; completed_by recorded only for done; one-off creates
   no next; closing a non-pending occurrence throws StateError.
4. Late completion: schedule-anchored weekly chore completed 16 days late →
   next due is the first slot strictly after today (missed slots skipped).
5. catchUpOverdue: 3 slots behind → exactly one pending at latest slot ≤
   today, one new `missed` row, assignee preserved; future-due pending
   untouched; completion-anchored chore 10 days overdue untouched; paused
   chore untouched; second call same day is a no-op (assert row counts).
6. pause/unpause round-trip per anchor mode incl. rotation continuity
   (A done → paused → unpaused → next assignee is B).
7. Every multi-write method leaves consistent state if re-read mid-test
   (assert via repository watches/gets, not raw SQL).

Done criteria: `dart format` clean; `flutter analyze --fatal-infos
--fatal-warnings` clean; `flutter test` fully green.
