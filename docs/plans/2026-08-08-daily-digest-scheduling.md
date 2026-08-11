# Daily Digest Scheduling (A-1 + T2.3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily digest actually fire every day without the app being opened, and scope its counts to the person holding the phone.

**Architecture:** Replace the single one-shot notification (id `1001`) with a
rolling **7-day horizon**: every recompute writes all seven ids
(`1001..1007`) at once — scheduling the days that have something to say and
cancelling the days that don't. The counts for a future day are *projected*
by a new pure domain function that mirrors catch-up's own rule (a
schedule-anchored chore rolls forward to its latest slot on or before that
date; everything else stays where it is), and are filtered to the acting
member. Nothing about the OS-facing plugin changes: still inexact, still
no `SCHEDULE_EXACT_ALARM`, still no `flutter_timezone`.

**Tech Stack:** Flutter · Riverpod · drift · `flutter_local_notifications` ·
`timezone` · gen_l10n · `very_good_analysis`

---

## Open product decisions

### OPD-1 — CLOSED 2026-08-08 (Igor): Option A

**Resolved — do not re-open during execution.** The digest counts the
recipient's own chores **plus unassigned "anyone" chores**. Strictly-mine
(Option B) would leave a household that assigns everything to "anyone" in
permanent silence, which is a worse failure than slight over-inclusion. The
plan below already assumes Option A throughout; the record of the
alternatives is kept for context only.

**Consequence:** this deviates from a written project decision —
`DESIGN.md` §3 says *"Scope: 'my chores' by default; 'unassigned chores'
opt-in"*, and Option A makes the opt-in behaviour the default. Fine on the
merits (§3 was written for the pre-sync, single-device era, when one phone
stood in for the whole household and the distinction barely mattered), but
this project records deviations rather than silently absorbing them — so
**Task 11 amends `DESIGN.md` §3**. It is not optional.

### OPD-1 (original write-up) — What does "my digest" count? (this is T2.3)

Today `_recompute` (`lib/app/providers.dart:736-745`) counts every pending
occurrence in the household, so both partners get the identical number every
morning. Once the digest genuinely fires daily this is seen every day rather
than once in a while, which is why the audit folds it in here. What should
the number mean?

- **Option A (recommended) — "yours plus everyone's".** Count occurrences
  assigned to the acting member, *plus* every unassigned (`anyone`)
  occurrence. Rationale: `anyone` chores are genuinely both partners'
  business, and a single-member household (the overwhelmingly common case
  today, where nearly everything is `anyone`) sees no change at all.
  Fixed/rotation chores assigned to the partner drop out, which is the
  entire point of the ticket.
- **Option B — "strictly mine".** Only occurrences whose
  `assignedMemberId` equals the acting member. Sharper, but a household that
  uses `anyone` for everything would get a permanently silent digest — the
  exact failure mode this whole plan exists to remove.
- **Option C — keep household-wide, and say whose.** e.g. *"3 chores today
  · 1 yours"*. Most informative, but needs two new ICU plural strings in both
  ARBs and a longer notification body on a platform that truncates.

**Option A was chosen (see the CLOSED block above).** It is one predicate in one pure function
(`projectDigestCounts`, Task 2) plus one test group. Switching to B is
deleting the `assignedMemberId == null` clause; switching to C means keeping
the counts unscoped and adding ARB strings — both are contained edits that do
not disturb any other task.

**Related, already settled elsewhere:** who "the acting member" *is* when the
household is linked is **A-5**'s job (pin to the claimed member, hide the
switcher). This plan just reads `actingMemberProvider`, so it inherits
whatever A-5 lands without further change.

---

## Judgement calls made (not product decisions — recorded so a reviewer can push back)

1. **Approach chosen: 7 slots ahead (audit option 1), not
   `matchDateTimeComponents`.** See "Approaches considered" below.
2. **Horizon = 7 days**, per the audit's own "~7 slots". iOS caps an app at
   64 pending local notifications, so 7 is nowhere near a limit; the constant
   `digestHorizonDays` is the single place to change it.
3. **Projection mirrors catch-up rather than replaying the recurrence
   series.** A chore only ever has ONE pending occurrence, so "what would day
   D look like" is exactly "what would `catchUpOverdue` have done by day D" —
   and that logic already exists. It is extracted to the domain (Task 1) and
   shared, rather than reimplemented, so the two can never drift apart.
4. **An unresolvable acting member (`null`) counts everything.** A digest
   that hides work because identity is momentarily unknown is worse than one
   that shows too much.
5. **Slot `k` owns id `1001 + k`, and every recompute rewrites all seven.**
   No partial updates, no id-per-date arithmetic to get wrong; a day that
   turns silent is explicitly cancelled.
6. **`CatchUpController` recomputes the digest unconditionally at midnight**,
   dropping the `if (changed)` gate (Task 9). Without it, an app left open
   for more than seven days runs off the end of its own horizon.

### Approaches considered

| | How it works | Why not / why yes |
| --- | --- | --- |
| **1. Rolling 7-day horizon** *(chosen)* | Every recompute cancels+schedules ids `1001..1007`, one per day, counts projected per date | Keeps the spec's "silence when nothing is due" rule **per day**; keeps counts honest; needs no new permission, no `flutter_timezone`, no background isolate, no platform code. Fails only after 7 unopened days, and fails to *silence*, not to spam |
| 2. `matchDateTimeComponents: DateTimeComponents.time` | One genuinely repeating daily alarm | Rejected. It **cannot express the silence rule at all** — it fires every single day forever, including days with nothing due, which is the one thing `DESIGN.md` §2 and `notifications.md` both forbid. The body text also freezes at whatever the counts were the day it was scheduled, and it needs a named `Location` (i.e. the `flutter_timezone` dependency `notification_scheduler.dart:135-144` deliberately explains away) |
| 3. Background isolate / WorkManager / server push | Re-arm from a background execution context | Rejected for this release. Android-only in practice (iOS has no dependable equivalent for this), needs new manifest capabilities and its own test story, and is explicitly N3 in `notifications.md`'s phasing |
| 4. Hybrid: horizon + a repeating fallback alarm at the end of it | Horizon for accuracy, `matchDateTimeComponents` as a backstop | Rejected. Inherits option 2's fatal flaw (the backstop fires on silent days) for a failure mode option 1 already handles acceptably |

---

## Global Constraints

- **Never** run `flutter`/`dart` yourself unless the task says to; when a
  step says to run tests, run exactly the command given.
- Specs in `docs/specs/` are binding contracts. `docs/specs/notifications.md`
  is updated by **Task 10** — that task is not optional.
- Every user-visible string goes through gen_l10n:
  `lib/l10n/app_en.arb` (template) + `lib/l10n/app_de.arb` (German
  **du**-form). Never inline English. *This plan adds no new strings under
  OPD-1 Option A.*
- Every interactive widget gets a stable id via `semantic()`
  (`lib/app/semantics.dart`). *This plan adds no widgets.*
- Widget/controller tests are integration-style: a real in-memory
  `AppDatabase` + fixed clock, overriding **only** `appDatabaseProvider`,
  `clockProvider` and the documented `digestNotificationPluginProvider` seam.
  Never mock repositories or services.
- Deadlocks to design around: never bare-`await` a drift stream outside a
  widget pump; never bare-`await bootstrapProvider.future` in a
  `ProviderContainer` test (poll `.hasValue` with pump loops — use the
  existing `_awaitBootstrap` helper); put one `tester.pump(small duration)`
  between `container.dispose()` and `database.close()`.
- Strict lints (`very_good_analysis`, `--fatal-infos`). **Every public
  member needs a doc comment**, including top-level constants and every
  field of every new class.
- `lib/domain/` is pure: no Flutter, no drift, no clock reads. Domain files
  may import other `lib/domain/` files and nothing else.
- TDD per task: write the failing test → run it → implement → run → commit.
- Commit messages: no `Co-Authored-By:` trailer, ever.
- **Every task must leave the repo compiling and green.** The old
  `planDigest`/`scheduleDigest` are deliberately kept alive until Task 8
  deletes them, so no intermediate commit is broken.

---

## File-structure map

**Created**

| File | Responsibility |
| --- | --- |
| `lib/domain/digest_projection.dart` | Pure: "what would the digest counts be on date D, if the app is never opened between now and then", including recipient scoping. Depends only on `lib/domain/recurrence/`. |
| `lib/application/digest_plan_builder.dart` | The single place that turns `(now, settings, pending occurrences, recipient)` into the seven-slot `List<DigestPlan?>`. Kills the duplicated recompute logic that `digest_preprompt_banner.dart:116-153` currently apologises for. |
| `test/domain/digest_projection_test.dart` | Pure unit tests for the projection. |
| `test/application/digest_plan_builder_test.dart` | Integration-style tests (real in-memory DB) for horizon shape + recipient scoping. |

**Modified**

