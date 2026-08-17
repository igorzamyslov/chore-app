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
Runs on app start, on app resume, and on local day change (the resume/
day-change triggers are owned by `CatchUpController` in
`lib/app/providers.dart` — see `docs/specs/polish-round-1.md` C1). For
every active, unpaused, **schedule-anchored recurring** chore with a
pending occurrence where at least one later series slot is ≤ today:

- close the pending occurrence as `missed` (`closedOn = today`),
- insert a new pending occurrence at the **latest** series slot ≤ today,
  keeping the SAME assigned member (missed turns don't advance rotation —
  otherwise procrastination would pass your turn to someone else).

This maintains the product invariant: at most ONE visible overdue
occurrence per chore, at its most recent missed slot. Completion-anchored
and one-off chores are never auto-missed — they just stay overdue.
Idempotent: a second call the same day changes nothing.

Returns the **number of chores it changed** (0 if none — the common case).
The digest recompute `CatchUpController` runs after every catch-up is
deliberately UNCONDITIONAL and does not consult this number (a day passing
is itself a reason to re-arm a bounded horizon); the count exists for the
UI.

**Catch-up must be visible (backlog B-1 / triage T2.1).** Rolling a
backlog forward before the first frame is silent by construction: the only
trace left is a reinserted pending occurrence, indistinguishable from one
that was always overdue, so to a returning user the list reads as an
unexplained accusation. Every catch-up run therefore ADDS its nonzero
count to an in-memory counter (`catchUpBannerCountProvider`,
`lib/app/providers.dart`), which the chores list renders as a dismissible
banner (`catchup.banner`, dismiss `catchup.banner.dismiss`) above the
first-run banners, explaining the mechanism in one sentence without using
the word "missed". Requirements:

- Zero count ⇒ nothing shown. A cold start with nothing overdue must be
  indistinguishable from before.
- Accumulating, not overwriting: a second run firing before the user has
  acknowledged the first never drops the earlier count.
- NOT persisted, unlike the once-ever `settings` flags behind the
  first-run banners: catch-up is a recurring background event, so a later
  run must be able to explain itself again. Dismissing resets the counter
  to 0.

### pauseChore(String choreId)
`setPaused(true)` + delete pending occurrences. History untouched.

### unpauseChore(String choreId)
`setPaused(false)` + insert a fresh pending occurrence — except for a
one-off whose only occurrence is already closed, which gets none (see
below).

Fetches `latestClosed = latestClosedOccurrence(choreId)` exactly once (the
most recent occurrence that is done, skipped, or missed — pending doesn't
count). This deliberately includes **skipped**: a skipped slot must not
resurrect either, same "skip sticks" principle as `completeOccurrence`/
`skipOccurrence`.

- **one-off**: if `latestClosed != null`, unpause the chore but insert NO
  occurrence at all — a completed/skipped one-off must never come back.
  Otherwise unchanged: `startDate` if ≥ today, else `today`.
- **schedule anchor**: `fromDate` = today if (`latestClosed == null` OR
  `latestClosed.dueDate` is before today), else `latestClosed.dueDate + 1
  day`; due = `nextScheduledOnOrAfter(rule, startDate, fromDate)`.
  Rationale — pause is a vacation, so unpause floors at two points: never
  *before* today (no instantly-overdue occurrence), and never *at or
  before* the latest closed slot (no resurrecting a slot that's already
  done/skipped/missed). The second floor is what fixes the bug where
  completing today's occurrence, then pausing, then unpausing the same day
  used to bring back a second pending occurrence at that same already-done
  slot.
- **completion anchor**: `today` if `latestClosed == null`; otherwise
  `candidate = nextAfterCompletion(rule, latestClosed.closedOn)`, and due =
  `candidate` if it's after today, else `today`.
- assignee: `fixed` → the assignee; `anyone` → null; `rotation` → continue
  from history: `nextRotationAssignee(order, latestClosed?.assignedMemberId)`.

Both throw `StateError` if the chore doesn't exist or is soft-deleted;
`pauseChore` on a paused chore (and unpause on unpaused) is a no-op.