| File | Change |
| --- | --- |
| `lib/domain/recurrence/recurrence_engine.dart` | Gains public `latestScheduledOnOrBefore` (extracted from `chore_service.dart`'s private `_latestOverdueSlot`). |
| `lib/application/chore_service.dart` | `catchUpOverdue` delegates to the extracted helper; private copy deleted. |
| `lib/domain/digest_planner.dart` | Gains `digestHorizonDays`, `digestSlots`, `planDigestSlot`; loses `planDigest` (Task 8). |
| `lib/application/notification_scheduler.dart` | `digestNotificationId` → `digestNotificationIdBase` + `digestNotificationIds`; gains `applyDigestPlans`; `cancelDigest` cancels the whole horizon; loses `scheduleDigest` (Task 8). |
| `lib/app/providers.dart` | `DigestRescheduleController._recompute` uses `buildDigestPlans` + `applyDigestPlans`; also listens to `actingMemberProvider`. `CatchUpController._runCatchUp` recomputes unconditionally. |
| `lib/features/chores/digest_preprompt_banner.dart` | `_recomputeDigest` shrinks to a `buildDigestPlans` call. |
| `test/application/fake_digest_notification_plugin.dart` | Gains a `pending` map + `deliverDue()` so "is a notification still armed tomorrow?" is assertable. |
| `test/domain/recurrence/recurrence_engine_test.dart` | Tests for `latestScheduledOnOrBefore`. |
| `test/domain/digest_planner_test.dart` | `digestSlots` group; `planDigest` group → `planDigestSlot`. |
| `test/application/notification_scheduler_test.dart` | `applyDigestPlans` group; `cancelDigest` cancels 7. |
| `test/app/digest_reschedule_test.dart` | **The no-interaction survival test**; horizon-rewrite test; `_disposeAndClose` teardown. |
| `test/app/day_change_catchup_test.dart` | Midnight now always recomputes. |
| `docs/specs/notifications.md` | The spec bug: N1 behaviour, architecture #1/#2/#3, testing. |
| `DESIGN.md` | §3's scope rule amended to "own + unassigned" (Task 11 — the recorded OPD-1 deviation). |
| `docs/backlog.md` | A-1 and T2.3 marked done; new G-9 follow-up row. |

---

## Task 1: Extract the "latest slot on or before a date" rule into the recurrence engine

The digest projection needs exactly the rule `catchUpOverdue` already
implements privately. Extract it first so there is one copy, not two.

**Files:**
- Modify: `lib/domain/recurrence/recurrence_engine.dart` (append)
- Modify: `lib/application/chore_service.dart:155-160` and `:643-660`
- Test: `test/domain/recurrence/recurrence_engine_test.dart` (append)

**Interfaces:**
- Consumes: `nextScheduledOnOrAfter`, `PlainDate`, `Recurrence` (all existing)
- Produces: `PlainDate? latestScheduledOnOrBefore({required Recurrence rule, required PlainDate startDate, required PlainDate afterDueDate, required PlainDate notAfter})`

- [ ] **Step 1: Write the failing tests**

Append to `test/domain/recurrence/recurrence_engine_test.dart`, inside
`main()`:

```dart
  group('latestScheduledOnOrBefore', () {
    test('daily rule returns the newest slot at or before notAfter', () {
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.everyNDays(1),
        startDate: PlainDate(2026, 1, 5),
        afterDueDate: PlainDate(2026, 1, 5),
        notAfter: PlainDate(2026, 1, 8),
      );
      expect(slot, PlainDate(2026, 1, 8));
    });

    test('weekly rule skips the days between two slots', () {
      // 2026-01-05 is a Monday; 2026-01-15 is a Thursday.
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.weekly(weekdays: const {DateTime.monday}),
        startDate: PlainDate(2026, 1, 5),
        afterDueDate: PlainDate(2026, 1, 5),
        notAfter: PlainDate(2026, 1, 15),
      );
      expect(slot, PlainDate(2026, 1, 12));
    });

    test('returns null when the next slot is still ahead of notAfter', () {
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.everyNDays(3),
        startDate: PlainDate(2026, 1, 5),
        afterDueDate: PlainDate(2026, 1, 5),
        notAfter: PlainDate(2026, 1, 7),
      );
      expect(slot, isNull);
    });

    test('never returns a slot at or before afterDueDate', () {
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.everyNDays(1),
        startDate: PlainDate(2026, 1, 1),
        afterDueDate: PlainDate(2026, 1, 10),
        notAfter: PlainDate(2026, 1, 10),
      );
      expect(slot, isNull);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/recurrence/recurrence_engine_test.dart`
Expected: FAIL — `The function 'latestScheduledOnOrBefore' isn't defined`.

- [ ] **Step 3: Implement**

Append to `lib/domain/recurrence/recurrence_engine.dart`, above the
`// Internal helpers` divider:

```dart
/// The latest schedule slot for [rule]/[startDate] that is on or before
/// [notAfter] and strictly after [afterDueDate], or `null` if there is none
/// (i.e. nothing has come due past [afterDueDate] by [notAfter]).
///
/// This is the rule `ChoreService.catchUpOverdue` applies to roll an
/// overdue schedule-anchored chore forward, and the same rule
/// `lib/domain/digest_projection.dart` applies to answer "what would this
/// chore look like on day D" — extracted here so the two can never drift
/// apart.
///
/// Walks forward one slot at a time from [afterDueDate] via
/// [nextScheduledOnOrAfter], which is efficient per that function's
/// performance contract; the number of steps is bounded by how many slots
/// have been missed, not by the distance from [startDate].
PlainDate? latestScheduledOnOrBefore({
  required Recurrence rule,
  required PlainDate startDate,
  required PlainDate afterDueDate,
  required PlainDate notAfter,
}) {
  var latest = nextScheduledOnOrAfter(rule, startDate, afterDueDate.addDays(1));
  if (latest.isAfter(notAfter)) {
    return null;
  }
  while (true) {
    final next = nextScheduledOnOrAfter(rule, startDate, latest.addDays(1));
    if (next.isAfter(notAfter)) {
      return latest;
    }
    latest = next;
  }
}
```

- [ ] **Step 4: Delete the private copy and delegate**

In `lib/application/chore_service.dart`, delete the whole private
`_latestOverdueSlot` function (the file's last declaration, currently lines
635-660, including its doc comment), and replace the call site inside
`catchUpOverdue`:

```dart
        final latestSlot = _latestOverdueSlot(
          rule: recurrence,
          startDate: chore.startDate,
          afterDueDate: pending.dueDate,
          today: today,
        );
```

with:

```dart
        final latestSlot = latestScheduledOnOrBefore(
          rule: recurrence,
          startDate: chore.startDate,
          afterDueDate: pending.dueDate,
          notAfter: today,
        );
```

`recurrence_engine.dart` is already imported by `chore_service.dart`
(line 16), so no import change is needed.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/domain/recurrence/ test/application/chore_service_test.dart test/app/day_change_catchup_test.dart`
Expected: PASS — the existing catch-up tests are the safety net proving the
extraction is behaviour-preserving.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/recurrence/recurrence_engine.dart lib/application/chore_service.dart test/domain/recurrence/recurrence_engine_test.dart
git commit -m "Extract latestScheduledOnOrBefore into the recurrence engine"
```

---

## Task 2: The pure digest projection

Answers, for a future date, "what would this household's pending work look
like on that day, given nobody opens the app in between" — and filters it to
one recipient.

**Files:**
- Create: `lib/domain/digest_projection.dart`
- Test: `test/domain/digest_projection_test.dart`

**Interfaces:**
- Consumes: `latestScheduledOnOrBefore` (Task 1), `PlainDate`, `Recurrence`,
  `RecurrenceAnchor`
- Produces:
  - `class ProjectedOccurrence` with `const ProjectedOccurrence({required PlainDate dueDate, required PlainDate startDate, required Recurrence? recurrence, required String? assignedMemberId})`
  - `class DigestCounts` with `int dueCount`, `int overdueCount`, `bool get isSilent`
  - `PlainDate projectedDueDateOn(ProjectedOccurrence occurrence, PlainDate date)`
  - `DigestCounts projectDigestCounts({required Iterable<ProjectedOccurrence> occurrences, required PlainDate date, required String? recipientMemberId})`

- [ ] **Step 1: Write the failing test**

Create `test/domain/digest_projection_test.dart`:

```dart
import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectedOccurrence _occurrence({
  required PlainDate dueDate,
  PlainDate? startDate,
  Recurrence? recurrence,
  String? assignedMemberId,
}) {
  return ProjectedOccurrence(
    dueDate: dueDate,
    startDate: startDate ?? dueDate,
    recurrence: recurrence,
    assignedMemberId: assignedMemberId,
  );
}

void main() {
  group('projectedDueDateOn', () {
    test('a one-off never moves: it just goes further overdue', () {
      final occurrence = _occurrence(dueDate: PlainDate(2026, 1, 5));
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 9)),
        PlainDate(2026, 1, 5),
      );
    });

    test('a completion-anchored chore never moves either', () {
      final occurrence = _occurrence(
        dueDate: PlainDate(2026, 1, 5),
        recurrence: Recurrence.everyNDays(
          2,
          anchor: RecurrenceAnchor.completion,
        ),
      );
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 9)),
        PlainDate(2026, 1, 5),
      );
    });

    test('a schedule-anchored daily chore rolls forward to that very day', () {
      final occurrence = _occurrence(
        dueDate: PlainDate(2026, 1, 5),
        recurrence: Recurrence.everyNDays(1),
      );
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 9)),
        PlainDate(2026, 1, 9),
      );
    });

    test('a schedule-anchored weekly chore lands on its own slot, not the '
        'queried day', () {
      // 2026-01-05 is a Monday; the query date is the following Thursday.
      final occurrence = _occurrence(
        dueDate: PlainDate(2026, 1, 5),
        recurrence: Recurrence.weekly(weekdays: const {DateTime.monday}),
      );
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 15)),
        PlainDate(2026, 1, 12),
      );
    });
  });

  group('projectDigestCounts', () {
    test('splits due-on-the-day from overdue-before-it', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(dueDate: PlainDate(2026, 1, 6)),
          _occurrence(dueDate: PlainDate(2026, 1, 6)),
          _occurrence(dueDate: PlainDate(2026, 1, 2)),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 2);
      expect(counts.overdueCount, 1);
      expect(counts.isSilent, isFalse);
    });

    test('ignores occurrences due after the queried day', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(dueDate: PlainDate(2026, 1, 20))],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.isSilent, isTrue);
    });

    test('counts mine and unassigned, but not my partner\'s (OPD-1 A)', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(dueDate: PlainDate(2026, 1, 6), assignedMemberId: 'me'),
          _occurrence(dueDate: PlainDate(2026, 1, 6)),
          _occurrence(
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: 'me',
      );
      expect(counts.dueCount, 2);
      expect(counts.overdueCount, 0);
    });

    test('a null recipient counts everything (identity unknown must not '
        'hide work)', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(dueDate: PlainDate(2026, 1, 6), assignedMemberId: 'me'),
          _occurrence(
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 2);
    });

    test('scoping is applied before projection, not after', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(
            dueDate: PlainDate(2026, 1, 5),
            recurrence: Recurrence.everyNDays(1),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 9),
        recipientMemberId: 'me',
      );
      expect(counts.isSilent, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/digest_projection_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:chore_app/domain/digest_projection.dart'`.

- [ ] **Step 3: Implement**

Create `lib/domain/digest_projection.dart`:

```dart
// `DigestCounts` has only final fields and no mutating members, so it is
// effectively immutable; we deliberately don't import `package:meta` (lib
// code is dart:core only) to add the `@immutable` annotation the lint below
// wants (same convention as `digest_planner.dart` and `plain_date.dart`).
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Projects what the daily digest would have to say on a *future* calendar
/// date, assuming nothing happens in between (spec
/// `docs/specs/notifications.md` architecture #1).
///
/// This exists because the digest is scheduled a whole horizon ahead
/// (`digestHorizonDays` in `lib/domain/digest_planner.dart`) and each of
/// those days needs its own counts *and* its own silence decision. The
/// assumption "nothing happens in between" is exactly right for the case
/// that matters: the app is not being opened, so nothing is completed,
/// skipped, or created, and `ChoreService.catchUpOverdue` never runs.
///
/// The one thing that DOES change without the app running is which slot a
/// schedule-anchored recurring chore is sitting on — because that is what
/// catch-up will do the moment the user opens the app on that day. So this
/// module mirrors catch-up's rule via
/// [latestScheduledOnOrBefore], rather than replaying the raw recurrence
/// series (which would count one chore several times over, since a chore
/// only ever has ONE pending occurrence).
///
/// Pure, same standard as `lib/domain/recurrence/`: no clock, no I/O, no
/// Flutter, no drift.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/recurrence/recurrence_engine.dart';

/// One pending occurrence, reduced to just the fields the projection needs.
///
/// The application layer maps a `OccurrenceWithChore` onto this (see
/// `lib/application/digest_plan_builder.dart`), which is what keeps this
/// module free of any data-layer import.
class ProjectedOccurrence {
  /// Creates a projection input.
  const ProjectedOccurrence({
    required this.dueDate,
    required this.startDate,
    required this.recurrence,
    required this.assignedMemberId,
  });

  /// The occurrence's current due date.
  final PlainDate dueDate;

  /// The owning chore's start date (the recurrence series' anchor).
  final PlainDate startDate;

  /// The owning chore's recurrence rule, or `null` for a one-off.
  final Recurrence? recurrence;

  /// The member this occurrence is assigned to, or `null` for "anyone".
  final String? assignedMemberId;
}

/// The due/overdue split for a single digest slot's calendar date.
class DigestCounts {
  /// Creates a counts pair.
  const DigestCounts({required this.dueCount, required this.overdueCount});

  /// Occurrences whose projected due date is exactly the queried date.
  final int dueCount;

  /// Occurrences whose projected due date is strictly before the queried
  /// date.
  final int overdueCount;

  /// Whether there is nothing at all to say — the spec's "silence is a
  /// feature" condition, evaluated per day.
  bool get isSilent => dueCount == 0 && overdueCount == 0;

  @override
  bool operator ==(Object other) =>
      other is DigestCounts &&
      other.dueCount == dueCount &&
      other.overdueCount == overdueCount;

  @override
  int get hashCode => Object.hash(dueCount, overdueCount);

  @override
  String toString() =>
      'DigestCounts(dueCount: $dueCount, overdueCount: $overdueCount)';
}

/// The due date [occurrence] would carry on [date], if the app is never
/// opened between now and then.
///
/// A one-off or completion-anchored occurrence simply stays where it is —
/// it goes further overdue, it does not move. A schedule-anchored recurring
/// occurrence rolls forward to the newest series slot on or before [date],
/// which is precisely what `ChoreService.catchUpOverdue` would do on that
/// day; if no slot has come due yet, it stays put.
PlainDate projectedDueDateOn(ProjectedOccurrence occurrence, PlainDate date) {
  final rule = occurrence.recurrence;
  if (rule == null || rule.anchor != RecurrenceAnchor.schedule) {
    return occurrence.dueDate;
  }
  return latestScheduledOnOrBefore(
        rule: rule,
        startDate: occurrence.startDate,
        afterDueDate: occurrence.dueDate,
        notAfter: date,
      ) ??
      occurrence.dueDate;
}

/// The digest counts for [date], over [occurrences], as seen by
/// [recipientMemberId].
///
/// Scoping (spec `docs/specs/notifications.md` N1, triage T2.3): an
/// occurrence counts when it is unassigned ("anyone" — genuinely everyone's
/// business) or assigned to [recipientMemberId]. A `null`
/// [recipientMemberId] means the acting member could not be resolved, in
/// which case everything counts: a digest that hides work because identity
/// is momentarily unknown would be worse than one that shows too much.
///
/// Scoping is applied BEFORE projection, so a partner's chore never
/// influences this recipient's counts no matter how it rolls forward.
DigestCounts projectDigestCounts({
  required Iterable<ProjectedOccurrence> occurrences,
  required PlainDate date,
  required String? recipientMemberId,
}) {
  var dueCount = 0;
  var overdueCount = 0;
  for (final occurrence in occurrences) {
    final assignee = occurrence.assignedMemberId;
    if (recipientMemberId != null &&
        assignee != null &&
        assignee != recipientMemberId) {
      continue;
    }
    final projected = projectedDueDateOn(occurrence, date);
    if (projected == date) {
      dueCount++;
    } else if (projected.isBefore(date)) {
      overdueCount++;
    }
  }
  return DigestCounts(dueCount: dueCount, overdueCount: overdueCount);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/digest_projection_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/digest_projection.dart test/domain/digest_projection_test.dart
git commit -m "Add the pure digest projection with per-recipient scoping"
```

---

## Task 3: Horizon slots and a per-slot planner

**Files:**
- Modify: `lib/domain/digest_planner.dart` (append; `planDigest` stays for now)
- Test: `test/domain/digest_planner_test.dart` (append)

**Interfaces:**
- Consumes: `nextDigestSlot`, `DigestPlan` (both existing)
- Produces:
  - `const int digestHorizonDays = 7;`
  - `List<DateTime> digestSlots({required DateTime now, required int digestMinutes, int horizonDays = digestHorizonDays})`
  - `DigestPlan? planDigestSlot({required DateTime fireAt, required bool enabled, required int dueTodayCount, required int overdueCount})`

- [ ] **Step 1: Write the failing tests**

Append to `test/domain/digest_planner_test.dart`, inside `main()`:

```dart
  group('digestSlots', () {
    test('returns digestHorizonDays consecutive slots by default', () {
      final slots = digestSlots(
        now: DateTime(2026, 7, 24, 7),
        digestMinutes: 480,
      );
      expect(slots, hasLength(digestHorizonDays));
      expect(slots.first, DateTime(2026, 7, 24, 8));
      expect(slots.last, DateTime(2026, 7, 30, 8));
    });

    test('the first slot is exactly nextDigestSlot', () {
      final now = DateTime(2026, 7, 24, 9); // past 08:00
      final slots = digestSlots(now: now, digestMinutes: 480);
      expect(slots.first, nextDigestSlot(now: now, digestMinutes: 480));
      expect(slots.first, DateTime(2026, 7, 25, 8));
      expect(slots.last, DateTime(2026, 7, 31, 8));
    });

    test('every slot keeps the same local wall-clock time across a DST '
        'transition', () {
      // 2026-03-29 is the European spring-forward day. Built from calendar
      // components, so 08:00 stays 08:00 rather than drifting to 09:00.
      final slots = digestSlots(
        now: DateTime(2026, 3, 27, 7),
        digestMinutes: 480,
      );
      for (final slot in slots) {
        expect(slot.hour, 8);
        expect(slot.minute, 0);
      }
    });

    test('rolls over the month boundary', () {
      final slots = digestSlots(
        now: DateTime(2026, 7, 30, 7),
        digestMinutes: 480,
      );
      expect(slots.last, DateTime(2026, 8, 5, 8));
    });

    test('rejects an out-of-range digestMinutes', () {
      expect(
        () => digestSlots(now: DateTime(2026), digestMinutes: 1440),
        throwsArgumentError,
      );
    });

    test('rejects a horizon below one day', () {
      expect(
        () => digestSlots(
          now: DateTime(2026),
          digestMinutes: 480,
          horizonDays: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('planDigestSlot', () {
    final fireAt = DateTime(2026, 7, 25, 8);

    test('disabled returns null even with nonzero counts', () {
      expect(
        planDigestSlot(
          fireAt: fireAt,
          enabled: false,
          dueTodayCount: 3,
          overdueCount: 2,
        ),
        isNull,
      );
    });

    test('zero counts returns null (silence is a feature, per day)', () {
      expect(
        planDigestSlot(
          fireAt: fireAt,
          enabled: true,
          dueTodayCount: 0,
          overdueCount: 0,
        ),
        isNull,
      );
    });

    test('overdue-only still schedules (must not silently rot)', () {
      final plan = planDigestSlot(
        fireAt: fireAt,
        enabled: true,
        dueTodayCount: 0,
        overdueCount: 1,
      );
      expect(plan, DigestPlan(fireAt: fireAt, dueTodayCount: 0, overdueCount: 1));
    });

    test('carries both counts and the exact fireAt through', () {
      final plan = planDigestSlot(
        fireAt: fireAt,
        enabled: true,
        dueTodayCount: 2,
        overdueCount: 1,
      );
      expect(plan!.fireAt, fireAt);
      expect(plan.dueTodayCount, 2);
      expect(plan.overdueCount, 1);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/domain/digest_planner_test.dart`
Expected: FAIL — `The function 'digestSlots' isn't defined`.

- [ ] **Step 3: Implement**

Append to `lib/domain/digest_planner.dart`, immediately after
`nextDigestSlot`:

```dart
/// How many consecutive daily digest slots are armed with the OS at once
/// (spec `docs/specs/notifications.md` architecture #2).
///
/// The digest is a *one-shot* OS notification per day, and nothing re-arms
/// it while the app is closed — so a single slot goes silent the morning
/// after it fires, for exactly the users a reminder exists to serve
/// (`docs/feedback/2026-08-08-prerelease-audit.md` P0). Arming a whole
/// horizon means the digest only degrades after this many consecutive
/// unopened days, and degrades into silence rather than into wrong counts.
///
/// Seven is comfortably inside iOS's 64-pending-notification cap and needs
/// no new platform capability.
const int digestHorizonDays = 7;

/// The next [horizonDays] digest slots after [now]: [nextDigestSlot], then
/// the same local wall-clock time on each following calendar day.
///
/// Built from calendar components rather than `add(Duration(days: 1))` for
/// the same DST reason [nextDigestSlot] documents — and the hour/minute are
/// re-derived from [digestMinutes] rather than read off the first slot,
/// because a spring-forward day can normalize a nonexistent wall-clock time
/// into a different hour, which would then propagate to every later slot.
///
/// [digestMinutes] must be in `0..1439`; [horizonDays] must be >= 1. Throws
/// [ArgumentError] otherwise.
List<DateTime> digestSlots({
  required DateTime now,
  required int digestMinutes,
  int horizonDays = digestHorizonDays,
}) {
  _validateDigestMinutes(digestMinutes);
  if (horizonDays < 1) {
    throw ArgumentError.value(horizonDays, 'horizonDays', 'Must be >= 1');
  }
  final hour = digestMinutes ~/ 60;
  final minute = digestMinutes % 60;
  final first = nextDigestSlot(now: now, digestMinutes: digestMinutes);
  return [
    for (var k = 0; k < horizonDays; k++)
      DateTime(first.year, first.month, first.day + k, hour, minute),
  ];
}

/// Decides whether one already-chosen slot at [fireAt] should fire.
///
/// Returns `null` (don't schedule this day; the caller cancels that day's
/// notification id instead) when [enabled] is `false`, or when both counts
/// are zero — silence is a feature, and with a horizon it is now decided
/// per day rather than once. An overdue-only day still notifies.
///
/// [dueTodayCount] and [overdueCount] must already be computed for
/// [fireAt]'s own calendar date — see
/// `lib/domain/digest_projection.dart`.
DigestPlan? planDigestSlot({
  required DateTime fireAt,
  required bool enabled,
  required int dueTodayCount,
  required int overdueCount,
}) {
  if (!enabled) {
    return null;
  }
  if (dueTodayCount == 0 && overdueCount == 0) {
    return null;
  }
  return DigestPlan(
    fireAt: fireAt,
    dueTodayCount: dueTodayCount,
    overdueCount: overdueCount,
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/domain/digest_planner_test.dart`
Expected: PASS — the pre-existing `planDigest` group still passes too.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/digest_planner.dart test/domain/digest_planner_test.dart
git commit -m "Add digestSlots and planDigestSlot for the digest horizon"
```

---

## Task 4: The shared plan builder

One function, two call sites — this is also the fix for the duplicated
recompute logic that `digest_preprompt_banner.dart:108-115` explicitly
apologises for in a comment.

**Files:**
- Create: `lib/application/digest_plan_builder.dart`
- Test: `test/application/digest_plan_builder_test.dart`

**Interfaces:**
- Consumes: `digestSlots`, `planDigestSlot`, `digestHorizonDays` (Task 3),
  `ProjectedOccurrence`, `projectDigestCounts` (Task 2), `DeviceSettings`
  and `OccurrenceWithChore` (existing data layer)
- Produces: `List<DigestPlan?> buildDigestPlans({required DateTime now, required DeviceSettings settings, required List<OccurrenceWithChore> pending, required String? recipientMemberId})` — always exactly `digestHorizonDays` long, index `k` = slot `k`, `null` = that day is silent

- [ ] **Step 1: Write the failing test**

Create `test/application/digest_plan_builder_test.dart`:

```dart
/// [buildDigestPlans] tests. Integration-style per the project's testing
/// convention: real in-memory `AppDatabase` + real `ChoreService`, so the
/// `OccurrenceWithChore` rows fed in are the exact shape production
/// produces, rather than hand-built drift rows that could drift from it.
///
/// A drift stream is read here via `listen` + `pumpEventQueue()` (the same
/// technique `test/data/repositories/chore_repository_test.dart` uses),
/// never by bare-awaiting it.
library;

import 'package:chore_app/application/digest_plan_builder.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase database;
  late ChoreRepository chores;
  late ChoreService service;
  late String householdId;
  late DeviceSettings settings;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    chores = ChoreRepository(database);
    service = ChoreService(database: database, chores: chores);
    final household = await HouseholdRepository(
      database,
    ).createLocalHousehold('Me');
    householdId = household.id;
    settings = await SettingsRepository(database).ensureSettings();
  });

  tearDown(() => database.close());

  Future<List<OccurrenceWithChore>> pending() async {
    final rows = <List<OccurrenceWithChore>>[];
    final sub = chores.watchPendingOccurrences(householdId).listen(rows.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    return rows.last;
  }

  test('always returns exactly digestHorizonDays entries', () async {
    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, hasLength(digestHorizonDays));
  });

  test('an empty household is silent on every single day', () async {
    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, everyElement(isNull));
  });

  test('a daily chore fills the whole horizon with "1 due"', () async {
    await service.createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      recurrence: Recurrence.everyNDays(1),
    );

    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );

    expect(plans.every((plan) => plan != null), isTrue);
    expect(plans.first!.fireAt, DateTime(2026, 1, 5, 8));
    expect(plans.last!.fireAt, DateTime(2026, 1, 11, 8));
    for (final plan in plans) {
      expect(plan!.dueTodayCount, 1);
      expect(plan.overdueCount, 0);
    }
  });

  test('a one-off is due on its day and overdue on every day after', () async {
    await service.createChore(
      householdId: householdId,
      title: 'Call the plumber',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
    );

    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );

    expect(plans.first!.dueTodayCount, 1);
    expect(plans.first!.overdueCount, 0);
    expect(plans[1]!.dueTodayCount, 0);
    expect(plans[1]!.overdueCount, 1);
    expect(plans.last!.overdueCount, 1);
  });

  test('a disabled digest is null on every day', () async {
    await service.createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      recurrence: Recurrence.everyNDays(1),
    );
    final settingsRepo = SettingsRepository(database);
    await settingsRepo.setDigestEnabled(enabled: false);
    final disabled = await settingsRepo.ensureSettings();

    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: disabled,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, everyElement(isNull));
  });

  test("a partner's fixed chore is invisible to my digest (T2.3)", () async {
    // `createLocalHousehold('Me')` in setUp already inserted an admin
    // member named 'Me' (see `HouseholdRepository.createLocalHousehold`), so
    // only the partner needs seeding here.
    final householdRepo = HouseholdRepository(database);
    final members = <Member>[];
    final sub = householdRepo.watchMembers(householdId).listen(members.addAll);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    final me = members.single;
    final partner = await householdRepo.addMember(
      householdId,
      name: 'Partner',
      color: 0xFF445566,
    );
    await service.createChore(
      householdId: householdId,
      title: "Partner's chore",
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.fixed,
      assigneeMemberIds: [partner.id],
    );
    await service.createChore(
      householdId: householdId,
      title: 'Shared chore',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
    );

    final rows = await pending();
    final mine = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: rows,
      recipientMemberId: me.id,
    );
    final theirs = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: rows,
      recipientMemberId: partner.id,
    );

    expect(mine.first!.dueTodayCount, 1, reason: 'the shared chore only');
    expect(theirs.first!.dueTodayCount, 2, reason: 'shared + their own');
  });
}
```

**Note for the implementer:** this file also needs
`import 'package:chore_app/application/chore_service.dart';`. The helper
signatures used above are verified:
`SettingsRepository.ensureSettings()` → `Future<DeviceSettings>`,
`setDigestEnabled({required bool enabled})`,
`HouseholdRepository.addMember(String householdId, {required String name, required int color, MemberRole role = MemberRole.member})` → `Future<Member>`,
`watchMembers(String householdId)` → `Stream<List<Member>>`.
`Member` comes from `app_database.dart`, already imported.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/application/digest_plan_builder_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:chore_app/application/digest_plan_builder.dart'`.

- [ ] **Step 3: Implement**

Create `lib/application/digest_plan_builder.dart`:

```dart
/// The single place that turns the app's current state into the digest's
/// whole scheduling horizon (spec `docs/specs/notifications.md`
/// architecture #2).
///
/// Deliberately a free function with no Riverpod dependency, because it has
/// two callers that cannot share a controller: `DigestRescheduleController`
/// in `lib/app/providers.dart` (which owns the debounced reschedule wiring
/// and is only ever activated from `main.dart`) and
/// `DigestPrepromptBanner` in `lib/features/chores/` (a widget, which must
/// never read that controller). Before this existed, the banner carried a
/// hand-copied duplicate of the recompute logic.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';

/// The digest plan for each of the next [digestHorizonDays] slots.
///
/// The returned list is ALWAYS exactly [digestHorizonDays] long: index `k`
/// is slot `k` (0 = the next slot), and a `null` entry means that day is
/// silent and its notification id must be cancelled rather than scheduled
/// (see `NotificationScheduler.applyDigestPlans`).
///
/// [pending] is the household's current pending occurrences (i.e.
/// `pendingOccurrencesProvider`'s value). [recipientMemberId] is the
/// acting member's id, or `null` when it can't be resolved — see
/// [projectDigestCounts] for what each means.
List<DigestPlan?> buildDigestPlans({
  required DateTime now,
  required DeviceSettings settings,
  required List<OccurrenceWithChore> pending,
  required String? recipientMemberId,
}) {
  final occurrences = [
    for (final row in pending)
      ProjectedOccurrence(
        dueDate: row.occurrence.dueDate,
        startDate: row.chore.startDate,
        recurrence: row.chore.recurrence,
        assignedMemberId: row.occurrence.assignedMemberId,
      ),
  ];
  final slots = digestSlots(now: now, digestMinutes: settings.digestMinutes);
  final plans = <DigestPlan?>[];
  for (final fireAt in slots) {
    final counts = projectDigestCounts(
      occurrences: occurrences,
      date: PlainDate.fromDateTime(fireAt),
      recipientMemberId: recipientMemberId,
    );
    plans.add(
      planDigestSlot(
        fireAt: fireAt,
        enabled: settings.digestEnabled,
        dueTodayCount: counts.dueCount,
        overdueCount: counts.overdueCount,
      ),
    );
  }
  return plans;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/application/digest_plan_builder_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/application/digest_plan_builder.dart test/application/digest_plan_builder_test.dart
git commit -m "Add buildDigestPlans, the shared digest horizon builder"
```