### updateChore(String id, {...})
Same parameters as `ChoreRepository.updateChore` (title/notes/categoryId/
recurrence/startDate/assignmentMode/assigneeMemberIds — same "omit to leave
unchanged" convention; `notes`/`categoryId`/`recurrence` need drift's
`Value` wrapper to distinguish "unchanged" from "set to null").

Updates the chore via the repository, then, if the edit changed
`recurrence` and/or `startDate` — compared by serialized value (two
`Recurrence`s are equal iff their JSON encodings match; a bare `null` only
ever equals `null`) — regenerates the chore's pending occurrence, in the
same transaction:

- delete the chore's current pending occurrence (if any);
- if the chore is paused, stop there — a paused chore has no pending
  occurrence by design (see `pauseChore`), and `unpauseChore` computes the
  right one later, from this now-updated row;
- otherwise insert a fresh one using THE SAME two-floors due-date rule as
  `unpauseChore` (never before today; never at or before the latest closed
  slot; closed one-off → nothing; completion anchor →
  `max(today, nextAfterCompletion)`), with the assignee re-resolved the
  same way (`fixed` → the assignee; `anyone` → null; `rotation` →
  continues from `latestClosedOccurrence` via `nextRotationAssignee`).

An edit that changes NEITHER `recurrence` nor `startDate` leaves the
pending occurrence — and its assignee — completely untouched, no matter
what else changed (title, notes, category, assignment mode/assignees).

Throws `StateError` if the chore doesn't exist or is soft-deleted (same
guard as `pauseChore`/`unpauseChore`).

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

**LIFO restriction (amended 2026-08-01, field feedback B2 —
docs/feedback/2026-08-01-field-feedback.md):** when a chore has SEVERAL
closed-today occurrences (possible because the successor of a closed
occurrence is itself immediately closable), only the LATEST of them —
ordered by due date, then `updated_at` as tiebreak — may be reopened.
Reopening a non-latest one throws `StateError`: the blanket
delete-pending step above would otherwise destroy a sibling occurrence
that an earlier reopen just restored (the original data-loss bug).
Unwinding a multi-close chain therefore takes several reopens,
newest-first, and restores exactly the original state at every step. The
Done-today UI mirrors the rule: the Reopen affordance is shown only on
each chore's latest closed-today row and reappears on the next row as
the chain unwinds.

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
   The returned count is asserted on every one of those calls (1, 0, 0,
   0 respectively) plus a two-overdue-chores run returning 2, so it is
   provably per-chore rather than a saturating flag. Banner side: the
   cold-start (`bootstrapProvider`) and resume/day-change
   (`CatchUpController`) paths each set `catchUpBannerCountProvider` to the
   real count, and the banner itself renders/hides/dismisses off it.
6. pause/unpause round-trip per anchor mode incl. rotation continuity
   (A done → paused → unpaused → next assignee is B); done/skip today →
   paused → unpaused (same day) never resurrects a pending occurrence at
   today's already-closed slot, for both schedule and completion anchors
   (and pinned-weekday schedules), and never when the latest closed slot is
   weeks in the past either; a closed one-off stays closed through a
   pause/unpause round trip (unpaused, zero pending, history untouched).
7. Every multi-write method leaves consistent state if re-read mid-test
   (assert via repository watches/gets, not raw SQL).
8. updateChore: changed recurrence and changed startDate both regenerate
   (new due date per the two-floors rule, old pending row gone via delete —
   not closed as `missed`); a weekday-pinned schedule recalculates against
   the new pin; a completion-anchored edit recomputes from
   `latestClosedOccurrence`; an edit touching neither field leaves the
   pending occurrence and its assignee byte-for-byte untouched; a
   completed one-off stays closed with no resurrection even when its
   startDate changes; a paused chore's edit updates the row but inserts no
   occurrence (unpausing afterward reads the updated rule correctly).

Done criteria: `dart format` clean; `flutter analyze --fatal-infos
--fatal-warnings` clean; `flutter test` fully green.