---

## Task 5: Teach the scheduler the whole horizon

**Files:**
- Modify: `lib/application/notification_scheduler.dart:13-16` and `:208-237`
- Modify: `test/application/fake_digest_notification_plugin.dart`
- Test: `test/application/notification_scheduler_test.dart`

**Interfaces:**
- Consumes: `digestHorizonDays`, `DigestPlan` (Task 3)
- Produces:
  - `const int digestNotificationIdBase = 1001;` (renamed from `digestNotificationId`)
  - `final List<int> digestNotificationIds` — `[1001..1007]`
  - `Future<void> NotificationScheduler.applyDigestPlans(List<DigestPlan?> plans)`
  - `FakeDigestNotificationPlugin.pending` (`Map<int, ScheduledCall>`) and `deliverDue(DateTime now)`

- [ ] **Step 1: Give the fake plugin a pending-request model**

The whole point of this plan is "is a notification still armed tomorrow?",
and a write-only `scheduledCalls` log cannot answer that. Modify
`test/application/fake_digest_notification_plugin.dart`: add the field and
method below, and update the two overrides.

```dart
  /// Every currently-armed notification, keyed by id: [zonedSchedule]
  /// replaces the entry for that id, [cancel] removes it, and [deliverDue]
  /// removes the ones the OS would already have shown.
  ///
  /// This models what `pendingNotificationRequests()` reports on a real
  /// device. [scheduledCalls] stays a full append-only history (used for
  /// debounce/burst assertions); this is the *current state*.
  final Map<int, ScheduledCall> pending = {};

  /// Simulates the OS delivering every armed notification whose `fireAt` is
  /// at or before [now], removing it from [pending]. Nothing re-arms them —
  /// which is exactly the behaviour the horizon exists to survive.
  void deliverDue(DateTime now) {
    pending.removeWhere((_, call) => !call.fireAt.isAfter(now));
  }
```

```dart
  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    final call = ScheduledCall(id: id, title: title, body: body, fireAt: fireAt);
    scheduledCalls.add(call);
    pending[id] = call;
  }

  @override
  Future<void> cancel(int id) async {
    cancelCallCount++;
    pending.remove(id);
  }
```

- [ ] **Step 2: Write the failing tests**

In `test/application/notification_scheduler_test.dart`, add this group after
the existing `scheduleDigest` group (leave that group alone — Task 8 removes
it), and replace the whole `cancelDigest` group with the version below:

```dart
  group('applyDigestPlans', () {
    List<DigestPlan?> plansOf(Map<int, DigestPlan> byIndex) => [
      for (var k = 0; k < digestHorizonDays; k++) byIndex[k],
    ];

    test('rejects a list that is not exactly digestHorizonDays long', () {
      expect(
        () => scheduler.applyDigestPlans(const []),
        throwsArgumentError,
      );
    });

    test('slot k schedules id digestNotificationIdBase + k', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
          2: DigestPlan(
            fireAt: DateTime(2026, 7, 26, 8),
            dueTodayCount: 2,
            overdueCount: 0,
          ),
        }),
      );

      expect(plugin.pending.keys, unorderedEquals([1001, 1003]));
      expect(plugin.pending[1001]!.fireAt, DateTime(2026, 7, 24, 8));
      expect(plugin.pending[1003]!.body, '2 chores today');
    });

    test('a null slot cancels that day rather than scheduling it', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
        }),
      );
      expect(plugin.cancelCallCount, digestHorizonDays - 1);
      expect(plugin.pending.keys, [1001]);
    });

    test('a later apply overwrites the whole horizon, silencing days that '
        'no longer have anything to say', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          for (var k = 0; k < digestHorizonDays; k++)
            k: DigestPlan(
              fireAt: DateTime(2026, 7, 24 + k, 8),
              dueTodayCount: 1,
              overdueCount: 0,
            ),
        }),
      );
      expect(plugin.pending, hasLength(digestHorizonDays));

      await scheduler.applyDigestPlans(plansOf({}));
      expect(plugin.pending, isEmpty);
    });

    test('initializes the plugin implicitly, and never requests permission '
        '(spec polish-round-1.md A3)', () async {
      await scheduler.applyDigestPlans(plansOf({}));
      expect(plugin.initializeCallCount, 1);
      expect(plugin.requestPermissionCallCount, 0);
    });

    test('overdue-only and combined bodies survive the move', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 0,
            overdueCount: 1,
          ),
          1: DigestPlan(
            fireAt: DateTime(2026, 7, 25, 8),
            dueTodayCount: 2,
            overdueCount: 1,
          ),
        }),
      );
      expect(plugin.pending[1001]!.body, '1 overdue chore');
      expect(plugin.pending[1002]!.body, '2 chores today · 1 overdue');
      expect(plugin.pending[1001]!.title, 'Famdo');
    });

    test('German locale produces German copy', () async {
      final germanScheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await germanScheduler.applyDigestPlans([
        DigestPlan(
          fireAt: DateTime(2026, 7, 24, 8),
          dueTodayCount: 2,
          overdueCount: 1,
        ),
        for (var k = 1; k < digestHorizonDays; k++) null,
      ]);
      expect(plugin.pending[1001]!.body, '2 Aufgaben heute · 1 überfällig');
    });
  });

  group('cancelDigest', () {
    test('initializes the plugin implicitly if not done already', () async {
      await scheduler.cancelDigest();
      expect(plugin.initializeCallCount, 1);
    });

    test('cancels every id in the horizon, not just the first', () async {
      await scheduler.cancelDigest();
      expect(plugin.cancelCallCount, digestHorizonDays);
      expect(digestNotificationIds, [1001, 1002, 1003, 1004, 1005, 1006, 1007]);
    });

    test('leaves nothing armed', () async {
      await scheduler.applyDigestPlans([
        for (var k = 0; k < digestHorizonDays; k++)
          DigestPlan(
            fireAt: DateTime(2026, 7, 24 + k, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
      ]);
      await scheduler.cancelDigest();
      expect(plugin.pending, isEmpty);
    });

    test('does not request permission (no schedule attempt)', () async {
      await scheduler.cancelDigest();
      expect(plugin.requestPermissionCallCount, 0);
    });
  });
```

Also change the existing assertion at line 56 from `digestNotificationId` to
`digestNotificationIdBase` (the constant is renamed in step 3).

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/application/notification_scheduler_test.dart`
Expected: FAIL — `The method 'applyDigestPlans' isn't defined`.

- [ ] **Step 4: Implement**

In `lib/application/notification_scheduler.dart`, replace the
`digestNotificationId` constant (lines 13-16) with:

```dart
/// The lowest notification id the daily digest owns; horizon slot `k`
/// (0 = the next slot) uses `digestNotificationIdBase + k` (spec
/// `docs/specs/notifications.md` architecture #2).
const int digestNotificationIdBase = 1001;

/// Every notification id the digest horizon owns, in slot order.
///
/// Fixed and exhaustive on purpose: every reschedule rewrites ALL of these
/// (scheduling some, cancelling the rest), so a day that stops having
/// anything to say can never keep a stale notification armed.
final List<int> digestNotificationIds = List<int>.unmodifiable([
  for (var k = 0; k < digestHorizonDays; k++) digestNotificationIdBase + k,
]);
```

Then replace `cancelDigest` (lines 233-237) and add `applyDigestPlans` — keep
`scheduleDigest` exactly as it is for now, changing only its `id:` argument
to `digestNotificationIdBase`:

```dart
  /// Rewrites the digest's ENTIRE scheduling horizon in one go: [plans] is
  /// indexed by slot (0 = the next slot), a non-null entry is scheduled on
  /// id `digestNotificationIdBase + index`, and a `null` entry cancels that
  /// id.
  ///
  /// Rewriting every id on every call — rather than only touching the days
  /// that changed — is what makes the horizon self-correcting: a completed
  /// chore silences its day, and a day whose counts changed gets the fresh
  /// number, with no bookkeeping about what was armed before.
  ///
  /// Deliberately never requests the OS notification permission itself; see
  /// the class doc and spec `docs/specs/polish-round-1.md` A3.
  ///
  /// Throws [ArgumentError] if [plans] is not exactly [digestHorizonDays]
  /// long.
  Future<void> applyDigestPlans(List<DigestPlan?> plans) async {
    if (plans.length != digestHorizonDays) {
      throw ArgumentError.value(
        plans.length,
        'plans.length',
        'Must be exactly digestHorizonDays ($digestHorizonDays)',
      );
    }
    await ensureInitialized();
    final l10n = lookupAppLocalizations(localeResolver());
    for (var k = 0; k < plans.length; k++) {
      final plan = plans[k];
      final id = digestNotificationIdBase + k;
      if (plan == null) {
        await plugin.cancel(id);
      } else {
        await plugin.zonedSchedule(
          id: id,
          title: l10n.appTitle,
          body: _digestBody(l10n, plan),
          fireAt: plan.fireAt,
        );
      }
    }
  }

  /// Cancels every day of the digest horizon.
  Future<void> cancelDigest() async {
    await ensureInitialized();
    for (final id in digestNotificationIds) {
      await plugin.cancel(id);
    }
  }
```

Finally, update the `zonedSchedule` doc on `DigestNotificationPlugin`
(line 43-46) to note the horizon:

```dart
  /// Schedules a one-shot notification titled [title] with body [body], to
  /// fire at [fireAt] (device-local wall-clock time), replacing any
  /// previously-scheduled notification with the same [id].
  ///
  /// Still deliberately one-shot per id: the daily repeat comes from
  /// [NotificationScheduler] arming a whole horizon of distinct ids at
  /// once, NOT from a repeating OS alarm — a repeating alarm could not
  /// honour the spec's "no notification when nothing is due" rule, and
  /// would freeze its body text at whatever the counts were when it was
  /// armed.
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/application/notification_scheduler_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full suite for compile fallout**

Run: `flutter test`
Expected: PASS. (`digestNotificationId` was referenced only in
`notification_scheduler.dart` and `notification_scheduler_test.dart:56`, both
updated above.)

- [ ] **Step 7: Commit**

```bash
git add lib/application/notification_scheduler.dart test/application/notification_scheduler_test.dart test/application/fake_digest_notification_plugin.dart
git commit -m "Schedule the digest as a horizon of ids instead of one shot"
```

---

## Task 6: Wire the controller — and prove the digest survives a day untouched

This is the task the whole plan exists for. **The test in step 2 must fail
before the implementation in step 4 and pass after it** — that is the
regression proof.

**Files:**
- Modify: `lib/app/providers.dart:676-690` (constructor listeners) and
  `:719-759` (`_recompute`)
- Test: `test/app/digest_reschedule_test.dart`

**Interfaces:**
- Consumes: `buildDigestPlans` (Task 4), `applyDigestPlans` (Task 5),
  `actingMemberProvider` (existing, defined above the controller at line 626)
- Produces: no new public API

- [ ] **Step 1: Give this test file the safe teardown helper**

`_recompute` is about to read `actingMemberProvider`, which subscribes
`membersProvider` (another live drift stream) for the container's lifetime.
Copy `_disposeAndClose` verbatim from
`test/app/day_change_catchup_test.dart:88-96` (including its doc comment)
into `test/app/digest_reschedule_test.dart`, and convert all four existing
tests from

```dart
    addTearDown(container.dispose);
    ...
    await database.close();
```

to

```dart
    ...
    await _disposeAndClose(tester, container, database);
```

(dropping the `addTearDown(container.dispose)` line and replacing the
trailing `await database.close();`).

- [ ] **Step 2: Write the failing tests**

Add to `test/app/digest_reschedule_test.dart`. These need `HouseholdRepository`
and `Recurrence` imports — add
`import 'package:chore_app/data/repositories/household_repository.dart';` and
`import 'package:chore_app/domain/recurrence/recurrence.dart';`, plus
`import 'package:chore_app/application/notification_scheduler.dart';` and
`import 'package:chore_app/domain/digest_planner.dart';`.

```dart
  testWidgets(
    'THE REGRESSION (audit P0): after the first slot fires, with NO app '
    'interaction at all, a digest is still armed for the following day',
    (tester) async {
      var currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      // Seed before the container exists: DigestRescheduleController's
      // constructor eagerly listens to bootstrapProvider.
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Water the plants',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);

      // The whole horizon is armed up front, one id per calendar day.
      expect(plugin.pending, hasLength(digestHorizonDays));
      expect(
        plugin.pending[digestNotificationIdBase]!.fireAt,
        DateTime(2026, 1, 5, 8),
      );
      expect(
        plugin.pending[digestNotificationIdBase + 1]!.fireAt,
        DateTime(2026, 1, 6, 8),
      );

      // The OS delivers today's digest. Then NOTHING happens: no mutation,
      // no resume, no launch — the app is never opened again.
      plugin.deliverDue(DateTime(2026, 1, 5, 8));
      currentTime = DateTime(2026, 1, 6, 7);
      await tester.pump(const Duration(hours: 23));

      // Tomorrow's digest is still armed. With a single one-shot id this
      // assertion fails: `pending` is empty here.
      expect(
        plugin.pending.values.map((call) => call.fireAt),
        contains(DateTime(2026, 1, 6, 8)),
        reason: 'the digest must not go silent the day after it fires',
      );
      expect(
        plugin.pending.values.every((call) => call.body == '1 chore today'),
        isTrue,
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'completing the last chore silences the entire horizon',
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      final service = container.read(choreServiceProvider);
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Call the plumber',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pump(digestRescheduleDebounce);
      expect(plugin.pending, isNotEmpty);

      final pendingOccurrence = await container
          .read(choreRepositoryProvider)
          .pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(pendingOccurrence!.id, completedBy: '');
      await tester.pump(digestRescheduleDebounce);

      expect(
        plugin.pending,
        isEmpty,
        reason: 'a one-off has no successor, so every day is now silent',
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    "a partner's fixed chore does not appear in this device's digest (T2.3)",
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      final householdRepo = HouseholdRepository(database);
      final household = await householdRepo.createLocalHousehold('Me');
      // `createLocalHousehold` already inserted an admin member named 'Me',
      // which is what `actingMemberProvider` resolves to.
      final partner = await householdRepo.addMember(
        household.id,
        name: 'Partner',
        color: 0xFF445566,
      );
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: "Partner's chore",
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.fixed,
            assigneeMemberIds: [partner.id],
          );
      await tester.pump(digestRescheduleDebounce);

      // The acting member resolves to the household's first/admin member —
      // not the partner — so this device's digest has nothing to say.
      expect(container.read(actingMemberProvider)!.id, isNot(partner.id));
      expect(plugin.pending, isEmpty);

      await _disposeAndClose(tester, container, database);
    },
  );
```

**Note for the implementer:** `HouseholdRepository.createLocalHousehold(name)`
inserts an admin `Member` with that name as part of the same transaction
(verified — `household_repository.dart:126-170`), so `actingMemberProvider`
resolves to "Me", not to `null`, and the partner's fixed chore is correctly
filtered out. `addMember`'s first argument is positional.

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/app/digest_reschedule_test.dart`
Expected: FAIL — the first test fails at
`expect(plugin.pending, hasLength(digestHorizonDays))` with length 1, because
the controller still schedules a single id.

- [ ] **Step 4: Implement**

In `lib/app/providers.dart`, add the fourth listener to
`DigestRescheduleController`'s constructor:

```dart
  DigestRescheduleController(this._ref) {
    _ref
      ..listen(bootstrapProvider, (previous, next) {
        if (next.hasValue) {
          unawaited(refreshPermissionState());
          triggerRecompute();
        }
      })
      ..listen(pendingOccurrencesProvider, (previous, next) {
        triggerRecompute();
      })
      ..listen(settingsProvider, (previous, next) {
        triggerRecompute();
      })
      // The digest is scoped to the acting member (triage T2.3), so a
      // change of who that is must re-count. Most such changes arrive via
      // `settingsProvider` (the stored id) — but a member being added,
      // renamed or removed can change `actingMemberProvider`'s fallback
      // resolution with no settings write at all.
      ..listen(actingMemberProvider, (previous, next) {
        triggerRecompute();
      });
  }
```

Then replace the body of `_recompute` (everything after the `settings`/
`pending` null guard) with:

```dart
  Future<void> _recompute() async {
    final scheduler = _ref.read(notificationSchedulerProvider);
    await scheduler.ensureInitialized();

    final settings = _ref.read(settingsProvider).value;
    final pending = _ref.read(pendingOccurrencesProvider).value;
    if (settings == null || pending == null) {
      // Either stream hasn't emitted its first value yet; the `ref.listen`
      // callback that eventually delivers it calls [triggerRecompute]
      // again, so nothing is lost by bailing out here.
      return;
    }

    await scheduler.applyDigestPlans(
      buildDigestPlans(
        now: _ref.read(clockProvider).now(),
        settings: settings,
        pending: pending,
        recipientMemberId: _ref.read(actingMemberProvider)?.id,
      ),
    );
  }
```

Add `import 'package:chore_app/application/digest_plan_builder.dart';` to the
import block, and update the class doc comment on
`DigestRescheduleController` — replace *"recomputes the [DigestPlan] for the
current [clockProvider] time and pushes it to [notificationSchedulerProvider]
— scheduling or cancelling the digest notification as appropriate"* with:

```dart
/// [digestRescheduleDebounce] after the last relevant change, rebuilds the
/// digest's whole scheduling horizon (`buildDigestPlans`, scoped to
/// [actingMemberProvider]) for the current [clockProvider] time and pushes
/// all [digestHorizonDays] days of it to [notificationSchedulerProvider] at
/// once — scheduling the days that have something to say and cancelling the
/// days that don't. The horizon is what makes the digest survive the app
/// simply not being opened (spec `docs/specs/notifications.md`
/// architecture #2): every trigger this class listens to requires a running
/// app, so a single-slot schedule went silent the morning after it fired.
```

`nextDigestSlot` and `planDigest` are no longer called from this file (the
doc comment above still *references* `digestHorizonDays`, which keeps the
`digest_planner.dart` import live). Run `flutter analyze` and delete that
import only if it is reported unused. The `plain_date.dart` import stays
either way — `closedTodayOccurrencesProvider` (line 548) uses it.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/app/digest_reschedule_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/app/providers.dart test/app/digest_reschedule_test.dart
git commit -m "Reschedule the whole digest horizon, scoped to the acting member"
```

---

## Task 7: De-duplicate the pre-prompt banner's recompute

**Files:**
- Modify: `lib/features/chores/digest_preprompt_banner.dart:108-153`
- Test: `test/features/chores/digest_preprompt_banner_test.dart` (assertion
  strengthened)

**Interfaces:**
- Consumes: `buildDigestPlans` (Task 4), `applyDigestPlans` (Task 5),
  `actingMemberProvider`
- Produces: no new public API

- [ ] **Step 1: Strengthen the existing test**

In `test/features/chores/digest_preprompt_banner_test.dart`, replace line 178

```dart
      expect(enablePlugin.scheduledCalls, isNotEmpty);
```

with

```dart
      expect(enablePlugin.scheduledCalls, isNotEmpty);
      expect(
        enablePlugin.pending.keys,
        everyElement(isIn(digestNotificationIds)),
        reason: 'the banner must arm the same horizon the controller does',
      );
```

adding `import 'package:chore_app/application/notification_scheduler.dart';`
if it is not already imported.

- [ ] **Step 2: Run to verify it still passes**

Run: `flutter test test/features/chores/digest_preprompt_banner_test.dart`
Expected: PASS — the banner still schedules id 1001 only, which is in the
horizon list, so this is a guard, not a red test. (The real red test for the
horizon is Task 6's.)

- [ ] **Step 3: Implement**

In `lib/features/chores/digest_preprompt_banner.dart`, replace
`_recomputeDigest` (lines 108-153) entirely with:

```dart
  /// Re-runs the same horizon build the `DigestRescheduleController`
  /// (`lib/app/providers.dart`) runs, via the shared
  /// [buildDigestPlans] — this used to be a hand-copied duplicate of that
  /// controller's private recompute, which it cannot call directly (the
  /// controller owns a persistent debounced `Timer` and is activated
  /// exactly once, from `main.dart`, never from the widget tree).
  Future<void> _recomputeDigest(WidgetRef ref) async {
    final scheduler = ref.read(notificationSchedulerProvider);
    await scheduler.ensureInitialized();

    final settings = ref.read(settingsProvider).value;
    final pending = ref.read(pendingOccurrencesProvider).value;
    if (settings == null || pending == null) {
      return;
    }

    await scheduler.applyDigestPlans(
      buildDigestPlans(
        now: ref.read(clockProvider).now(),
        settings: settings,
        pending: pending,
        recipientMemberId: ref.read(actingMemberProvider)?.id,
      ),
    );
  }
```

Replace the imports of `digest_planner.dart` and
`recurrence/plain_date.dart` (lines 11-12) with
`import 'package:chore_app/application/digest_plan_builder.dart';` — neither
is used any more.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chores/digest_preprompt_banner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chores/digest_preprompt_banner.dart test/features/chores/digest_preprompt_banner_test.dart
git commit -m "Share the digest horizon builder with the pre-prompt banner"
```

---

## Task 8: Delete the single-slot API

Now that both call sites are on the horizon API, remove the old one so
nothing can regress back onto it.

**Files:**
- Modify: `lib/domain/digest_planner.dart` (delete `planDigest`)
- Modify: `lib/application/notification_scheduler.dart` (delete
  `scheduleDigest`)
- Modify: `test/domain/digest_planner_test.dart` (delete the `planDigest`
  group)
- Modify: `test/application/notification_scheduler_test.dart` (delete the
  `scheduleDigest` group)

**Interfaces:**
- Consumes: nothing new
- Produces: nothing new (removal only)

- [ ] **Step 1: Confirm there are no remaining callers**

Run: `grep -rn "planDigest(\|scheduleDigest(" lib test e2e`
Expected: only the two definitions and the two test groups about to be
deleted. If anything else appears, wire it onto `buildDigestPlans` /
`applyDigestPlans` first.

- [ ] **Step 2: Delete**

- In `lib/domain/digest_planner.dart`: delete the whole `planDigest`
  function and its doc comment (currently lines 95-133). Keep
  `_validateDigestMinutes`, `nextDigestSlot`, `digestSlots`,
  `planDigestSlot`, `digestHorizonDays`, `DigestPlan`.
- In `lib/domain/digest_planner.dart`'s `DigestPlan` doc, the phrase
  *"`null` (returned by [planDigest] instead of an instance)"* becomes
  *"`null` (returned by [planDigestSlot] instead of an instance)"*.
- In `lib/application/notification_scheduler.dart`: delete the whole
  `scheduleDigest` method and its doc comment.
- In `test/domain/digest_planner_test.dart`: delete the entire
  `group('planDigest', ...)` block (its coverage is now in the
  `planDigestSlot` and `digestSlots` groups).
- In `test/application/notification_scheduler_test.dart`: delete the entire
  `group('scheduleDigest', ...)` block (its coverage — ids, title, fireAt
  passthrough, all four body shapes, German copy — is now in the
  `applyDigestPlans` group).

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: `No issues found!` — in particular no unused-import or
missing-doc-comment infos.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/digest_planner.dart lib/application/notification_scheduler.dart test/domain/digest_planner_test.dart test/application/notification_scheduler_test.dart
git commit -m "Remove the single-slot digest planner and scheduler API"
```

---

## Task 9: Roll the horizon forward at midnight

An app left open for more than `digestHorizonDays` days runs off the end of
its own horizon, because nothing emits when nothing changes. The
day-change timer already exists; it just declines to use it.

**Files:**
- Modify: `lib/app/providers.dart:864-875` (`CatchUpController._runCatchUp`)
  and its class doc (lines 815-819)
- Test: `test/app/day_change_catchup_test.dart:214-263`

**Interfaces:**
- Consumes: `DigestRescheduleController.triggerRecompute` (existing)
- Produces: no new public API

- [ ] **Step 1: Rewrite the failing test**

In `test/app/day_change_catchup_test.dart`, replace the test currently named
`'is a no-op (and triggers no digest recompute) when nothing is overdue'`
with this (same body up to the final assertions):

```dart
    testWidgets(
      'leaves occurrences alone when nothing is overdue, but still rolls '
      'the digest horizon forward',
      (tester) async {
```

and replace its two closing assertions

```dart
        final repo = container.read(choreRepositoryProvider);
        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 20));
        expect(plugin.scheduledCalls, isEmpty);
```

with

```dart
        final repo = container.read(choreRepositoryProvider);
        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 20));
        // Nothing is due inside the horizon (the chore is 15 days out), so
        // the recompute correctly arms nothing...
        expect(plugin.scheduledCalls, isEmpty);
        // ...but it MUST have run: without an unconditional recompute, an
        // app left open longer than digestHorizonDays runs off the end of
        // its own horizon and goes silent.
        expect(
          plugin.cancelCallCount,
          greaterThanOrEqualTo(digestHorizonDays),
        );
```

Add `import 'package:chore_app/domain/digest_planner.dart';` to that file.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/app/day_change_catchup_test.dart`
Expected: FAIL — `cancelCallCount` is below `digestHorizonDays`, because
`_runCatchUp` skipped the recompute when nothing changed.

- [ ] **Step 3: Implement**

In `lib/app/providers.dart`, replace `CatchUpController._runCatchUp`:

```dart
  Future<void> _runCatchUp() async {
    final householdId = _householdId;
    if (householdId == null) {
      return;
    }
    await _ref.read(choreServiceProvider).catchUpOverdue(householdId);
    // Deliberately unconditional, and NOT gated on catch-up having changed
    // something: the digest is armed only `digestHorizonDays` days ahead,
    // so an app left open longer than that with no mutations would run off
    // the end of its own horizon and go silent. A day passing is itself a
    // reason to re-arm.
    _ref.read(digestRescheduleControllerProvider).triggerRecompute();
  }
```

and update the class doc comment — replace the paragraph beginning
*"Catch-up only triggers a digest recompute"* (lines 815-819) with:

```dart
/// Every day-change (and every resume) triggers a digest recompute
/// unconditionally — see [_runCatchUp]. This is what re-arms the digest's
/// rolling horizon for an app that simply stays open, which no other
/// trigger covers.
```

`ChoreService.catchUpOverdue`'s `bool` return is now unused here. Leave the
return value in place — it is documented behaviour of the service and
`test/application/chore_service_test.dart` asserts on it — and just don't
bind it.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/app/day_change_catchup_test.dart`
Expected: PASS (all 3 groups).

- [ ] **Step 5: Run the full suite and analyzer**

Run: `flutter test && flutter analyze`
Expected: PASS / `No issues found!`. If the analyzer flags the now-unused
`bool` return with an `unawaited`/discard info, adjust to
`await _ref.read(choreServiceProvider).catchUpOverdue(householdId);` exactly
as written above (a bare `await` of a `Future<bool>` discards the value
without a lint).

- [ ] **Step 6: Commit**

```bash
git add lib/app/providers.dart test/app/day_change_catchup_test.dart
git commit -m "Recompute the digest on every day change, not only on catch-up"
```

---

## Task 10: Update the spec and the backlog

`docs/specs/notifications.md` is a binding contract, and its architecture #2
trigger list carries the same bug the code did — it never said "after the
digest fires". This task is required, not optional.

**Files:**
- Modify: `docs/specs/notifications.md`
- Modify: `docs/backlog.md`

- [ ] **Step 1: Update `docs/specs/notifications.md` — N1 behavior**

Under `## N1 behavior`, after the *"No notification at all when there is
nothing due and nothing overdue"* bullet, insert:

```markdown
- **The schedule must survive the app not being opened.** The digest is
  armed as a rolling **7-day horizon** (`digestHorizonDays`) of distinct
  one-shot notifications, one per calendar day, ids
  `digestNotificationIdBase + k` = `1001..1007`. Every recompute rewrites
  ALL seven: days with something to say are scheduled, days without are
  cancelled — so the silence rule is evaluated **per day**, not once. Counts
  for a future day are projected by `lib/domain/digest_projection.dart`
  under the assumption that nothing happens in between (which is exactly
  true when the app isn't opened), mirroring `catchUpOverdue`'s roll-forward
  rule for schedule-anchored chores. The digest therefore degrades only
  after 7 consecutive unopened days, and degrades into silence rather than
  into wrong counts. Deliberately NOT a repeating OS alarm
  (`matchDateTimeComponents`): that cannot honour the silence rule, freezes
  its body text, and would require a named `Location` (the
  `flutter_timezone` dependency architecture #3 avoids).
- **The digest is scoped to the device's acting member** (`actingMemberProvider`,
  triage T2.3): an occurrence counts when it is unassigned ("anyone" — that
  is genuinely everyone's business) or assigned to the acting member. Both
  partners must not receive the identical household-wide number. When the
  acting member cannot be resolved, everything counts.
```

- [ ] **Step 2: Update architecture #1**

Replace the `planDigest` code block and the "Scheduling rule" paragraph in
architecture #1 with:

```markdown
1. **Pure planner + projection** — `lib/domain/digest_planner.dart` and
   `lib/domain/digest_projection.dart`, zero deps beyond
   `lib/domain/recurrence/`:
   ```dart
   const int digestHorizonDays = 7;
   List<DateTime> digestSlots({required DateTime now,
       required int digestMinutes, int horizonDays = digestHorizonDays});
   DigestPlan? planDigestSlot({required DateTime fireAt, required bool enabled,
       required int dueTodayCount, required int overdueCount});
   DigestCounts projectDigestCounts({
       required Iterable<ProjectedOccurrence> occurrences,
       required PlainDate date, required String? recipientMemberId});
   ```
   Slot rule: slot 0 is today at digest time if that is still ahead of
   `now`, else tomorrow; slots 1..n are the same local wall-clock time on
   each following calendar day (built from calendar components, so a DST
   transition never shifts the hour). Each slot's counts are projected for
   that slot's own DATE and its silence decision is made independently. The
   planner and projection stay pure; `lib/application/digest_plan_builder.dart`
   (`buildDigestPlans`) is the one place that joins them to real data, and
   is shared by the reschedule controller and the pre-prompt banner.
```

- [ ] **Step 3: Update architecture #2 — the trigger list is the spec bug**

Replace architecture #2's body with:

```markdown
2. **`NotificationScheduler`** — `lib/application/notification_scheduler.dart`:
   wraps `flutter_local_notifications` behind a 3-method interface
   (`ensureInitialized`, `applyDigestPlans(List<DigestPlan?>)`,
   `cancelDigest()`), so everything above the plugin is testable with a
   fake. `applyDigestPlans` takes exactly `digestHorizonDays` entries
   indexed by slot and rewrites every id: non-null → schedule on
   `digestNotificationIdBase + k`, null → cancel it. `cancelDigest` cancels
   the whole horizon.
   Rebuilt (`buildDigestPlans` → `applyDigestPlans`) on: bootstrap, app
   resume, local day change (every day change, NOT only when catch-up
   changed something), any occurrence/chore/settings mutation, and any
   change of acting member — debounced 500ms via the existing stream
   providers (listen, not poll).
   **Every one of those triggers requires the app to be running.** That is
   precisely why the horizon exists: nothing re-arms the digest while the
   app is closed, so a single-slot schedule went silent the morning after it
   fired (`docs/feedback/2026-08-08-prerelease-audit.md` P0). Do not
   "simplify" this back to one notification id.
```

- [ ] **Step 4: Update architecture #3 and the testing section**

In architecture #3, after the `AndroidScheduleMode.inexactAllowWhileIdle`
sentence, add:

```markdown
   Each notification stays a genuine one-shot `zonedSchedule`; the daily
   repeat comes from the 7-id horizon, never from
   `matchDateTimeComponents` (see N1 behavior for why).
```

In `## Testing`, replace the "Scheduler" bullet with:

```markdown
- Scheduler: fake-plugin tests — the fake models `pending` requests by id
  (schedule replaces, cancel removes, `deliverDue` simulates the OS firing
  one), so the horizon is directly assertable. Cover: slot k → id 1001+k, a
  null slot cancels, a later apply silences days that no longer have
  anything to say, reschedule-on-mutation, debounce collapses bursts,
  cancel on disable.
- **The horizon regression test (required):** advance the fake clock past
  the first slot's `fireAt`, deliver it, and — with NO app interaction of
  any kind — assert a notification is still armed for the following day.
  Lives in `test/app/digest_reschedule_test.dart`.
- Projection: pure unit tests — one-off and completion-anchored occurrences
  never move; a schedule-anchored one rolls forward to its latest slot on or
  before the queried date; recipient scoping counts mine + unassigned.
```

- [ ] **Step 5: Update `docs/backlog.md`**

In the A. Release gates table, replace the **A-1** row's "What's wrong" cell
with:

```markdown
**DONE 2026-08-08** (`docs/plans/2026-08-08-daily-digest-scheduling.md`): the digest is now armed as a rolling 7-day horizon of distinct ids, rewritten on every trigger, with counts projected per date and scoped to the acting member. **T2.3 closed with it**
```

T2.3 has no lettered row of its own in `docs/backlog.md` — it is named only
inside the A-1 row's text, which the replacement above already marks closed.
Leave `docs/research/triage.md` and
`docs/feedback/2026-08-08-prerelease-audit.md` unedited: both are dated
historical records, not living trackers.

- [ ] **Step 6: Verify nothing else contradicts the new spec**

Run: `grep -rn "one-shot\|fixed notification id\|1001" docs/specs/ lib/`
Expected: every remaining hit reads as "one-shot *per id*, horizon supplies
the repeat", not "one notification total". Fix any that don't.

- [ ] **Step 7: Commit**

```bash
git add docs/specs/notifications.md docs/backlog.md
git commit -m "Spec the digest scheduling horizon and per-recipient scoping"
```

---

## Task 11: Amend `DESIGN.md` §3 — record the scope-rule deviation

OPD-1's Option A makes "unassigned chores" part of the default digest scope.
`DESIGN.md` §3 currently says the opposite. Specs and design decisions in
this project are binding contracts, so the deviation is written down rather
than silently absorbed.

**Files:**
- Modify: `DESIGN.md` §3 ("Todo list & notifications"), the *Notification
  philosophy* bullet list
- Modify: `docs/backlog.md` section G (follow-up candidate)

- [ ] **Step 1: Replace the scope bullet**

In `DESIGN.md` §3, replace this line:

```markdown
- Scope: "my chores" by default; "unassigned chores" opt-in.
```

with:

```markdown
- Scope: the digest counts **the recipient's own chores plus unassigned
  ("anyone") chores**. *Amended 2026-08-08 (decision OPD-1,
  `docs/plans/2026-08-08-daily-digest-scheduling.md`); this line previously
  read "'my chores' by default; 'unassigned chores' opt-in".* The opt-in
  framing was retired because it was written for the pre-sync,
  single-device era — one phone stood in for the whole household, so
  "unassigned" barely differed from "everything". With per-recipient
  scoping actually implemented (triage T2.3), defaulting "anyone" chores
  OFF would leave a household that assigns everything to "anyone" — the
  common case — with a permanently silent digest, which is a worse failure
  than slight over-inclusion. A genuine per-device toggle remains possible
  later; see backlog G-9.
```

- [ ] **Step 2: Record the follow-up rather than building it**

In `docs/backlog.md`, section **G. Product features**, append a row to the
table:

```markdown
| **G-9** | Digest scope toggle — "include unassigned chores" | The opt-in that `DESIGN.md` §3 originally promised, retired as a *default* by OPD-1 (`docs/plans/2026-08-08-daily-digest-scheduling.md`) rather than as a *capability*. Would be a `settings` boolean feeding `projectDigestCounts`'s recipient predicate — genuinely small, but it is a new settings row, new l10n and new widget tests, and nobody has asked for it. Build it if a real household reports the over-inclusion as noise, not before | S |
```

- [ ] **Step 3: Verify nothing else still states the old rule**

Run: `grep -rn "unassigned" DESIGN.md docs/specs/`
Expected: the only scope-rule statement is the amended §3 bullet and the
`notifications.md` N1 bullet added in Task 10; the two must agree. Fix any
third statement that contradicts them.

- [ ] **Step 4: Commit**

```bash
git add DESIGN.md docs/backlog.md
git commit -m "Amend DESIGN.md 3: digest scope is own plus unassigned chores"
```

---

## Final verification

- [ ] Run: `flutter test` → all green
- [ ] Run: `flutter analyze` → `No issues found!`
- [ ] Run: `grep -rn "planDigest(\|scheduleDigest(\|digestNotificationId\b" lib test`
      → no hits (the constant is `digestNotificationIdBase` now)
- [ ] Confirm by reading `test/app/digest_reschedule_test.dart` that the
      regression test genuinely asserts a notification armed for **day 2**
      *after* day 1's was delivered, with no controller trigger in between.

## Out of scope (do not fold in)

- **A-2 / audit P1** (`todayProvider`, date-derived UI never rolling over at
  midnight). Task 9 touches `CatchUpController._runCatchUp`, which A-2 will
  also touch — whichever lands second should re-read that method rather than
  assume it.
- **A-5 / T1.3** (acting-member misattribution, `markDoneFor`). This plan
  reads `actingMemberProvider` and inherits whatever A-5 does to it.
- **A-4** (reset should cancel the digest), **E-1** (the hardcoded English
  notification channel name). Both live in `notification_scheduler.dart`'s
  neighbourhood and both are separate tickets.
- **G-6 / N2** (per-chore reminders, evening re-reminder). Explicitly
  gated on this landing first.
