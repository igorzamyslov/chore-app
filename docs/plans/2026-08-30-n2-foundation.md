# N2 Foundation (slices 1–3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land schema v13, the pure notification-planning core, and a scheduler
that writes all three notification id ranges in one serialized write — the
dependency chain underneath `docs/specs/notifications-n2.md` slices 4–7.

> ### GOES LIVE: NOTHING
>
> **Thirteen tasks, three slices, and not one of them makes a user-visible
> change.** Every new setting ships OFF or at a default matching today's
> behaviour; nothing here writes `chores.reminder_minutes` (that is slice 4),
> so every reminder and evening plan is `null` on every real device and the
> digest's content is byte-identical. **If you finish this plan and cannot see
> anything happen, that is success, not a bug you introduced.** The wave-4
> handover asked that a plan building machinery across several tasks name the
> task that makes it live; here the honest answer is *none of them*. See
> "What goes LIVE in this plan" below for the two things that *do* change
> (the v13 migration, and 40 extra no-op `cancel` calls per recompute).

**Architecture:** Three layers, bottom-up. (1) drift schema v13 adds five
device-scoped `settings` columns, the synced `chores.reminder_minutes`, and the
device-scoped `reminder_snoozes` table. (2) A new pure domain module
`lib/domain/reminder_planner.dart` holds the §3.1 constants, `applyQuietHours`,
and the reminder/evening planners; `digest_projection.dart` gains Rule D as one
lookup against an armed-date map; `digest_plan_builder.dart` gains
`buildNotificationPlans` computing **reminders → evening → digest** in one pass.
(3) `NotificationScheduler` gains `applyPlans`, which rewrites ids 1001–1024 /
2001–2033 / 3001–3007 inside a **single** enqueued write, and `cancelAll`.

**Tech Stack:** Flutter, Riverpod, drift (+ build_runner), Supabase/PostgREST,
`flutter_local_notifications`, `flutter_test`, gen_l10n, pgTAP.

---

## How to review this plan: three anchors

Everything else here is bookkeeping. If you read only three things, read these.

1. **Task 9's partition proof.** §0.1 made falsifiable rather than restated.
   It compares PRODUCTION output against a test-local oracle loop and asserts
   two things: `armed ⊆ oracle`, and
   `digestTotal + armedOnThisDate.length == oracle.length`. Two disjoint
   subsets whose sizes sum to the whole ARE a partition — so it fails **high**
   on "told twice" and **low** on "told by nobody", in one assertion. The
   oracle is a hand-written loop, deliberately not a call to
   `projectDigestCounts`: an oracle that calls the function under test can only
   ever agree with it.
2. **`reminderOverflowCount` is produced at the single truncation site**
   (Task 6), so `armed.length + overflowCount == eligible` holds **by
   construction**, not by two computations agreeing. That is why the field
   belongs to the planner and not to slice 4's UI. Its discriminating test is
   the 33-armed / 5-out-of-window / 3-overdue fixture that must yield **0**
   where the plausible wrong implementation ("every reminder-enabled chore
   minus the armed ones") yields 8.
3. **Goes live: nothing** — see the box above.

**Three inversions in this plan are BLOCKING.** They are marked as such at
their steps: Task 6 step 5 inversion 3, and Task 9 step 4 inversions 1 and 3.
If any of them fails to turn a test red, the test it targets cannot fail and is
worth nothing however well it reads — fix the test before the task is
considered done. Wave 6 found four tests of exactly that shape.

## Global Constraints

Copied from the spec and from this repo's standing rules. **Every task's
requirements implicitly include this section.**

- **The binding contract is `docs/specs/notifications-n2.md`.** The design is
  settled. Do not redesign; if something reads as a gap, check
  "Interpretation notes" below before inventing an answer.
- **The invariant (§0.1, the partition):** for every calendar date `D` in the
  digest horizon and every in-scope pending occurrence `X` — **either** `X` is
  counted by the digest slot firing on `D`, **or** a reminder for `X` is armed
  to fire on `D`. Never both. Never neither.
- **Id budget (§3.1), all derived, never literals:**
  `n2NotificationIdBudget = 40`, `eveningHorizonSlots = 7`,
  `reminderCeiling = n2NotificationIdBudget - eveningHorizonSlots` (33),
  `reminderNotificationIdBase = 2001`, `eveningNotificationIdBase = 3001`,
  `reminderArmWindowDays = 14`, `defaultReminderMinutes = 1080`.
  `digestNotificationIdBase = 1001` and `digestHorizonSlots = 24` are unchanged.
  Total is exactly 64 with no slack.
- **Migration existence assertions use `PRAGMA table_info`** (§8.4). Drift maps
  an ABSENT nullable column to `null` on read, so `expect(row.col, isNull)`
  passes whether or not the migration ran. That vacuity is why every column
  assertion below is a name-set assertion.
- **`settings` is device-scoped and NOT synced. `chores` IS synced**, so
  `reminder_minutes` needs both row mappers plus a Supabase migration.
  `reminder_snoozes` is device-scoped and unsynced.
- **PostgREST:** `.upsert()` checks UPDATE privilege on every payload column at
  plan time; against column-restricted grants use `ignoreDuplicates: true`.
  Use `.isFilter('deleted_at', null)`, never `.eq(...)`.
- **pgTAP:** `supabase test db` does NOT apply migrations — `supabase db reset`
  first. `test_login()` sets `role=authenticated` for the rest of the
  transaction, so `reset role;` before any superuser statement. UUIDs are hex
  only. `is(<no such row>, null)` passes VACUOUSLY.
- **Notification writes are serialized through one queue** (backlog G-12).
  Anything scheduled must ride it or it races.
- **`db.yml` runs pgTAP only when the diff touches `supabase/**`.** A Dart-only
  push reports a fast green WITHOUT running any SQL.
- **Any drift table change needs `dart run build_runner build`.** Generated
  drift code is never hand-written.
- **Lints:** very_good_analysis, `flutter analyze --fatal-infos
  --fatal-warnings`. Every public member needs a doc comment.
- **Test command:**
  `flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <file>`
- **Widget-test helpers are never hand-rolled.** `testChoreApp` and
  `find.bySemanticsIdentifier` live in `test/test_utils/pump_app.dart`;
  `openSettingsTab` lives in `test/features/settings/settings_test_utils.dart`.
  Never hand-roll a `ProviderScope` pump — it HANGS and takes the suite with it.
  (No task in this plan needs a widget test; this is here so nobody adds one
  from memory.)
- **Commit messages carry no `Co-Authored-By:` trailer.**

## What goes LIVE in this plan: nothing

**Honest answer: no task here makes any user-visible behaviour live.** Every
new `settings` column ships OFF or at a default that matches today's behaviour
(quiet hours off, evening re-reminder off); nothing in slices 1–3 writes
`chores.reminder_minutes` (the chore-form row is slice 4), so
`buildNotificationPlans` returns 33 null reminder plans and 7 null evening
plans on every real device, and `applyPlans` therefore cancels 40 ids that were
never armed. The digest's own content is byte-identical.

Two things *do* change in production and are worth naming so nobody is
surprised:

1. **Schema v13 runs on every install** on first launch after the update
   (Task 1–3). It is additive: five defaulted columns, one nullable column, one
   new empty table. No data rewrite.
2. **Each recompute issues 40 extra `cancel` platform calls** (Task 11/13).
   Harmless — cancelling an unarmed id is a no-op — but observable in call
   counts, which is why the existing cost-bound tests are re-verified in
   Task 13 rather than assumed.

## Interpretation notes (gaps the spec left to the implementer)

These are engineering resolutions, **not** product decisions. Each names the
spec line it serves.

1. **`buildNotificationPlans` needs a snoozes argument.** §9.1 gives the
   signature `({now, settings, pending, recipientMemberId})` but §2.3 step 3
   requires reading `reminder_snoozes`. A pure function cannot query drift, so
   the signature gains
   `required Map<String, DateTime> snoozedUntilByOccurrenceId` (the caller
   reads it; `const {}` is a legal empty value). Same shape as `pending`
   already being passed in.
2. **`reminder_planner.dart` imports `digest_projection.dart`.** §9.1's import
   list says "`dart:core` plus `lib/domain/recurrence/`", but §2.3 step 1 says
   the roll-forward must be **the same** `latestScheduledOnOrBefore` path
   `digest_projection.dart` uses. Re-implementing it would be a second copy of
   the rule the two channels must agree on, which §0.1 forbids in substance.
   `digest_projection.dart` and `digest_planner.dart` are both pure, so
   importing them keeps the purity standard §9.1 is actually asking for. It
   also imports `digest_planner.dart` to reuse `digestSlots` for the evening
   horizon.
3. **`ProjectedOccurrence` gains `choreId`, `choreTitle` and
   `reminderMinutes`.** D4's tiebreak is "lowest **chore** id", which the type
   does not carry today; §2.3 needs `reminder_minutes`; §11 makes the reminder
   title "the chore title verbatim". `choreId`/`choreTitle` are **required**
   for the reason the existing doc comment gives for `id` (the compiler must
   name every construction site); `reminderMinutes` defaults to `null`.
4. **Rule D is a parameter, not a re-derivation.** `projectDigestCounts` gains
   `Map<String, PlainDate> armedReminderDates = const {}` and skips an
   occurrence whose entry equals the queried date — **before** bucketing, so
   the omission follows the reminder into whichever bucket the occurrence is in
   (§2.4's "general form"). Defaulting to `const {}` is what keeps the existing
   monotonicity group compiling verbatim (§2.5, §13.1).
5. **Evening plans are built in slice 2, not slice 6.** §9.1 requires
   `buildNotificationPlans` to return all three lists and §13.1 lists the
   evening-slot rules under pure unit tests; slice 6 adds only the Settings UI.
   They are all-null in production until the setting is turned on.
6. **`applyDigestPlans` survives; `cancelDigest` does not.** §9.2 allows narrow
   wrappers "only if nothing outside the scheduler calls them" — but
   `DigestPrepromptBanner._enable` and `rewriteDigestHorizon` both call
   `applyDigestPlans`, and §10.1 explicitly forbids the isolate from rewriting
   more than it must. So `applyDigestPlans` stays public and digest-only, while
   `cancelDigest` **becomes** `cancelAll` (all three ranges) with no wrapper —
   a wipe that leaves reminders armed is what §9.2 calls strictly worse than
   G-12's bug.
7. **Slice 3 schedules reminders/evening with no action and no payload.**
   Actions (`reminder.done`, `reminder.snooze`, `evening.done`) and payload
   `v:2` are slice 7. Do **not** attach `digestDoneActionId` to a reminder —
   `notifications.md` requires each new surface to mint its own action id.
   `EveningPlan.soleOccurrenceId` is computed now (§5) and simply unused by the
   scheduler until slice 7.
8. **The two new Android channels ARE in slice 3**, because a notification
   cannot be scheduled without a channel and §9.3 forbids reusing the digest's.
   Android caches channel copy at creation and cannot rename, so getting
   `reminders_v1` / `evening_v1` and their localized copy right now is
   effectively one-shot (see `digestChannelId`'s doc comment). The iOS
   `reminderActions` / `eveningActions` categories are **not** in slice 3 —
   they exist only to carry actions.

9. **`NotificationPlanSet` carries `reminderOverflowCount`** — how many
   reminder-eligible occurrences the §3.2 ceiling turned away. Added to §9.1's
   plan set on the coordinator's instruction, and it belongs here rather than
   in slice 4: the alternative is re-deriving §2.3's whole arming rule at the
   UI layer, which puts two copies of that rule in the tree.
   - It is **not derivable** from the three plan lists. At the ceiling
     `reminders` holds exactly `reminderCeiling` entries whether one chore
     overflowed or ninety did, so the number has to be carried.
   - It is produced at the **single truncation site** inside `planReminders`
     (Task 6), from the same list that produces `armed`, so
     `armed.length + overflowCount == eligible count` by construction and the
     two cannot disagree.
   - It counts **ceiling losses only** — not occurrences excluded by the
     14-day window (D3), the already-overdue rule (D8), recipient scoping
     (§2.2) or having no `reminder_minutes`. Those never competed for a slot,
     and slice 4's sub-line ("N chores stayed in the daily summary because
     this device can hold 33 reminders at once") is only true of ceiling
     losses.
   - Two tests in Task 6 discriminate on exactly that: a fixture of 33 armed
     + 5 out-of-window + 3 overdue must yield **0**, and a fixture of 40
     in-window + 5 out-of-window must yield **7**. The plausible wrong
     implementation ("every reminder-enabled chore minus the armed ones")
     yields 8 and 12 and is caught by both. Task 6 step 5 inversion 3 runs
     precisely that wrong implementation and requires it to go red.
   - **Slice 4 consumes it and cites §9.1**; it must never construct it.

## Task 0 corrections (refresh pass, 2026-08-30, wave-7 implementer)

Everything below was found by re-reading the code this plan cites, as it
actually stands on `integration/wave-7` (`28d38bc`). Each is a correction to
this plan, not a redesign of the spec.

1. **§6's "quiet hours apply to the digest as well" was NOT planned.** The
   spec is explicit — "Quiet hours apply to the **digest** as well, which is
   a behaviour change to a shipped feature and so is stated deliberately" —
   and D7 names the digest first in "deferred, never dropped". This plan's
   self-review maps §6 onto Tasks 4 and 5, but Task 5 only *builds*
   `applyQuietHours` and nothing ever applies it to a digest slot. That is an
   omission, not a decision (no interpretation note claims it), so **Task 9
   now shifts each digest slot moment through `applyQuietHours` before
   computing that slot's counts**, and the counts are computed for the
   SHIFTED date. Consequences, all checked:
   - Slots stay pairwise distinct: slot `k` at 23:30 on day `k` defers to
     07:00 on day `k+1`, and slot `k+1` defers to day `k+2`. Two slots can
     never land on one date.
   - Rule D stays coherent, because it was already keyed on a calendar date
     that both channels compute the same way.
   - Nothing ships changed: quiet hours default OFF, and the shipped 08:00
     digest is outside the default 22:00–07:00 window anyway (§6's own
     closing paragraph).
   - `buildDigestPlans` (the digest-only wrapper) gets the shift too. Its two
     callers already pass real `DeviceSettings`, so they stay consistent with
     the recompute rather than drifting from it.

2. **Task 11's "ONE enqueued write, not three" test cannot fail.** Its
   assertion is that the later caller's title wins, and that is FIFO, which
   holds in BOTH shapes: `_enqueueNotificationWrite` is synchronous, so
   splitting `applyPlans` into three chained enqueues still leaves A's
   reminder write ahead of B's reminder write. The test would stay green
   through the very inversion it exists to catch — wave 6's failure shape
   exactly. **Replaced** with a test of the property D9 actually names (a
   *window* between two writes): gate the first `cancel`, let `applyPlans`
   pause inside the digest range, enqueue `cancelAll()` behind it, release,
   and assert `plugin.pending` is empty. With three sub-writes the reminder
   and evening ranges are written AFTER the cancel and stay armed, so it goes
   red. See Task 11 step 1.

3. **Task 9's partition test skipped every `null` digest slot, which is a
   hole in the invariant it exists to prove.** A `null` slot is a slot whose
   counts are zero — that is an answer, not the absence of one — so the
   identity must be asserted on it too. As written, an over-omitting Rule D
   that drove a slot to zero would be silently skipped. The walk now derives
   the slot moments independently (from `digestSlots`, shifted by
   `applyQuietHours` per correction 1), asserts each non-null plan's `fireAt`
   agrees with the derived moment, and treats a `null` plan as
   `digestTotal == 0`.

4. **`test/application/digest_plan_builder_test.dart` has no `_settings()`,
   `_row()` or `_reminderAt()` helpers**, and its own doc comment says it is
   integration-style on purpose: real in-memory `AppDatabase` + real
   `ChoreService`, so `OccurrenceWithChore` rows are the exact shape
   production makes. Task 9's partition fixture cannot be built that way — it
   needs ~45 rows with DETERMINISTIC chore ids (D4's tiebreak is "lowest
   chore id", and the ceiling test names a specific loser), and
   `ChoreRepository.newId` hands out UUIDs. Resolution, recorded rather than
   improvised: the new groups add hand-built `_row`/`_reminderAt` helpers
   constructing `Chore`/`ChoreOccurrence` directly, and `_settings(...)` is a
   `copyWith` over the REAL `ensureSettings()` row from `setUp` (never a
   hand-built `DeviceSettings` literal, which would rot the moment a column
   is added). Every pre-existing test in the file is left untouched and still
   integration-style.

5. **Task 13's fixture cannot set `reminder_minutes` through the service.**
   `ChoreService.createChore` has no such parameter and adding one is slice
   4's job (the chore form). Use `ChoreRepository.updateChore(id,
   reminderMinutes: Value(1080))` instead — Task 2 adds exactly that.

6. **`schema_migration_test.dart` has ELEVEN tests, ten of which rewind below
   13** (`1 -> 2`, `3 -> 12`, `2 -> 12`, `5 -> 12`, `6 -> 12`, `7 -> 12`,
   `8 -> 12`, `9 -> 12`, `10 -> 12`, `11 -> 12`, plus the fresh-database one
   that rewinds nothing). Tasks 1–3 name only four of them. All ten need the
   collateral drops, and the `10 -> 12` test — which the plan never mentions
   — is one of them.

7. **Task 4 step 4 inversion 2 is a compile guard, not a test red.** Removing
   the five fields from `ensureSettings`'s hand-built `DeviceSettings`
   literal fails at analysis because drift makes non-nullable columns
   required constructor parameters. The plan says as much; it is recorded
   here so it is not counted as inversion evidence. Inversion 1
   (`setQuietHours` writing one end) is this task's real red.

8. Line-number drift, all harmless and all corrected in place where a step
   quotes one: `app_database.dart`'s `from < 12` block ends at ~140 (plan
   says ~137); `projectDigestCounts` is at 157–190 (plan says 160–194);
   `DigestRescheduleController._recompute` is at 1294–1322 (plan says
   1290–1317). `ProjectedOccurrence.id`'s doc comment says "there are only
   two construction sites in the tree" and becomes three — Task 6 updates it.

## Closed product decisions

**OQ-P1 — Does the B1 backup document include `reminder_snoozes`? CLOSED
2026-08-30 by the product owner: NO.** Recorded closed rather than deleted, so
the reasoning survives and nobody re-opens it from the options alone.

A snooze is device-scoped, transient notification bookkeeping — "I pushed this
notification to tomorrow" — not household data. The export exists so a user
keeps the things they *created*: chores, occurrences, members, categories,
shopping. Restoring a snooze would resurrect a deferral against an occurrence
that may no longer exist, or that may have been completed on another device in
the meantime — worse than losing it. And its absence costs the user nothing
they would notice.

**Copy audit, run before closing this** (this project has twice shipped copy
that promised what the mechanism did not do — the chore-delete dialog claiming
history was kept when nothing could show it, and the archive copy implying a
restorability that did not exist). Checked: `docs/specs/polish-round-1.md` B1,
`lib/features/settings/export_row.dart`, and every export string in
`app_en.arb`/`app_de.arb`.

**Finding: the user-facing copy is already scoped to household data and claims
no completeness. The exclusion contradicts nothing, and no copy task is
needed.** Specifically:

- The row itself carries a label and nothing else — `settingsExportEntry`,
  "Export data" / "Daten exportieren". `ExportDataTile` passes no subtitle, so
  there is no second line to over-promise in.
- `settingsExportError` is a generic failure string.
- The two places that *point* at the export are the delete-account
  confirmations, and both are scoped: `accountDeleteFinalBodyKeepPhone` says
  "to keep **a copy of your data** somewhere else", and
  `accountDeleteFinalBodyDeletePhone` enumerates the scope explicitly —
  "**members, chores and shopping list**". Neither says "everything", "all your
  data" or "a full backup".
- Spec B1 lists the exact `tables` key set and does not include
  `reminder_snoozes`; it is consistent with the exclusion as written.

**One inaccuracy found, and it is not user-facing:** the ARB `@description` on
`settingsExportEntry` reads "shares a full JSON backup of **every table**".
That is a developer-facing note, invisible to users — but it is exactly the
sentence a future implementer would read as licence to add a table, so Task 3
corrects it in one line rather than leaving a stale claim behind.

---

# Slice 1 — Schema v13

Four tasks. All three schema additions land at `schemaVersion 13`; Task 1 is
the one that bumps the version, Tasks 2 and 3 add more work under the same
`from < 13` guard.

### Task 1: The five `settings` columns (§8.1)

**Files:**
- Modify: `lib/data/db/tables.dart` (class `Settings`, after
  `pendingJoinCode`, before `createdAt`)
- Modify: `lib/data/db/app_database.dart:56` (`schemaVersion`) and the
  `else` branch of `onUpgrade` (after the `from < 12` block, ~line 137)
- Regenerate: `lib/data/db/app_database.g.dart` (build_runner; never hand-edit)
- Test: `test/data/db/schema_migration_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `DeviceSettings.quietHoursEnabled` (`bool`),
  `.quietStartMinutes` (`int`), `.quietEndMinutes` (`int`),
  `.eveningReminderEnabled` (`bool`), `.eveningReminderMinutes` (`int`);
  `SettingsCompanion` fields of the same names; `schemaVersion == 13`.

- [ ] **Step 1: Add the five columns to the `Settings` table**

In `lib/data/db/tables.dart`, inside `class Settings extends Table`, directly
after the `pendingJoinCode` getter and before `createdAt`:

```dart
  /// Whether quiet hours are active (spec `docs/specs/notifications-n2.md`
  /// §6). Default `false`, so upgrading to schemaVersion 13 changes the
  /// behaviour of exactly zero installs until someone opens Settings.
  /// Added in schemaVersion 13; see `AppDatabase.migration`.
  BoolColumn get quietHoursEnabled =>
      boolean().withDefault(const Constant(false))();

  /// The start of the quiet-hours window, as minutes since local midnight
  /// (default `1320` = 22:00). The window WRAPS midnight in the normal
  /// case and must be evaluated as a wrapping interval, never as a numeric
  /// range; `quietStartMinutes == quietEndMinutes` is treated as OFF, not
  /// as a 24-hour window (spec `docs/specs/notifications-n2.md` §6). The
  /// single implementation of that rule is `applyQuietHours` in
  /// `lib/domain/reminder_planner.dart`. Added in schemaVersion 13.
  IntColumn get quietStartMinutes =>
      integer().withDefault(const Constant(1320))();

  /// The end of the quiet-hours window, as minutes since local midnight
  /// (default `420` = 07:00) -- see [quietStartMinutes]. Added in
  /// schemaVersion 13.
  IntColumn get quietEndMinutes => integer().withDefault(const Constant(420))();

  /// Whether the evening re-reminder is enabled (spec
  /// `docs/specs/notifications-n2.md` §5). **Ships OFF** (D12): the
  /// governing principle is digest by default, never nag, and defaulting a
  /// second daily notification to on would impose a behaviour change on
  /// every existing user who never asked for one. Added in schemaVersion
  /// 13.
  BoolColumn get eveningReminderEnabled =>
      boolean().withDefault(const Constant(false))();

  /// The evening re-reminder's fire time, as minutes since local midnight
  /// (default `1200` = 20:00 -- an hour clear of the 22:00 quiet-hours
  /// default, so a user turning the feature on with defaults gets a working
  /// feature, spec `docs/specs/notifications-n2.md` §5.1). Added in
  /// schemaVersion 13.
  IntColumn get eveningReminderMinutes =>
      integer().withDefault(const Constant(1200))();
```

- [ ] **Step 2: Bump `schemaVersion` and regenerate**

In `lib/data/db/app_database.dart`, change line 56 to:

```dart
  int get schemaVersion => 13;
```

Then regenerate (this is the only legal way to change `app_database.g.dart`):

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `Succeeded after ...` with `app_database.g.dart` written.

- [ ] **Step 3: Write the failing migration assertions**

In `test/data/db/schema_migration_test.dart`, add the collateral-drop helper
after `_dropPendingJoinCodeColumn` (the seed always opens at the *current*
schema first, so every test that rewinds below 13 must drop these or the
upgrade throws a duplicate-column error):

```dart
/// Drops the five schemaVersion 13 `settings` columns (spec
/// `docs/specs/notifications-n2.md` §8.1) on [seed] -- mirrors
/// `_dropPendingJoinCodeColumn`'s reasoning for the same collateral-drop
/// pattern, five columns wide.
Future<void> _dropN2SettingsColumns(AppDatabase seed) async {
  for (final column in const [
    'quiet_hours_enabled',
    'quiet_start_minutes',
    'quiet_end_minutes',
    'evening_reminder_enabled',
    'evening_reminder_minutes',
  ]) {
    await seed.customStatement('ALTER TABLE settings DROP COLUMN $column');
  }
}
```

Extend the shared name list (`_settingsColumnsAddedAfterV2`, line 95) with the
five new names:

```dart
  'pending_join_code', // v12
  'quiet_hours_enabled', // v13
  'quiet_start_minutes', // v13
  'quiet_end_minutes', // v13
  'evening_reminder_enabled', // v13
  'evening_reminder_minutes', // v13
];
```

Call `await _dropN2SettingsColumns(seed);` in the seed of **every** test that
rewinds `user_version` below 13 — that is every test in the file **except**
the `1 -> 2` one, which drops the whole `settings` table (so there is nothing
to drop separately) and the fresh-database one (which never rewinds). Place
the call next to the existing `await _dropPendingJoinCodeColumn(seed);` line in
each.

Then add the value + existence assertions. In the `11 -> 12` test — retitle it
to `schemaVersion 11 -> 13` — after the existing `pendingJoinCodeColumns`
assertion:

```dart
      // The five v13 columns arrive with their spec defaults (spec
      // `docs/specs/notifications-n2.md` §8.1) -- both features OFF, so
      // this upgrade changes no install's behaviour.
      expect(row.quietHoursEnabled, isFalse);
      expect(row.quietStartMinutes, 1320);
      expect(row.quietEndMinutes, 420);
      expect(row.eveningReminderEnabled, isFalse);
      expect(row.eveningReminderMinutes, 1200);
      // Existence, not just default value. `quietHoursEnabled` and
      // `eveningReminderEnabled` are non-nullable and so self-guard, but
      // the three INTEGER columns do not read as vacuously as a nullable
      // one only because they carry defaults -- assert the names on disk
      // and nobody has to work out which is which (§8.4).
      final n2Columns = await _columnNames(upgraded, 'settings');
      expect(n2Columns, containsAll(_settingsColumnsAddedAfterV2));
```

Add a new test pinning the else-branch placement, modelled on the existing
`membership_revoked` / `pending_join_code` shape (place it after the
`11 -> 12` test):

```dart
  test(
    'the five v13 settings columns are added exactly once on a 12 -> 13 '
    'upgrade -- they live inside the settings `else` branch, because '
    '`settings` did not exist before v2',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v13_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v12 install -- the schema every shipped
      // build (0.9.0) is actually running: open the *current* (v13) schema
      // once so `onCreate` materializes every table at full v13 width,
      // insert a settings row with non-NULL actingMemberId/syncHouseholdId
      // (so the "existing row survives" guarantee is exercised), then drop
      // only the five v13 columns and roll `user_version` back to 12.
      // Deliberately no `_dropStatusClosedOnIndex` here: at `from == 12`
      // the `from < 11` branch never runs, so the index must STAY.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
              syncHouseholdId: const Value('household-1'),
            ),
          );
      await _dropN2SettingsColumns(seed);
      await seed.customStatement('PRAGMA user_version = 12');
      await seed.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.quietHoursEnabled, isFalse);
      expect(row.quietStartMinutes, 1320);
      expect(row.quietEndMinutes, 420);
      expect(row.eveningReminderEnabled, isFalse);
      expect(row.eveningReminderMinutes, 1200);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.syncHouseholdId, 'household-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);

      // Exactly one of each on disk -- this, not the value assertions
      // above, is what proves the migration ran (§8.4).
      final columns = await upgraded
          .customSelect("PRAGMA table_info('settings')")
          .get();
      final names = columns.map((row) => row.read<String>('name')).toList();
      for (final column in const [
        'quiet_hours_enabled',
        'quiet_start_minutes',
        'quiet_end_minutes',
        'evening_reminder_enabled',
        'evening_reminder_minutes',
      ]) {
        expect(
          names.where((name) => name == column),
          hasLength(1),
          reason: '$column must be added exactly once',
        );
      }
    },
  );
```

- [ ] **Step 4: Run the tests and watch them go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/db/schema_migration_test.dart
```

**Expected RED, precisely:** every rewinding test fails inside `onUpgrade`
with `SqliteException(1): no such column: quiet_hours_enabled` — drift's
`addColumn` has not been written yet, so `_columnNames`'s `containsAll` reports
the five missing names, and the new `12 -> 13` test fails its
`hasLength(1)` loop on `quiet_hours_enabled` with `Actual: []`. **Not** an
analyzer failure: the columns exist on the Dart side already (Step 1), so this
is a genuine behavioural red on the migration path.

- [ ] **Step 5: Add the migration branch**

In `lib/data/db/app_database.dart`, inside the `else` branch of `onUpgrade`,
after the `if (from < 12)` block:

```dart
        if (from < 13) {
          // v12 -> v13 (spec `docs/specs/notifications-n2.md` §8.1): quiet
          // hours (3 columns) and the evening re-reminder (2 columns), all
          // with defaults, no data rewrite. Both features default OFF, so
          // this upgrade changes the behaviour of exactly zero installs
          // until someone opens Settings.
          //
          // Lives here, inside the `else` branch, for exactly the reason
          // spelled out for `membershipRevoked` and `pendingJoinCode`
          // above: `settings` did not exist before v2, so a v1 -> v13 jump
          // builds the table at full current width via [createTable], and a
          // second unconditional `addColumn` for the same column would
          // throw a duplicate-column error. §8.1 states this placement is
          // not a free choice.
          await migrator.addColumn(settings, settings.quietHoursEnabled);
          await migrator.addColumn(settings, settings.quietStartMinutes);
          await migrator.addColumn(settings, settings.quietEndMinutes);
          await migrator.addColumn(settings, settings.eveningReminderEnabled);
          await migrator.addColumn(settings, settings.eveningReminderMinutes);
        }
```

- [ ] **Step 6: Run the tests and watch them go GREEN**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/db/schema_migration_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: INVERT the implementation and confirm the tests catch it**

Temporarily move the whole `if (from < 13) { ... }` block from inside the
`else` branch to the flat/unconditional region (next to the `from < 11`
index block). Re-run the same command.

**Expected RED at the test step:** the `1 -> 2` test fails with
`SqliteException(1): duplicate column name: quiet_hours_enabled` — the flat
placement duplicate-adds on a v1 jump, which is precisely the trap §8.1
names. Restore the block to the `else` branch and confirm green again.

- [ ] **Step 8: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/data/db/tables.dart lib/data/db/app_database.dart \
  lib/data/db/app_database.g.dart test/data/db/schema_migration_test.dart
git commit -m "Add schema v13's five device-scoped notification settings columns"
```

### Task 2: `chores.reminder_minutes` — the one synced field (§8.2)

**Files:**
- Modify: `lib/data/db/tables.dart` (class `Chores`, after `pausedAt`)
- Modify: `lib/data/db/app_database.dart` (`onUpgrade`, flat/unconditional
  region — **outside** the `settings` `else`)
- Modify: `lib/data/repositories/chore_repository.dart` (`createChore`,
  `updateChore`)
- Modify: `lib/data/sync/row_mappers.dart:94-133` (`choreRow`, `choreFromRow`)
- Create: `supabase/migrations/20260830120000_chore_reminder_minutes.sql`
- Create: `supabase/tests/003_chore_reminder_minutes_test.sql`
- Regenerate: `lib/data/db/app_database.g.dart`
- Modify: `test/data/db/schema_migration_test.dart`
- Create: `test/data/sync/row_mappers_test.dart` — **verified absent as of
  this plan** (`test/data/` holds only `db/` and `repositories/`), so the
  `sync/` directory is new. Give the file the standard header imports:
  `package:chore_app/data/db/app_database.dart`,
  `package:chore_app/data/sync/row_mappers.dart`,
  `package:chore_app/domain/recurrence/plain_date.dart`,
  `package:flutter_test/flutter_test.dart`, and a `void main() { ... }`
  wrapping the four tests below.

**Interfaces:**
- Consumes: `schemaVersion == 13` and the `from < 13` guard from Task 1.
- Produces: `Chore.reminderMinutes` (`int?`); `ChoreRepository.createChore(...,
  int? reminderMinutes)` and `ChoreRepository.updateChore(..., Value<int?>
  reminderMinutes = const Value.absent())`; the `'reminder_minutes'` key in
  `choreRow`; `choreFromRow` tolerating an absent key.

- [ ] **Step 1: Add the column and regenerate**

In `lib/data/db/tables.dart`, inside `class Chores extends Table`, after
`pausedAt`:

```dart
  /// The per-chore individual reminder's fire time, as minutes since local
  /// midnight, or `NULL` for "no individual reminder" (spec
  /// `docs/specs/notifications-n2.md` D1, §2.1).
  ///
  /// **One nullable column, deliberately, rather than a boolean beside a
  /// time:** the opt-in and the time are one fact, so they cannot disagree.
  /// Turning the switch off writes `NULL`, so there is no state in which
  /// the app holds a reminder time it is not using.
  ///
  /// **This is household data and it SYNCS** (§8.2) -- `DESIGN.md` §1 lists
  /// "reminder overrides" as a field of the chore definition, and "the bins
  /// go out Tuesday evening" is a fact about the bins, not about a phone. It
  /// replicating does NOT mean both partners are reminded: the recipient
  /// predicate in `projectDigestCounts` decides whose device rings (§2.2).
  /// Added in schemaVersion 13; see `AppDatabase.migration`.
  IntColumn get reminderMinutes => integer().nullable()();
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 2: Write the failing migration + mapper tests**

In `test/data/db/schema_migration_test.dart`, add the collateral-drop helper:

```dart
/// Drops `chores.reminder_minutes` (schema v13, spec
/// `docs/specs/notifications-n2.md` §8.2) on [seed] -- the same
/// collateral-drop pattern as the helpers above. Needed by every test that
/// rewinds below 13, because `chores` has existed since schemaVersion 1 and
/// its backfill is therefore UNCONDITIONAL.
Future<void> _dropChoreReminderMinutesColumn(AppDatabase seed) async {
  await seed.customStatement('ALTER TABLE chores DROP COLUMN reminder_minutes');
}
```

Call it in the seed of **every** test that rewinds below 13 — including the
`1 -> 2` test (dropping the whole `settings` table does not cover a `chores`
column) and the new `12 -> 13` test from Task 1.

In the `7 -> 12` test (retitle to `7 -> 13`), after the existing chore
assertions:

```dart
      expect(chore.reminderMinutes, isNull);
      // `reminderMinutes` is nullable, so the assertion directly above
      // cannot fail on its own -- drift maps an ABSENT nullable column to
      // `null` on read (§8.4, and see `_columnNames`). This is the one that
      // can, and it is what proves the UNCONDITIONAL backfill ran: `chores`
      // has existed since schemaVersion 1, so this column can never be
      // covered by `createTable` inside the `settings` `else` branch.
      final choreColumns = await _columnNames(upgraded, 'chores');
      expect(choreColumns, contains('reminder_minutes'));
```

Add the same two lines to the new `12 -> 13` test and to the `1 -> 2` test
(the v1 path is the one where a wrongly-placed `addColumn` would be skipped
entirely).

Now the mapper tests. In `test/data/sync/row_mappers_test.dart`:

```dart
  test('choreRow carries reminder_minutes, and choreFromRow round-trips it '
      '(spec docs/specs/notifications-n2.md §8.2)', () {
    final chore = Chore(
      id: 'ch1',
      householdId: 'h1',
      title: 'Bins',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      reminderMinutes: 1080,
      createdAt: 't0',
      updatedAt: 't0',
      syncDirty: true,
    );
    final row = choreRow(chore);
    expect(row['reminder_minutes'], 1080);
    expect(choreFromRow({...row, 'reminder_minutes': 1080}).reminderMinutes,
        1080);
  });

  test('a NULL reminder_minutes round-trips as null', () {
    final chore = Chore(
      id: 'ch1',
      householdId: 'h1',
      title: 'Bins',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      createdAt: 't0',
      updatedAt: 't0',
      syncDirty: true,
    );
    final row = choreRow(chore);
    expect(row.containsKey('reminder_minutes'), isTrue);
    expect(row['reminder_minutes'], isNull);
    expect(choreFromRow(row).reminderMinutes, isNull);
  });

  test('choreFromRow tolerates the key being ABSENT entirely -- an '
      'un-migrated server (spec docs/specs/notifications-n2.md §8.2 point '
      '3, the mixed-version cost)', () {
    final row = <String, Object?>{
      'id': 'ch1',
      'household_id': 'h1',
      'title': 'Bins',
      'notes': null,
      'category_id': null,
      'recurrence': null,
      'start_date': '2026-01-05',
      'assignment_mode': 'anyone',
      'paused_at': null,
      'created_by': null,
      'created_at': 't0',
      'updated_at': 't0',
      'deleted_at': null,
      // NO 'reminder_minutes' key at all.
    };
    expect(choreFromRow(row).reminderMinutes, isNull);
  });

  test('choreFromRow reads a PostgREST JSON number, not just an int -- '
      'the same `as num?` tolerance color/sort_order already have', () {
    final row = <String, Object?>{
      'id': 'ch1',
      'household_id': 'h1',
      'title': 'Bins',
      'notes': null,
      'category_id': null,
      'recurrence': null,
      'start_date': '2026-01-05',
      'assignment_mode': 'anyone',
      'paused_at': null,
      'created_by': null,
      'created_at': 't0',
      'updated_at': 't0',
      'deleted_at': null,
      'reminder_minutes': 1080.0,
    };
    expect(choreFromRow(row).reminderMinutes, 1080);
  });
```

- [ ] **Step 3: Run both suites and watch them go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/db/schema_migration_test.dart test/data/sync/row_mappers_test.dart
```

**Expected RED, precisely:**
- migration: every rewinding test throws
  `SqliteException(1): no such column: reminder_minutes` at the seed's
  `_dropChoreReminderMinutesColumn`… **no** — the column DOES exist on the
  current schema after Step 1, so the drop succeeds; the failure is the
  `expect(choreColumns, contains('reminder_minutes'))` assertion reporting
  `Actual: <a set that does not contain 'reminder_minutes'>`, because
  `onUpgrade` never puts it back.
- mappers: `Expected: <1080> Actual: <null>` on
  `row['reminder_minutes']` (the key is not in `choreRow` yet), and a
  `type 'Null' is not a subtype` style failure is **not** expected — if you
  see one, the mapper was written before its test.

- [ ] **Step 4: Add the unconditional migration branch**

In `lib/data/db/app_database.dart`, in the flat region (after the
`if (from < 11)` index block, i.e. **outside** the `settings` `else`):

```dart
      if (from < 13) {
        // v12 -> v13 (spec `docs/specs/notifications-n2.md` §8.2): the
        // nullable `chores.reminderMinutes` column, defaulting to `NULL`
        // (no individual reminder) -- no data rewrite.
        //
        // Flat and UNCONDITIONAL, NOT inside the `settings` `else` branch
        // above: `chores` has existed since schemaVersion 1, so
        // `createTable` never covers it on any path and the `else` branch
        // would skip it entirely for a v1 install. Same shape as the
        // `syncDirty` (v8) and `members.deletedAt` (v9) backfills.
        await migrator.addColumn(chores, chores.reminderMinutes);
      }
```

- [ ] **Step 5: Add the mappers**

In `lib/data/sync/row_mappers.dart`, add to `choreRow` after `'paused_at'`:

```dart
  'reminder_minutes': chore.reminderMinutes,
```

and to `choreFromRow` after `pausedAt:`:

```dart
  // `as num?` rather than `as int?`, matching how `color`/`sort_order`
  // already tolerate PostgREST's JSON numbers. A MISSING key yields `null`
  // here too, which is the mixed-version tolerance §8.2 point 3 requires:
  // an un-migrated server simply does not send the column.
  reminderMinutes: (row['reminder_minutes'] as num?)?.toInt(),
```

- [ ] **Step 6: Thread it through the repository**

In `lib/data/repositories/chore_repository.dart`, add to `createChore`'s
parameter list (after `createdBy`):

```dart
    int? reminderMinutes,
```

to its `ChoresCompanion.insert` (after `createdBy:`):

```dart
              reminderMinutes: Value(reminderMinutes),
```

and to the `Chore(...)` it returns (after `createdBy:`):

```dart
        reminderMinutes: reminderMinutes,
```

In `updateChore`, add the parameter (after `assignmentMode`):

```dart
    Value<int?> reminderMinutes = const Value.absent(),
```

and to its `ChoresCompanion` (after `assignmentMode:`):

```dart
          reminderMinutes: reminderMinutes,
```

Extend `updateChore`'s doc comment's `Value`-wrapper paragraph to name
`reminderMinutes` alongside `notes`, `categoryId` and `recurrence` — it is
nullable in the schema, so a bare `null` would be ambiguous between
"unchanged" and "clear the reminder", and clearing it is exactly what turning
the switch off does (§2.1).

- [ ] **Step 7: Run both suites and watch them go GREEN**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/db/schema_migration_test.dart test/data/sync/row_mappers_test.dart
```

Expected: all pass.

- [ ] **Step 8: INVERT and confirm the tests catch it**

Move the `if (from < 13) { await migrator.addColumn(chores, ...); }` block
**inside** the `settings` `else` branch and re-run.

**Expected RED at the test step:** the `1 -> 2` test fails on
`expect(choreColumns, contains('reminder_minutes'))` — a v1 install takes the
`if (from < 2)` branch, so an `else`-placed backfill never runs and the column
is silently missing forever. Restore the flat placement; confirm green.

Then, separately, change `choreFromRow`'s `as num?` to `as int?` and re-run:
the JSON-number test fails with
`type 'double' is not a subtype of type 'int?' in type cast`. Restore.

- [ ] **Step 9: Add the Supabase migration**

Create `supabase/migrations/20260830120000_chore_reminder_minutes.sql`:

```sql
-- Per-chore individual reminders (spec docs/specs/notifications-n2.md
-- §8.2, D1): minutes since local midnight, NULL = no individual reminder.
--
-- No RLS change: the column sits inside a row whose access is already
-- decided by household_id (chores_select/insert/update in the initial
-- schema). No grant change either: `chores` carries a TABLE-level
-- `grant select, insert, update ... to authenticated`, so a new column is
-- covered automatically -- unlike `members`, whose column-scoped UPDATE
-- grant is what forces `ignoreDuplicates: true` on that table's upsert.
-- The sync engine's `upsertRows('chores', ...)` therefore needs no change.
alter table public.chores add column reminder_minutes integer;
```

- [ ] **Step 10: Add the pgTAP assertions**

Create `supabase/tests/003_chore_reminder_minutes_test.sql`:

```sql
-- pgTAP: chores.reminder_minutes (spec docs/specs/notifications-n2.md
-- §8.2). Run: `supabase db reset && supabase test db` -- `supabase test db`
-- does NOT apply migrations on its own.
begin;
create extension if not exists pgtap with schema extensions;

select plan(3);

select has_column('public', 'chores', 'reminder_minutes',
  'chores.reminder_minutes exists (schema v13, spec notifications-n2 §8.2)');

select col_type_is('public', 'chores', 'reminder_minutes', 'integer',
  'reminder_minutes is integer -- minutes since local midnight, not a time');

-- The column-privilege check that matters for PostgREST: `.upsert()`
-- verifies UPDATE on EVERY payload column at plan time. `chores` has a
-- table-level UPDATE grant, so this passes for the new column too and the
-- push needs no `ignoreDuplicates` workaround. This assertion is here so a
-- future narrowing of the grant to a column list fails HERE rather than as
-- a runtime PostgREST error nobody can read.
select ok(
  has_table_privilege('authenticated', 'public.chores', 'update'),
  'authenticated retains table-level UPDATE on chores, so an upsert '
  'carrying reminder_minutes plans successfully');

select * from finish();
rollback;
```

Note: this file never calls `test_login()`, so no `reset role;` is needed.

- [ ] **Step 11: Verify the SQL locally (optional but strongly advised)**

The maintainer runs this — **do not run `supabase`/`docker` from an agent
session; the global SDK lock is shared.** Ask the maintainer to run:

```bash
supabase db reset && supabase test db
```

Expected: `003_chore_reminder_minutes_test.sql .. ok`, 3 of 3 assertions.
If it cannot be run locally, `db.yml` will run it on the PR — and it WILL run,
because this diff touches `supabase/**`.

- [ ] **Step 12: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/data/db/tables.dart lib/data/db/app_database.dart \
  lib/data/db/app_database.g.dart lib/data/repositories/chore_repository.dart \
  lib/data/sync/row_mappers.dart test/data/db/schema_migration_test.dart \
  test/data/sync/row_mappers_test.dart \
  supabase/migrations/20260830120000_chore_reminder_minutes.sql \
  supabase/tests/003_chore_reminder_minutes_test.sql
git commit -m "Add chores.reminder_minutes, its sync mappers and its server column"
```

### Task 3: The `reminder_snoozes` table and its repository (§4.2, §8.3)

**Files:**
- Modify: `lib/data/db/tables.dart` (new `ReminderSnoozes` table at the end)
- Modify: `lib/data/db/app_database.dart` (`@DriftDatabase` tables list; the
  flat `from < 13` block from Task 2)
- Create: `lib/data/repositories/reminder_snooze_repository.dart`
- Modify: `lib/application/data_reset.dart` (explicit delete)
- Regenerate: `lib/data/db/app_database.g.dart`
- Modify: `test/data/db/schema_migration_test.dart`
- Create: `test/data/repositories/reminder_snooze_repository_test.dart`
- Modify: `test/application/chore_service_test.dart` (the pause-cascade test)
- Modify: `test/application/data_reset_test.dart`

**Interfaces:**
- Consumes: `schemaVersion == 13` (Task 1), the flat `from < 13` block
  (Task 2).
- Produces: `ReminderSnooze` data class (`occurrenceId`, `snoozedUntil`,
  `createdAt`, `updatedAt`); `ReminderSnoozeRepository` with
  `Future<void> upsertSnooze({required String occurrenceId, required DateTime
  snoozedUntilUtc})`, `Future<Map<String, DateTime>> activeSnoozes()`,
  `Future<void> collectGarbage({required Set<String> pendingOccurrenceIds,
  required DateTime nowUtc})`. `activeSnoozes()` is what Task 9's
  `snoozedUntilByOccurrenceId` argument is fed from.

- [ ] **Step 1: Add the table and regenerate**

At the end of `lib/data/db/tables.dart`:

```dart
/// A device-local deferral of ONE occurrence's individual reminder (spec
/// `docs/specs/notifications-n2.md` §4.2, D5).
///
/// **Device-scoped and NOT synced**, and that is the whole point: snoozing
/// is a personal act about a personal notification -- the same scope
/// `DESIGN.md` §3 gives every other notification setting. One partner
/// pressing Snooze must not silence the other's reminder. It also keeps the
/// entire N2 surface off the sync path except `chores.reminderMinutes`,
/// which means no Supabase migration, no mappers and no LWW semantics to
/// argue about for this table.
///
/// **Snooze moves nothing.** A row here defers a NOTIFICATION and leaves
/// `chore_occurrences.due_date`, `status`, `assigned_member_id`, rotation
/// position and stats exactly as they were (D5). `skipOccurrence` is the
/// wrong primitive and must never appear in this feature: it closes the
/// occurrence as `skipped`, advances the recurrence and advances rotation.
///
/// Rows are garbage-collected on every plan pass (see
/// `ReminderSnoozeRepository.collectGarbage`), so the table never grows.
///
/// Deliberately does NOT mix in [SyncDirtyColumn] -- there is nothing to
/// push. Added in schemaVersion 13; see `AppDatabase.migration`.
@DataClassName('ReminderSnooze')
class ReminderSnoozes extends Table {
  /// The deferred occurrence. Primary key: one live snooze per occurrence.
  ///
  /// **The cascade delete is load-bearing, not decoration.**
  /// `ChoreService.pauseChore` HARD-DELETES the pending occurrence, and
  /// foreign keys are ON (`AppDatabase.migration`'s `beforeOpen` sets
  /// `PRAGMA foreign_keys = ON`), so without `onDelete: KeyAction.cascade`
  /// a snoozed chore could not be paused at all.
  TextColumn get occurrenceId => text().references(
    ChoreOccurrences,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// The instant the reminder should be re-armed for, as an ISO-8601 UTC
  /// string -- the convention every other timestamp column in this file
  /// uses.
  ///
  /// Stores INTENT, not deliverability: the quiet-hours shift is applied at
  /// plan time (§2.3 step 4), never at write time, so exactly one code path
  /// decides when a reminder may fire.
  TextColumn get snoozedUntil => text()();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {occurrenceId};
}
```

In `lib/data/db/app_database.dart`, add `ReminderSnoozes,` to the
`@DriftDatabase(tables: [...])` list, after `Settings,`. Then:

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 2: Write the failing tests**

In `test/data/db/schema_migration_test.dart`, add the collateral-drop helper:

```dart
/// Drops the `reminder_snoozes` table (schema v13, spec
/// `docs/specs/notifications-n2.md` §8.3) on [seed] -- the same
/// collateral-drop pattern as `_dropStatusClosedOnIndex`, one rung back up
/// the schema-object hierarchy. [seed] always opens at the *current* (v13)
/// schema first, so `onCreate` has already created this table; rewinding
/// `user_version` alone does not remove it, and `onUpgrade`'s plain
/// `createTable` would then throw "table reminder_snoozes already exists".
Future<void> _dropReminderSnoozesTable(AppDatabase seed) async {
  await seed.customStatement('DROP TABLE reminder_snoozes');
}
```

Call it in the seed of **every** test that rewinds below 13 (all of them
except the fresh-database test).

Add the table + FK assertions to the new `12 -> 13` test from Task 1:

```dart
      // The new table exists with exactly its four columns (§8.3).
      final snoozeColumns = await _columnNames(upgraded, 'reminder_snoozes');
      expect(snoozeColumns, {
        'occurrence_id',
        'snoozed_until',
        'created_at',
        'updated_at',
      });

      // ... and its FK CASCADES. A missing cascade is invisible until
      // someone pauses a snoozed chore, which is why §8.4 requires this
      // assertion specifically. `PRAGMA foreign_key_list` is the only place
      // the delete action is observable without provoking it.
      final fks = await upgraded
          .customSelect("PRAGMA foreign_key_list('reminder_snoozes')")
          .get();
      expect(fks, hasLength(1));
      expect(fks.single.read<String>('table'), 'chore_occurrences');
      expect(fks.single.read<String>('from'), 'occurrence_id');
      expect(fks.single.read<String>('to'), 'id');
      expect(fks.single.read<String>('on_delete'), 'CASCADE');
```

Add the same block to the `1 -> 2` test (the v1 path is where a wrongly-placed
`createTable` would be skipped).

Create `test/data/repositories/reminder_snooze_repository_test.dart`. Follow
the setup shape of `test/data/repositories/settings_repository_test.dart`
(open `AppDatabase(NativeDatabase.memory())`, `addTearDown(db.close)`), and
seed a household + chore + pending occurrence the way
`test/data/repositories/chore_repository_test.dart` already does — read that
file for the exact companion calls rather than inventing them. Tests:

```dart
  test('upsertSnooze writes a row, and a second call for the same '
      'occurrence REPLACES it rather than throwing (idempotent double '
      'tap, spec docs/specs/notifications-n2.md §13.2)', () async {
    await repo.upsertSnooze(
      occurrenceId: 'o1',
      snoozedUntilUtc: DateTime.utc(2026, 8, 31, 18),
    );
    await repo.upsertSnooze(
      occurrenceId: 'o1',
      snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
    );
    final rows = await db.select(db.reminderSnoozes).get();
    expect(rows, hasLength(1));
    expect(rows.single.snoozedUntil, '2026-09-01T18:00:00.000Z');
  });

  test('activeSnoozes returns a map keyed by occurrence id, with UTC '
      'DateTimes', () async {
    await repo.upsertSnooze(
      occurrenceId: 'o1',
      snoozedUntilUtc: DateTime.utc(2026, 8, 31, 18),
    );
    expect(await repo.activeSnoozes(), {
      'o1': DateTime.utc(2026, 8, 31, 18),
    });
  });

  test('collectGarbage deletes rows whose occurrence is no longer pending '
      'AND rows whose snoozed_until has passed, and keeps the rest '
      '(spec §4.2 -- the table never grows)', () async {
    await repo.upsertSnooze(
      occurrenceId: 'o1', // pending, future -> kept
      snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
    );
    await repo.upsertSnooze(
      occurrenceId: 'o2', // pending, PAST -> deleted
      snoozedUntilUtc: DateTime.utc(2026, 8, 29, 18),
    );
    await repo.upsertSnooze(
      occurrenceId: 'o3', // future, but NOT pending -> deleted
      snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
    );
    await repo.collectGarbage(
      pendingOccurrenceIds: {'o1', 'o2'},
      nowUtc: DateTime.utc(2026, 8, 30, 12),
    );
    final rows = await db.select(db.reminderSnoozes).get();
    expect(rows.map((r) => r.occurrenceId), ['o1']);
  });
```

In `test/application/chore_service_test.dart`, add the cascade test required
by §13.2 (place it beside the existing `pauseChore` tests, reusing that file's
existing fixture helpers rather than writing new ones):

```dart
  test('pausing a chore with a SNOOZED pending occurrence deletes the '
      'snooze row rather than throwing -- the cascade FK is load-bearing '
      'because pauseChore hard-deletes the occurrence while foreign keys '
      'are ON (spec docs/specs/notifications-n2.md §4.2)', () async {
    // (create chore + pending occurrence via this file's existing helper,
    // then:)
    await database
        .into(database.reminderSnoozes)
        .insert(
          ReminderSnoozesCompanion.insert(
            occurrenceId: occurrence.id,
            snoozedUntil: '2026-09-01T18:00:00.000Z',
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );

    await service.pauseChore(chore.id);

    expect(await database.select(database.reminderSnoozes).get(), isEmpty);
  });
```

- [ ] **Step 3: Run and watch them go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/db/schema_migration_test.dart \
  test/data/repositories/reminder_snooze_repository_test.dart \
  test/application/chore_service_test.dart
```

**Expected RED, precisely:**
- migration: `12 -> 13` and `1 -> 2` fail on
  `expect(snoozeColumns, {...})` with
  `SqliteException(1): no such table: reminder_snoozes` raised by
  `PRAGMA table_info` returning nothing — the seed dropped the table and
  `onUpgrade` never re-creates it.
- repository: the test file does not compile —
  `Error: Couldn't find constructor 'ReminderSnoozeRepository'`. This is the
  signature red; the behavioural red arrives at Step 6's inversion.
- `chore_service_test`: **PASSES already**, because `onCreate` builds the
  table with the cascade on a fresh in-memory database. That is expected and
  is exactly why Step 6 inverts the cascade rather than trusting this green.

- [ ] **Step 4: Add the migration line**

In `lib/data/db/app_database.dart`, inside the flat `if (from < 13)` block
added in Task 2, after the `chores.reminderMinutes` line:

```dart
        // v12 -> v13 (spec `docs/specs/notifications-n2.md` §8.3): the
        // device-scoped, unsynced `reminder_snoozes` table. Flat and
        // unconditional for the same reason the column above is: this table
        // is introduced HERE, so no install at any shipped version 1..12
        // can already carry it, and a plain `createTable` (drift offers no
        // `IF NOT EXISTS` form) throwing would mean the upgrade path itself
        // is wrong -- which is worth finding out.
        await migrator.createTable(reminderSnoozes);
```

- [ ] **Step 5: Write the repository**

Create `lib/data/repositories/reminder_snooze_repository.dart`:

```dart
/// Manages `reminder_snoozes` -- the device-local, unsynced deferrals of
/// individual chore reminders (spec `docs/specs/notifications-n2.md` §4.2).
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// Repository for the device-scoped reminder-snooze rows.
///
/// Unlike the synced repositories in this layer there is no `syncDirty`
/// bookkeeping and no household scoping: snoozing is a personal act about a
/// personal notification (§4.2), so nothing here ever leaves the device.
class ReminderSnoozeRepository {
  /// Creates a repository backed by [db].
  ///
  /// [nowUtc] is injectable so tests can supply a controllable clock; it
  /// defaults to the real UTC clock.
  ReminderSnoozeRepository(this.db, {this.nowUtc = _defaultNowUtc});

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Records that [occurrenceId]'s reminder is deferred until
  /// [snoozedUntilUtc], replacing any existing row for that occurrence.
  ///
  /// Idempotent by construction (`InsertMode.insertOrReplace` on the
  /// occurrence-id primary key), which is what makes a double tap on the
  /// notification's Snooze action a no-op rather than a constraint error
  /// (§13.2). [snoozedUntilUtc] is stored as an ISO-8601 UTC string and
  /// carries INTENT only -- the quiet-hours shift is applied at plan time
  /// (§2.3 step 4), never here.
  Future<void> upsertSnooze({
    required String occurrenceId,
    required DateTime snoozedUntilUtc,
  }) async {
    final now = _isoNow();
    await db
        .into(db.reminderSnoozes)
        .insert(
          ReminderSnoozesCompanion.insert(
            occurrenceId: occurrenceId,
            snoozedUntil: snoozedUntilUtc.toUtc().toIso8601String(),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Every stored snooze, as `occurrenceId -> snoozed-until instant` (UTC).
  ///
  /// Returned as a plain map because its one consumer is the pure planning
  /// pass (`buildNotificationPlans`, spec §9.1), which may not touch drift.
  /// Deliberately returns ALL rows rather than filtering by time: §2.3 step
  /// 5 is the single place a past moment is dropped, and a second copy of
  /// that rule here is exactly the drift §0.1 exists to prevent.
  Future<Map<String, DateTime>> activeSnoozes() async {
    final rows = await db.select(db.reminderSnoozes).get();
    return {
      for (final row in rows)
        row.occurrenceId: DateTime.parse(row.snoozedUntil).toUtc(),
    };
  }

  /// Deletes every row whose occurrence is not in [pendingOccurrenceIds] or
  /// whose `snoozed_until` is at or before [nowUtc] (spec §4.2).
  ///
  /// Called on every plan pass. Cheap, and it means the table never grows.
  Future<void> collectGarbage({
    required Set<String> pendingOccurrenceIds,
    required DateTime nowUtc,
  }) async {
    final cutoff = nowUtc.toUtc().toIso8601String();
    await (db.delete(db.reminderSnoozes)..where(
      (tbl) =>
          tbl.occurrenceId.isNotIn(pendingOccurrenceIds) |
          tbl.snoozedUntil.isSmallerOrEqualValue(cutoff),
    )).go();
  }

  String _isoNow() => nowUtc().toUtc().toIso8601String();
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();
```

Note on the `collectGarbage` predicate: `snoozed_until` is a fixed-width
ISO-8601 UTC string with milliseconds (every writer goes through
`upsertSnooze`), so a lexicographic `<=` is a chronological `<=` — the same
property `closedOn`'s range scan already relies on (`ChoreOccurrences`' doc
comment). Do not "fix" it into date arithmetic.

- [ ] **Step 6: Run, go GREEN, then INVERT**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/db/schema_migration_test.dart \
  test/data/repositories/reminder_snooze_repository_test.dart \
  test/application/chore_service_test.dart
```

Expected: all pass.

Now invert, twice:

1. Remove `onDelete: KeyAction.cascade` from the `occurrenceId` column, run
   `dart run build_runner build --delete-conflicting-outputs`, re-run the
   suites. **Expected RED at the test step:** the `chore_service_test` cascade
   test fails with
   `SqliteException(787): FOREIGN KEY constraint failed` out of
   `pauseChore`, and the migration test fails
   `expect(fks.single.read<String>('on_delete'), 'CASCADE')` with
   `Actual: 'NO ACTION'`. Restore and regenerate.
2. Change `collectGarbage`'s `|` to `&`. **Expected RED:** the garbage
   test fails with `Expected: ['o1'] Actual: ['o1', 'o2', 'o3']` — an `AND`
   only deletes rows that are both stale and unpending, which is neither
   half of §4.2's rule. Restore.

- [ ] **Step 7: Wire the wipe, and record the export decision**

In `lib/application/data_reset.dart`, add as the FIRST delete inside the
transaction (before `choreOccurrences`):

```dart
    // Before `chore_occurrences`, whose cascade would take these rows out
    // anyway -- explicit because "the wipe deletes every table" is the
    // guarantee this function's own test asserts, and a reader should not
    // have to reason about FK cascades to see that it holds.
    await database.delete(database.reminderSnoozes).go();
```

and extend the function's doc comment's FK-order sentence to name
`reminder_snoozes` first.

In `lib/application/data_export.dart`, add a comment above
`exportedTableNames`. **Do not add the table** — the product owner closed
OQ-P1 on 2026-08-30 as "not exported":

```dart
/// `reminder_snoozes` (schema v13) is deliberately NOT here, decided
/// 2026-08-30: a snooze is device-scoped, transient NOTIFICATION
/// bookkeeping -- "I pushed this notification to tomorrow" -- not household
/// data. This document exists so a user keeps the things they created, and
/// restoring a snooze would resurrect a deferral against an occurrence that
/// may no longer exist, or that another device completed in the meantime,
/// which is worse than losing it. Its absence costs the user nothing they
/// would notice. See "Closed product decisions" in
/// `docs/plans/2026-08-30-n2-foundation.md` before adding it.
```

Then fix the one stale claim the copy audit found. In `lib/l10n/app_en.arb`,
`settingsExportEntry`'s `@description` currently reads "shares a full JSON
backup of **every table**". That is developer-facing (users see only the label
"Export data"), but it is the sentence a future implementer would read as
licence to add a table, so scope it:

```json
  "@settingsExportEntry": {
    "description": "Settings screen list entry (spec docs/specs/polish-round-1.md B1), between the digest section and About. Tapping it shares a JSON backup of the household's data -- the tables named in exportedTableNames (lib/application/data_export.dart), which is deliberately not every table in the schema: device-scoped, transient tables such as reminder_snoozes are excluded. The user-facing copy is the two-word label alone and claims no completeness."
  },
```

Then `flutter gen-l10n` (an `@description` change alone does not alter the
generated getters, but regenerate so the doc comment in
`app_localizations.dart` follows).

In `test/application/data_reset_test.dart`, extend the existing
"every table is empty afterwards" assertions with:

```dart
    expect(await database.select(database.reminderSnoozes).get(), isEmpty);
```

seeding a snooze row alongside the other fixtures so the assertion is not
vacuous.

- [ ] **Step 8: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data test/application
git add -A
git commit -m "Add the device-scoped reminder_snoozes table and its repository"
```

### Task 4: `SettingsRepository` setters for the five new columns

**Files:**
- Modify: `lib/data/repositories/settings_repository.dart`
- Modify: `test/data/repositories/settings_repository_test.dart`

**Interfaces:**
- Consumes: `DeviceSettings.quietHoursEnabled` etc. (Task 1).
- Produces: `SettingsRepository.setQuietHoursEnabled({required bool enabled})`,
  `.setQuietHours({required int startMinutes, required int endMinutes})`,
  `.setEveningReminderEnabled({required bool enabled})`,
  `.setEveningReminderTime(int minutesSinceMidnight)`. Slices 5 and 6 consume
  these; nothing in slices 1–3 calls them.

- [ ] **Step 1: Write the failing tests**

Append to `test/data/repositories/settings_repository_test.dart`, following
the file's existing `setDigestTime` test shape:

```dart
  test('ensureSettings inserts the v13 defaults: quiet hours off '
      '22:00-07:00, evening re-reminder off at 20:00 (spec '
      'docs/specs/notifications-n2.md §8.1)', () async {
    final settings = await repo.ensureSettings();
    expect(settings.quietHoursEnabled, isFalse);
    expect(settings.quietStartMinutes, 1320);
    expect(settings.quietEndMinutes, 420);
    expect(settings.eveningReminderEnabled, isFalse);
    expect(settings.eveningReminderMinutes, 1200);
  });

  test('setQuietHours writes both ends together', () async {
    await repo.setQuietHours(startMinutes: 1290, endMinutes: 400);
    final row = await repo.ensureSettings();
    expect(row.quietStartMinutes, 1290);
    expect(row.quietEndMinutes, 400);
  });

  test('setQuietHours rejects a minute-of-day outside 0..1439, on either '
      'end', () async {
    expect(
      () => repo.setQuietHours(startMinutes: -1, endMinutes: 400),
      throwsArgumentError,
    );
    expect(
      () => repo.setQuietHours(startMinutes: 1290, endMinutes: 1440),
      throwsArgumentError,
    );
  });

  test('setQuietHours ACCEPTS start == end -- that is "off", not an '
      'invalid range (spec §6), and rejecting it here would make the '
      'setting unreachable through its own picker', () async {
    await repo.setQuietHours(startMinutes: 600, endMinutes: 600);
    final row = await repo.ensureSettings();
    expect(row.quietStartMinutes, 600);
    expect(row.quietEndMinutes, 600);
  });

  test('setQuietHoursEnabled and setEveningReminderEnabled toggle '
      'independently', () async {
    await repo.setQuietHoursEnabled(enabled: true);
    expect((await repo.ensureSettings()).quietHoursEnabled, isTrue);
    expect((await repo.ensureSettings()).eveningReminderEnabled, isFalse);
    await repo.setEveningReminderEnabled(enabled: true);
    expect((await repo.ensureSettings()).eveningReminderEnabled, isTrue);
    expect((await repo.ensureSettings()).quietHoursEnabled, isTrue);
  });

  test('setEveningReminderTime writes minutes since midnight and '
      'validates the range', () async {
    await repo.setEveningReminderTime(1260);
    expect((await repo.ensureSettings()).eveningReminderMinutes, 1260);
    expect(() => repo.setEveningReminderTime(1440), throwsArgumentError);
  });
```

- [ ] **Step 2: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/repositories/settings_repository_test.dart
```

**Expected RED:** the file does not compile —
`Error: The method 'setQuietHours' isn't defined for the class
'SettingsRepository'`. The first test (`ensureSettings` defaults) is the one
that CAN run once the others compile; it is the behavioural half.

- [ ] **Step 3: Implement the setters**

In `lib/data/repositories/settings_repository.dart`, after `setDigestTime`:

```dart
  /// Enables or disables quiet hours (spec
  /// `docs/specs/notifications-n2.md` §6).
  Future<void> setQuietHoursEnabled({required bool enabled}) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        quietHoursEnabled: Value(enabled),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the quiet-hours window, both ends at once, as minutes since local
  /// midnight.
  ///
  /// Written together deliberately: the window is one fact, and a UI that
  /// wrote the ends separately would briefly persist a half-updated window
  /// that a concurrent recompute could read.
  ///
  /// `startMinutes == endMinutes` is ACCEPTED and means the window is off
  /// (spec §6) -- it is `quietHoursEnabled` that turns the feature off, and
  /// rejecting an equal pair here would make the value unreachable from a
  /// pair of time pickers. Throws [ArgumentError] if either value is
  /// outside `0..1439`.
  Future<void> setQuietHours({
    required int startMinutes,
    required int endMinutes,
  }) async {
    _validateMinuteOfDay(startMinutes, 'startMinutes');
    _validateMinuteOfDay(endMinutes, 'endMinutes');
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        quietStartMinutes: Value(startMinutes),
        quietEndMinutes: Value(endMinutes),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Enables or disables the evening re-reminder (spec
  /// `docs/specs/notifications-n2.md` §5). Ships disabled (D12).
  Future<void> setEveningReminderEnabled({required bool enabled}) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        eveningReminderEnabled: Value(enabled),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the evening re-reminder's fire time, as minutes since local
  /// midnight. Throws [ArgumentError] if outside `0..1439`.
  Future<void> setEveningReminderTime(int minutesSinceMidnight) async {
    _validateMinuteOfDay(minutesSinceMidnight, 'minutesSinceMidnight');
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        eveningReminderMinutes: Value(minutesSinceMidnight),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  void _validateMinuteOfDay(int value, String name) {
    if (value < 0 || value > 1439) {
      throw ArgumentError.value(
        value,
        name,
        'Must be in 0..1439 (minutes since local midnight)',
      );
    }
  }
```

Also update `ensureSettings`'s doc comment (it currently says "inserting it
with schema defaults (`digestEnabled: true`, `digestMinutes: 480`)") to name
the v13 defaults too, and add the five fields to the `DeviceSettings(...)`
literal it returns inside the transaction — that literal is hand-built, so
drift will NOT fill them in and the returned object would otherwise disagree
with the row on disk:

```dart
        quietHoursEnabled: false,
        quietStartMinutes: 1320,
        quietEndMinutes: 420,
        eveningReminderEnabled: false,
        eveningReminderMinutes: 1200,
```

- [ ] **Step 4: Run, go GREEN, then INVERT**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/data/repositories/settings_repository_test.dart
```

Expected: pass.

Invert: make `setQuietHours` write only `quietStartMinutes` (drop the
`quietEndMinutes` line). **Expected RED at the test step:**
`setQuietHours writes both ends together` fails with
`Expected: <400> Actual: <420>`. Restore.

Second inversion, aimed at the hand-built `DeviceSettings` literal: remove the
five fields you just added there. **Expected RED:** the code does not compile
(they are required constructor parameters) — which is itself the guard, and is
why this literal cannot silently drift. Restore.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/data/repositories/settings_repository.dart \
  test/data/repositories/settings_repository_test.dart
git commit -m "Add settings repository setters for quiet hours and the evening re-reminder"
```

**Slice 1 is complete.** Schema v13 is in, nothing user-visible changed, and
no code reads any of it yet.

---

# Slice 2 — The planning core

**This is where most of the risk lives** (§14). Five tasks, all pure
functions; nothing is scheduled and nothing reaches a user.

### Task 5: `reminder_planner.dart` — the constants and `applyQuietHours` (§3.1, §6)

**Files:**
- Create: `lib/domain/reminder_planner.dart`
- Create: `test/domain/reminder_planner_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `n2NotificationIdBudget`, `eveningHorizonSlots`,
  `reminderCeiling`, `reminderNotificationIdBase`, `eveningNotificationIdBase`,
  `reminderArmWindowDays`, `defaultReminderMinutes`;
  `DateTime applyQuietHours({required DateTime candidate, required bool
  enabled, required int startMinutes, required int endMinutes})`.

- [ ] **Step 1: Write the failing tests**

Create `test/domain/reminder_planner_test.dart`:

```dart
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the id-budget constants (spec docs/specs/notifications-n2.md §3.1)',
      () {
    test('reminderCeiling is DERIVED from the budget and the evening '
        'horizon, never written as 33 -- the split must move as one number '
        'when it moves at all', () {
      expect(reminderCeiling, n2NotificationIdBudget - eveningHorizonSlots);
      // The shipped values, pinned so a silent edit is visible in a diff.
      expect(n2NotificationIdBudget, 40);
      expect(eveningHorizonSlots, 7);
      expect(reminderCeiling, 33);
    });

    test('the bases are far apart, so an off-by-one inside one range '
        'cannot land inside another', () {
      expect(reminderNotificationIdBase, 2001);
      expect(eveningNotificationIdBase, 3001);
    });

    test('the arm window and the default reminder time', () {
      expect(reminderArmWindowDays, 14);
      expect(defaultReminderMinutes, 1080); // 18:00
    });
  });

  group('applyQuietHours (spec docs/specs/notifications-n2.md §6)', () {
    // 22:00 -> 07:00, the shipped default: a WRAPPING window.
    DateTime shift(DateTime candidate, {bool enabled = true,
        int start = 1320, int end = 420}) =>
        applyQuietHours(
          candidate: candidate,
          enabled: enabled,
          startMinutes: start,
          endMinutes: end,
        );

    test('disabled: returns the candidate untouched, even inside the '
        'window', () {
      final candidate = DateTime(2026, 8, 30, 23, 30);
      expect(shift(candidate, enabled: false), candidate);
    });

    test('outside a wrapping window: untouched', () {
      final candidate = DateTime(2026, 8, 30, 18);
      expect(shift(candidate), candidate);
    });

    test('inside a wrapping window, LATE side: deferred to the window end '
        'on the FOLLOWING calendar day', () {
      expect(shift(DateTime(2026, 8, 30, 23, 30)),
          DateTime(2026, 8, 31, 7));
    });

    test('inside a wrapping window, EARLY side: deferred to the window end '
        'on the SAME calendar day', () {
      expect(shift(DateTime(2026, 8, 30, 3, 15)), DateTime(2026, 8, 30, 7));
    });

    test('inside a NON-wrapping window (a daytime quiet window): deferred '
        'to its end the same day', () {
      expect(
        shift(DateTime(2026, 8, 30, 11), start: 600, end: 840),
        DateTime(2026, 8, 30, 14),
      );
    });

    test('outside a NON-wrapping window: untouched', () {
      final candidate = DateTime(2026, 8, 30, 15);
      expect(shift(candidate, start: 600, end: 840), candidate);
    });

    test('a candidate exactly AT start is INSIDE (deferred)', () {
      expect(shift(DateTime(2026, 8, 30, 22)), DateTime(2026, 8, 31, 7));
    });

    test('a candidate exactly AT end is OUTSIDE (untouched)', () {
      final candidate = DateTime(2026, 8, 30, 7);
      expect(shift(candidate), candidate);
    });

    test('start == end is OFF, not a 24-hour window -- "never notify" is '
        'what the toggle is for', () {
      final candidate = DateTime(2026, 8, 30, 23, 30);
      expect(shift(candidate, start: 600, end: 600), candidate);
    });

    test('the deferral target is a WALL-CLOCK time and must not shift an '
        'hour across the spring-forward transition (Europe/Berlin, '
        '2026-03-29 02:00 -> 03:00)', () {
      // Candidate at 23:30 on the night BEFORE the clocks go forward. The
      // answer must be 07:00 local on the 29th, not 06:00 or 08:00.
      final result = shift(DateTime(2026, 3, 28, 23, 30));
      expect(result.year, 2026);
      expect(result.month, 3);
      expect(result.day, 29);
      expect(result.hour, 7);
      expect(result.minute, 0);
    });

    test('...and not across the autumn fall-back transition either '
        '(2026-10-25 03:00 -> 02:00)', () {
      final result = shift(DateTime(2026, 10, 24, 23, 30));
      expect(result.year, 2026);
      expect(result.month, 10);
      expect(result.day, 25);
      expect(result.hour, 7);
      expect(result.minute, 0);
    });

    test('the answer is always at or after the candidate -- the property '
        'the arming rule relies on (§2.3 step 5 drops a PAST moment, so a '
        'shift that went backwards would silently delete reminders)', () {
      for (var minute = 0; minute < 1440; minute += 7) {
        final candidate =
            DateTime(2026, 8, 30, minute ~/ 60, minute % 60);
        expect(
          shift(candidate).isBefore(candidate),
          isFalse,
          reason: 'shift went backwards for $candidate',
        );
      }
    });

    test('rejects a minute-of-day outside 0..1439 on either end', () {
      expect(
        () => shift(DateTime(2026, 8, 30, 12), start: -1),
        throwsArgumentError,
      );
      expect(
        () => shift(DateTime(2026, 8, 30, 12), end: 1440),
        throwsArgumentError,
      );
    });
  });
}
```

**On the two DST tests:** these run against the host's local timezone, which
in CI is UTC — where nothing shifts and the test is weaker but still correct.
They are written as component assertions (`result.hour == 7`) rather than
`DateTime` equality precisely so they are meaningful in both timezones: the
whole point is "the wall-clock hour is 7 whatever the offset did". Do **not**
introduce a `timezone` package dependency into a `lib/domain/` test to
strengthen them — §13.3 already records that only a real device settles the
overnight DST deferral.

- [ ] **Step 2: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/reminder_planner_test.dart
```

**Expected RED:** `Error: Error when reading
'lib/domain/reminder_planner.dart': No such file or directory`. This is the
file-does-not-exist red; the behavioural reds arrive at Step 4's inversions.

- [ ] **Step 3: Write the module**

Create `lib/domain/reminder_planner.dart`:

```dart
/// Pure scheduling logic for per-chore reminders, the evening re-reminder
/// and quiet hours (spec `docs/specs/notifications-n2.md` §2, §5, §6).
///
/// Same purity standard as `digest_planner.dart` and `digest_projection.dart`
/// -- no clock, no I/O, no Flutter, no drift. It imports those two rather
/// than `dart:core` alone, deliberately: §2.3 step 1 requires the reminder's
/// roll-forward to be **the same** `latestScheduledOnOrBefore` path the
/// digest projection already uses, and §5's horizon is the same
/// "today if still ahead of now, else tomorrow" rule `nextDigestSlot`
/// implements. A second copy of either would be exactly the drift §0.1's
/// partition exists to prevent.
library;

/// The number of iOS pending-notification ids `docs/specs/notifications.md`
/// reserves for N2 (spec `docs/specs/notifications-n2.md` §3).
///
/// iOS caps an app at 64 pending notifications; the digest owns 24 of them
/// and this is the rest. **The total is now exactly 64 and there is no
/// slack left** -- anything new must take ids from one of the three ranges
/// by amending §3.1's table.
const int n2NotificationIdBudget = 40;

/// How many consecutive daily evening re-reminder slots are armed at once
/// (spec §3.1).
///
/// Seven, not fourteen: the evening re-reminder is the "you are around
/// today and busy" instrument, and someone who has not opened the app in a
/// week is not busy-today, they are away -- which is what the digest's own
/// 83-day horizon is for.
const int eveningHorizonSlots = 7;

/// The most individual reminders that can be armed at once (spec §3.1).
///
/// **Derived, never written as `33`**, for the same reason
/// `digestNotificationIds` is derived from `digestHorizonSlots`: the split
/// between reminders and the evening horizon must move as one number when
/// it moves at all.
const int reminderCeiling = n2NotificationIdBudget - eveningHorizonSlots;

/// The lowest notification id per-chore reminders own; reminder `i` in the
/// sorted armed list uses `reminderNotificationIdBase + i` (spec §2.3).
///
/// **Ids are position-relative, exactly like the digest's**, so an id names
/// neither a chore nor a date and the payload is the only channel that can
/// address anything.
///
/// Deliberately far from [eveningNotificationIdBase] and from
/// `digestNotificationIdBase` (1001 / 2001 / 3001 rather than adjacent), so
/// an off-by-one inside one range cannot silently land in another's.
const int reminderNotificationIdBase = 2001;

/// The lowest notification id the evening re-reminder horizon owns; slot
/// `k` uses `eveningNotificationIdBase + k` (spec §3.1). See
/// [reminderNotificationIdBase] for why the bases are spaced out.
const int eveningNotificationIdBase = 3001;

/// How far ahead an individual reminder may be armed, in days (spec D3).
///
/// The digest is the long-range instrument (83 days); individual reminders
/// are the same-fortnight instrument. Arming several occurrences per chore
/// would multiply the id cost for coverage the digest already provides.
const int reminderArmWindowDays = 14;

/// The time a freshly-enabled chore reminder is pre-filled with, as minutes
/// since local midnight (18:00) -- spec §2.1.
///
/// A **constant, not a settings column**: a default is not state, and a
/// stored one would have to pick a device scope for a value that is only
/// ever a starting point in a picker. 18:00 is the hour "bins out on
/// Tuesday evening" names, and far enough from the 08:00 digest default
/// that the two never read as one event.
const int defaultReminderMinutes = 1080;

/// [candidate] itself when quiet hours are off or [candidate] falls outside
/// the window; otherwise the first instant at or after [candidate] whose
/// minute-of-day equals [endMinutes] (spec `docs/specs/notifications-n2.md`
/// §6).
///
/// **Deferred, never dropped**, for the digest and for individual reminders
/// (D7): dropping discards something the user asked for, while deferring
/// converts a 23:30 ping nobody can act on into an 07:00 one they can. The
/// evening re-reminder is the one exception and it is handled by its own
/// caller, which drops a slot this function would have moved -- an
/// "evening" re-reminder delivered at 07:00 has a false premise.
///
/// The window WRAPS midnight in the normal case and is evaluated as a
/// wrapping interval, never as a numeric range. `startMinutes ==
/// endMinutes` is treated as OFF, not as a 24-hour window: the latter would
/// mean "never notify", which is what [enabled] is for. A candidate exactly
/// at [startMinutes] is INSIDE; one exactly at [endMinutes] is OUTSIDE.
///
/// The result is built from calendar components rather than
/// `add(Duration(hours:))` for the DST reason `nextDigestSlot` documents:
/// the deferral target is a WALL-CLOCK time, and adding a fixed duration
/// across a daylight-saving transition would land an hour out. It is
/// therefore always at or after [candidate] -- a property §2.3 step 5
/// relies on, since a shift that went backwards would silently delete
/// reminders by making them look past.
///
/// [startMinutes] and [endMinutes] must be in `0..1439`; throws
/// [ArgumentError] otherwise.
DateTime applyQuietHours({
  required DateTime candidate,
  required bool enabled,
  required int startMinutes,
  required int endMinutes,
}) {
  _validateMinuteOfDay(startMinutes, 'startMinutes');
  _validateMinuteOfDay(endMinutes, 'endMinutes');
  if (!enabled || startMinutes == endMinutes) {
    return candidate;
  }
  final minuteOfDay = candidate.hour * 60 + candidate.minute;
  final inside = startMinutes < endMinutes
      // A non-wrapping window: [start, end).
      ? minuteOfDay >= startMinutes && minuteOfDay < endMinutes
      // A wrapping window: [start, midnight) union [midnight, end).
      : minuteOfDay >= startMinutes || minuteOfDay < endMinutes;
  if (!inside) {
    return candidate;
  }
  final hour = endMinutes ~/ 60;
  final minute = endMinutes % 60;
  // Same day when the end is still ahead of us in the day (the early side
  // of a wrapping window, or any non-wrapping window); tomorrow when it is
  // not (the late side of a wrapping window). `DateTime`'s constructor
  // normalizes an out-of-range day into the next month/year for us.
  final sameDay = minuteOfDay < endMinutes;
  return DateTime(
    candidate.year,
    candidate.month,
    candidate.day + (sameDay ? 0 : 1),
    hour,
    minute,
  );
}

void _validateMinuteOfDay(int value, String name) {
  if (value < 0 || value > 1439) {
    throw ArgumentError.value(
      value,
      name,
      'Must be in 0..1439 (minutes since local midnight)',
    );
  }
}
```

- [ ] **Step 4: Run, go GREEN, then INVERT three times**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/reminder_planner_test.dart
```

Expected: all pass.

Inversions, each run with the same command:

1. Change `minuteOfDay >= startMinutes` to `minuteOfDay > startMinutes` in
   both branches. **Expected RED:** *a candidate exactly AT start is INSIDE*
   fails with
   `Expected: DateTime:<2026-08-31 07:00:00.000> Actual: DateTime:<2026-08-30 22:00:00.000>`.
2. Change `minuteOfDay < endMinutes` to `minuteOfDay <= endMinutes` in the
   `inside` computation. **Expected RED:** *a candidate exactly AT end is
   OUTSIDE* fails, returning 07:00 the FOLLOWING day rather than the
   candidate.
3. Replace the whole `DateTime(...)` return with
   `candidate.add(Duration(minutes: (endMinutes - minuteOfDay + 1440) % 1440))`.
   **Expected RED:** on a machine in a DST-observing local timezone the
   spring-forward test fails with `Expected: <7> Actual: <8>`; on a UTC CI
   machine it still passes, which is exactly why the *inside a wrapping
   window, LATE side* and *EARLY side* tests exist as absolute-value
   assertions — confirm at least one of those three goes red before restoring.
   If none does on your machine, note it and rely on inversion 1 and 2 for
   this task's red evidence; do not weaken the DST tests.

Restore after each.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/domain/reminder_planner.dart test/domain/reminder_planner_test.dart
git commit -m "Add the N2 id-budget constants and applyQuietHours"
```

### Task 6: `ProjectedOccurrence`'s new fields, the arming rule, and the ceiling (§2.2, §2.3, §3.2, D4)

**Files:**
- Modify: `lib/domain/digest_projection.dart` (class `ProjectedOccurrence`)
- Modify: `lib/application/digest_plan_builder.dart:39-48` (the only lib
  construction site)
- Modify: `test/domain/digest_projection_test.dart:6-20` (the `_occurrence`
  helper — the only test construction site)
- Modify: `lib/domain/reminder_planner.dart`
- Modify: `test/domain/reminder_planner_test.dart`

**Interfaces:**
- Consumes: `applyQuietHours`, `reminderCeiling`, `reminderArmWindowDays`
  (Task 5); `projectedDueDateOn`, `ProjectedOccurrence` (existing).
- Produces: `ProjectedOccurrence.choreId` (`String`, required),
  `.choreTitle` (`String`, required), `.reminderMinutes` (`int?`, optional);
  `class ReminderPlan {DateTime fireAt; String occurrenceId; String choreId;
  String choreTitle; PlainDate dueDate;}`;
  `class ReminderPlanResult {List<ReminderPlan> armed; int overflowCount;}`;
  `ReminderPlanResult planReminders({required DateTime now, required
  Iterable<ProjectedOccurrence> occurrences, required String?
  recipientMemberId, required Map<String, DateTime>
  snoozedUntilByOccurrenceId, required bool quietHoursEnabled, required int
  quietStartMinutes, required int quietEndMinutes})`.

- [ ] **Step 1: Extend `ProjectedOccurrence`**

In `lib/domain/digest_projection.dart`, add three fields to
`ProjectedOccurrence` (constructor parameters in the same order):

```dart
  /// The owning chore's id.
  ///
  /// **Required, not optional**, for the reason [id]'s own doc comment
  /// gives: D4's ceiling tiebreak is "lowest CHORE id", and an optional
  /// field would let a future construction site silently fall back to a
  /// different, unstable ordering. Distinct from [id], which is the
  /// OCCURRENCE's -- an occurrence id changes every time the chore
  /// regenerates, so it is the wrong thing to break a tie with.
  final String choreId;

  /// The owning chore's title, carried verbatim.
  ///
  /// A per-chore reminder's TITLE is the chore title, unlocalized user data
  /// -- that is what makes it actionable and it is the whole of AC1 (spec
  /// `docs/specs/notifications-n2.md` §11). Carried here rather than joined
  /// on later so the pure planner produces a complete [ReminderPlan] and no
  /// application-layer step can attach the wrong title to a position-
  /// relative id.
  final String choreTitle;

  /// The owning chore's `reminder_minutes`, or `null` for "no individual
  /// reminder" (spec `docs/specs/notifications-n2.md` D1).
  ///
  /// Optional (defaulting to `null`) unlike [choreId]/[choreTitle], because
  /// `null` is a meaningful, common and safe value here -- it is what every
  /// chore has until someone turns the switch on -- whereas a defaulted
  /// chore id would be a silently wrong ordering key.
  final int? reminderMinutes;
```

In the constructor: `required this.choreId, required this.choreTitle,
this.reminderMinutes,`.

Update `lib/application/digest_plan_builder.dart`'s map:

```dart
      ProjectedOccurrence(
        id: row.occurrence.id,
        choreId: row.chore.id,
        choreTitle: row.chore.title,
        reminderMinutes: row.chore.reminderMinutes,
        dueDate: row.occurrence.dueDate,
        startDate: row.chore.startDate,
        recurrence: row.chore.recurrence,
        assignedMemberId: row.occurrence.assignedMemberId,
      ),
```

Update `test/domain/digest_projection_test.dart`'s `_occurrence` helper —
adding parameters only, so every existing call site is untouched:

```dart
ProjectedOccurrence _occurrence({
  required PlainDate dueDate,
  String id = 'occ',
  String? choreId,
  String choreTitle = 'Chore',
  int? reminderMinutes,
  PlainDate? startDate,
  Recurrence? recurrence,
  String? assignedMemberId,
}) {
  return ProjectedOccurrence(
    id: id,
    // Defaults to the occurrence id so existing call sites keep distinct
    // chore ids without naming them; tests about the D4 tiebreak pass it
    // explicitly.
    choreId: choreId ?? id,
    choreTitle: choreTitle,
    reminderMinutes: reminderMinutes,
    dueDate: dueDate,
    startDate: startDate ?? dueDate,
    recurrence: recurrence,
    assignedMemberId: assignedMemberId,
  );
}
```

- [ ] **Step 2: Write the failing arming tests**

Append to `test/domain/reminder_planner_test.dart` (add the imports for
`digest_projection.dart`, `recurrence/plain_date.dart`,
`recurrence/recurrence.dart`), with a local helper mirroring the projection
test's:

```dart
ProjectedOccurrence _occ({
  required PlainDate dueDate,
  String id = 'occ',
  String? choreId,
  String choreTitle = 'Bins',
  int? reminderMinutes = 1080, // 18:00 unless a test says otherwise
  PlainDate? startDate,
  Recurrence? recurrence,
  String? assignedMemberId,
}) => ProjectedOccurrence(
  id: id,
  choreId: choreId ?? id,
  choreTitle: choreTitle,
  reminderMinutes: reminderMinutes,
  dueDate: dueDate,
  startDate: startDate ?? dueDate,
  recurrence: recurrence,
  assignedMemberId: assignedMemberId,
);

ReminderPlanResult _plan(
  List<ProjectedOccurrence> occurrences, {
  DateTime? now,
  String? recipientMemberId,
  Map<String, DateTime> snoozes = const {},
  bool quietHoursEnabled = false,
}) => planReminders(
  now: now ?? DateTime(2026, 8, 30, 9),
  occurrences: occurrences,
  recipientMemberId: recipientMemberId,
  snoozedUntilByOccurrenceId: snoozes,
  quietHoursEnabled: quietHoursEnabled,
  quietStartMinutes: 1320,
  quietEndMinutes: 420,
);
```

Then the group:

```dart
  group('planReminders (spec docs/specs/notifications-n2.md §2.3)', () {
    test('a chore with NO reminder_minutes is not eligible at all', () {
      final result = _plan([
        _occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
      ]);
      expect(result.armed, isEmpty);
      expect(result.overflowCount, 0);
    });

    test('arms at the due date at reminder_minutes, and carries the chore '
        'title verbatim', () {
      final result = _plan([
        _occ(id: 'o1', dueDate: PlainDate(2026, 8, 30), choreTitle: 'Bins'),
      ]);
      expect(result.armed, hasLength(1));
      expect(result.armed.single.fireAt, DateTime(2026, 8, 30, 18));
      expect(result.armed.single.occurrenceId, 'o1');
      expect(result.armed.single.choreTitle, 'Bins');
      expect(result.armed.single.dueDate, PlainDate(2026, 8, 30));
    });

    test('a SCHEDULE-anchored chore rolls forward to its next series slot, '
        'and that is a genuine new due date, not a repeat (spec §7)', () {
      // Daily chore, occurrence 3 days stale. On 2026-08-30 catch-up would
      // roll it to today, so today at 18:00 is when it is armed.
      final result = _plan([
        _occ(
          id: 'daily',
          dueDate: PlainDate(2026, 8, 27),
          startDate: PlainDate(2026, 8, 27),
          recurrence: Recurrence.everyNDays(1),
        ),
      ]);
      expect(result.armed.single.fireAt, DateTime(2026, 8, 30, 18));
      expect(result.armed.single.dueDate, PlainDate(2026, 8, 30));
    });

    test('a ONE-OFF does NOT roll forward, so an overdue one is silent '
        '(D8: an individual reminder says "this is due today", never "you '
        'failed")', () {
      final result = _plan([
        _occ(id: 'oneoff', dueDate: PlainDate(2026, 8, 27)),
      ]);
      expect(result.armed, isEmpty);
      expect(result.overflowCount, 0);
    });

    test('a COMPLETION-anchored chore does not roll forward either', () {
      final result = _plan([
        _occ(
          id: 'comp',
          dueDate: PlainDate(2026, 8, 27),
          recurrence: Recurrence.everyNDays(
            3,
            anchor: RecurrenceAnchor.completion,
          ),
        ),
      ]);
      expect(result.armed, isEmpty);
    });

    test('a moment already PAST today is dropped -- 18:00 when it is '
        'already 20:00 (D8)', () {
      final result = _plan(
        [_occ(dueDate: PlainDate(2026, 8, 30))],
        now: DateTime(2026, 8, 30, 20),
      );
      expect(result.armed, isEmpty);
    });

    test('a moment more than reminderArmWindowDays out is dropped (D3), '
        'and one exactly ON the boundary is kept', () {
      final justInside = _plan([
        _occ(
          id: 'in',
          dueDate: PlainDate(2026, 8, 30).addDays(reminderArmWindowDays),
        ),
      ]);
      expect(justInside.armed, hasLength(1));

      final justOutside = _plan([
        _occ(
          id: 'out',
          dueDate: PlainDate(2026, 8, 30).addDays(reminderArmWindowDays + 1),
        ),
      ]);
      expect(justOutside.armed, isEmpty);
      expect(
        justOutside.overflowCount,
        0,
        reason: 'the window is not the ceiling -- a chore too far out did '
            'not LOSE a slot, it never competed for one',
      );
    });

    test('an occurrence assigned to someone else is out of scope (§2.2) -- '
        'a shared reminder_minutes column does not mean a shared alarm', () {
      final result = _plan(
        [
          _occ(id: 'mine', dueDate: PlainDate(2026, 8, 30),
              assignedMemberId: 'me'),
          _occ(id: 'theirs', dueDate: PlainDate(2026, 8, 30),
              assignedMemberId: 'partner'),
          _occ(id: 'anyone', dueDate: PlainDate(2026, 8, 30)),
        ],
        recipientMemberId: 'me',
      );
      expect(
        result.armed.map((plan) => plan.occurrenceId),
        ['anyone', 'mine'], // tie on fireAt -> chore-id ascending
      );
    });

    test('an unresolvable acting member puts EVERYTHING in scope', () {
      final result = _plan([
        _occ(id: 'theirs', dueDate: PlainDate(2026, 8, 30),
            assignedMemberId: 'partner'),
      ]);
      expect(result.armed, hasLength(1));
    });

    test('a FUTURE snooze overrides the arm moment (§2.3 step 3)', () {
      final result = _plan(
        [_occ(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
        snoozes: {'o1': DateTime(2026, 8, 31, 18).toUtc()},
      );
      expect(result.armed.single.fireAt, DateTime(2026, 8, 31, 18));
      expect(
        result.armed.single.dueDate,
        PlainDate(2026, 8, 30),
        reason: 'snooze moves the NOTIFICATION, never the occurrence (D5) '
            '-- the due date it reports is still the real one',
      );
    });

    test('a PAST snooze does not override, and the ordinary arm moment '
        'still applies', () {
      final result = _plan(
        [_occ(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
        snoozes: {'o1': DateTime(2026, 8, 29, 18).toUtc()},
      );
      expect(result.armed.single.fireAt, DateTime(2026, 8, 30, 18));
    });

    test('the quiet-hours shift is applied to a SNOOZED moment too -- §2.3 '
        'step 4 is the only place the shift happens, including for a '
        'snooze', () {
      final result = _plan(
        [_occ(id: 'o1', dueDate: PlainDate(2026, 8, 30),
            reminderMinutes: 1380)], // 23:00, inside 22:00-07:00
        snoozes: {'o1': DateTime(2026, 8, 31, 23).toUtc()},
        quietHoursEnabled: true,
      );
      expect(result.armed.single.fireAt, DateTime(2026, 9, 1, 7));
    });

    test('quiet hours DEFER an ordinary reminder rather than dropping it '
        '(D7)', () {
      final result = _plan(
        [_occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: 1380)],
        quietHoursEnabled: true,
      );
      expect(result.armed.single.fireAt, DateTime(2026, 8, 31, 7));
    });

    test('the armed list is sorted by fire moment ascending, tie-broken by '
        'CHORE id ascending -- stable across recomputes and across devices '
        '(D4)', () {
      final result = _plan([
        _occ(id: 'o3', choreId: 'c-zulu', dueDate: PlainDate(2026, 8, 30)),
        _occ(id: 'o1', choreId: 'c-alpha', dueDate: PlainDate(2026, 8, 31)),
        _occ(id: 'o2', choreId: 'c-bravo', dueDate: PlainDate(2026, 8, 30)),
      ]);
      expect(
        result.armed.map((plan) => plan.choreId),
        ['c-bravo', 'c-zulu', 'c-alpha'],
      );
    });

    group('the ceiling (§3.2, D4)', () {
      List<ProjectedOccurrence> candidates(int count, {int dayOffset = 0}) => [
        for (var i = 0; i < count; i++)
          _occ(
            id: 'o${i.toString().padLeft(3, '0')}',
            choreId: 'c${i.toString().padLeft(3, '0')}',
            dueDate: PlainDate(2026, 8, 30).addDays(dayOffset),
          ),
      ];

      test('34 candidates: the 33 soonest win and exactly one overflows', () {
        final result = _plan(candidates(reminderCeiling + 1));
        expect(result.armed, hasLength(reminderCeiling));
        expect(result.overflowCount, 1);
      });

      test('exactly reminderCeiling candidates: none overflows', () {
        final result = _plan(candidates(reminderCeiling));
        expect(result.armed, hasLength(reminderCeiling));
        expect(result.overflowCount, 0);
      });

      test('NEAREST-FIRST is what wins: a chore due tomorrow beats a chore '
          'due in a week, whatever their ids', () {
        final result = _plan([
          // reminderCeiling chores due in a week, ids sorting FIRST.
          for (var i = 0; i < reminderCeiling; i++)
            _occ(
              id: 'a${i.toString().padLeft(3, '0')}',
              choreId: 'a${i.toString().padLeft(3, '0')}',
              dueDate: PlainDate(2026, 9, 6),
            ),
          // One chore due tomorrow, id sorting LAST.
          _occ(id: 'zzz', choreId: 'zzz', dueDate: PlainDate(2026, 8, 31)),
        ]);
        expect(
          result.armed.first.choreId,
          'zzz',
          reason: 'nearest-first never delays a reminder in favour of a '
              'later one',
        );
        expect(result.armed, hasLength(reminderCeiling));
        expect(result.overflowCount, 1);
      });

      test('overflowCount counts ONLY the chores the CEILING turned away -- '
          'not the ones the 14-day window or the past-moment rule excluded, '
          'which never competed for a slot at all', () {
        final result = _plan([
          // 33 genuine competitors -> all armed.
          for (var i = 0; i < reminderCeiling; i++)
            _occ(
              id: 'in${i.toString().padLeft(3, '0')}',
              choreId: 'in${i.toString().padLeft(3, '0')}',
              dueDate: PlainDate(2026, 8, 31),
            ),
          // 5 reminder-enabled chores beyond the arm window.
          for (var i = 0; i < 5; i++)
            _occ(
              id: 'far$i',
              choreId: 'far$i',
              dueDate: PlainDate(2026, 8, 30)
                  .addDays(reminderArmWindowDays + 1 + i),
            ),
          // 3 reminder-enabled one-offs already overdue.
          for (var i = 0; i < 3; i++)
            _occ(
              id: 'old$i',
              choreId: 'old$i',
              dueDate: PlainDate(2026, 8, 20).addDays(i),
            ),
        ]);
        expect(result.armed, hasLength(reminderCeiling));
        expect(
          result.overflowCount,
          0,
          reason: 'the naive "every reminder-enabled chore minus the armed '
              'ones" would say 8 here, and it would be wrong: the Settings '
              'sub-line promises "N chores stayed in the summary BECAUSE '
              'of the limit"',
        );
      });

      test('...and it does count them when the ceiling really is what bit: '
          '40 competitors inside the window plus 5 outside it overflows by '
          'SEVEN, not twelve', () {
        final result = _plan([
          for (var i = 0; i < 40; i++)
            _occ(
              id: 'in${i.toString().padLeft(3, '0')}',
              choreId: 'in${i.toString().padLeft(3, '0')}',
              dueDate: PlainDate(2026, 8, 31),
            ),
          for (var i = 0; i < 5; i++)
            _occ(
              id: 'far$i',
              choreId: 'far$i',
              dueDate: PlainDate(2026, 8, 30)
                  .addDays(reminderArmWindowDays + 1 + i),
            ),
        ]);
        expect(result.armed, hasLength(reminderCeiling));
        expect(result.overflowCount, 40 - reminderCeiling);
      });

      test('armed.length + overflowCount is the eligible set, always -- the '
          'invariant that makes the two impossible to disagree', () {
        for (final count in [0, 1, reminderCeiling - 1, reminderCeiling,
            reminderCeiling + 1, 100]) {
          final result = _plan(candidates(count));
          expect(
            result.armed.length + result.overflowCount,
            count,
            reason: 'for $count eligible candidates',
          );
        }
      });
    });
  });
```

- [ ] **Step 3: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/reminder_planner_test.dart test/domain/digest_projection_test.dart \
  test/application/digest_plan_builder_test.dart
```

**Expected RED:** `reminder_planner_test.dart` does not compile —
`Error: Undefined name 'planReminders'` and `'ReminderPlanResult' isn't a
type`. The other two suites must be **green** at this step: Step 1's field
additions are purely additive with a defaulted helper, so if either goes red
you have broken an existing call site — fix that before proceeding.

- [ ] **Step 4: Implement `planReminders`**

Append to `lib/domain/reminder_planner.dart` (and add the imports for
`digest_projection.dart` and `recurrence/plain_date.dart`):

```dart
/// One armed individual reminder (spec `docs/specs/notifications-n2.md`
/// §2.3).
///
/// Carries no notification id: **ids are position-relative** -- reminder `i`
/// in [ReminderPlanResult.armed] uses `reminderNotificationIdBase + i` -- so
/// an id names neither a chore nor a date, and the payload is the only
/// channel that can address anything.
class ReminderPlan {
  /// Creates a plan.
  const ReminderPlan({
    required this.fireAt,
    required this.occurrenceId,
    required this.choreId,
    required this.choreTitle,
    required this.dueDate,
  });

  /// The device-local moment this reminder should fire, after the snooze
  /// override and the quiet-hours shift.
  final DateTime fireAt;

  /// The occurrence this reminder is about -- the action payload's `occ`.
  final String occurrenceId;

  /// The owning chore's id; the D4 ceiling tiebreak.
  final String choreId;

  /// The owning chore's title, which is the notification's TITLE verbatim.
  final String choreTitle;

  /// The occurrence's projected due date.
  ///
  /// Carried so the scheduler can pick between "Due today" and "Still open"
  /// (spec §11) by comparing it with [fireAt]'s calendar date, rather than
  /// doing date arithmetic inside a localized string. A snooze or a
  /// quiet-hours deferral is exactly the case where the two differ -- and
  /// the due date is unchanged by either (D5).
  final PlainDate dueDate;
}

/// What one planning pass decided about individual reminders.
class ReminderPlanResult {
  /// Creates a result. Built at exactly one place -- see [planReminders] --
  /// so [armed] and [overflowCount] cannot disagree.
  const ReminderPlanResult({required this.armed, required this.overflowCount});

  /// The reminders to arm, in fire-moment order, at most [reminderCeiling]
  /// of them.
  final List<ReminderPlan> armed;

  /// How many reminder-eligible occurrences the CEILING turned away (spec
  /// §3.2).
  ///
  /// **Not derivable from [armed]**: at the ceiling [armed] has exactly
  /// [reminderCeiling] entries whether one chore overflowed or ninety did,
  /// so the number has to be carried. It is produced at the same truncation
  /// site that produces [armed], which is what makes
  /// `armed.length + overflowCount` the eligible count by construction.
  ///
  /// **Counts only ceiling losses.** An occurrence excluded by the 14-day
  /// window (D3), by the already-overdue rule (D8), by recipient scoping
  /// (§2.2), or by having no `reminder_minutes` at all never competed for a
  /// slot and is NOT counted here. Slice 4's Settings sub-line says "N
  /// chores stayed in the daily summary because this device can hold
  /// [reminderCeiling] reminders at once", and that sentence is only true
  /// of ceiling losses.
  ///
  /// The losers are **not silent**: Rule D omits only ARMED occurrences, so
  /// an occurrence that lost the ordering is counted by its date's digest
  /// slot exactly as it is today. The ceiling degrades one chore from
  /// "individually reminded" to "in the daily summary" -- never into
  /// silence.
  final int overflowCount;
}

/// Plans every individual reminder for [now], over [occurrences], as seen by
/// [recipientMemberId] (spec `docs/specs/notifications-n2.md` §2.3).
///
/// Applies, in order: eligibility (`reminderMinutes != null`), the same
/// recipient scoping `projectDigestCounts` uses (§2.2), the roll-forward via
/// [projectedDueDateOn] (§2.3 step 1 -- deliberately the same function, not
/// a copy), the arm moment from calendar components (step 2), the snooze
/// override for a moment still in the future (step 3), the quiet-hours shift
/// (step 4 -- **the only place** it is applied to a reminder, snoozed or
/// not), and the two drops of step 5. Survivors are sorted by [fireAt]
/// ascending, tie-broken by [ReminderPlan.choreId] ascending, and the first
/// [reminderCeiling] are armed.
///
/// [snoozedUntilByOccurrenceId] holds UTC instants (as stored); they are
/// converted to local before any comparison, because every other moment
/// here is device-local.
ReminderPlanResult planReminders({
  required DateTime now,
  required Iterable<ProjectedOccurrence> occurrences,
  required String? recipientMemberId,
  required Map<String, DateTime> snoozedUntilByOccurrenceId,
  required bool quietHoursEnabled,
  required int quietStartMinutes,
  required int quietEndMinutes,
}) {
  final today = PlainDate.fromDateTime(now);
  final windowEnd = today.addDays(reminderArmWindowDays);
  final eligible = <ReminderPlan>[];
  for (final occurrence in occurrences) {
    final reminderMinutes = occurrence.reminderMinutes;
    if (reminderMinutes == null) {
      continue;
    }
    final assignee = occurrence.assignedMemberId;
    if (recipientMemberId != null &&
        assignee != null &&
        assignee != recipientMemberId) {
      continue;
    }
    final armDate = projectedDueDateOn(occurrence, today);
    // Calendar components, never `add(Duration(days:))` -- the same DST
    // reason `nextDigestSlot` documents.
    var armAt = DateTime(
      armDate.year,
      armDate.month,
      armDate.day,
      reminderMinutes ~/ 60,
      reminderMinutes % 60,
    );
    final snoozedUntil = snoozedUntilByOccurrenceId[occurrence.id]?.toLocal();
    if (snoozedUntil != null && snoozedUntil.isAfter(now)) {
      armAt = snoozedUntil;
    }
    armAt = applyQuietHours(
      candidate: armAt,
      enabled: quietHoursEnabled,
      startMinutes: quietStartMinutes,
      endMinutes: quietEndMinutes,
    );
    if (!armAt.isAfter(now)) {
      continue; // Already past: overdue is the digest's job (D8).
    }
    if (PlainDate.fromDateTime(armAt).isAfter(windowEnd)) {
      continue; // Beyond the fortnight the digest already covers (D3).
    }
    eligible.add(
      ReminderPlan(
        fireAt: armAt,
        occurrenceId: occurrence.id,
        choreId: occurrence.choreId,
        choreTitle: occurrence.choreTitle,
        dueDate: armDate,
      ),
    );
  }
  eligible.sort((a, b) {
    final byMoment = a.fireAt.compareTo(b.fireAt);
    return byMoment != 0 ? byMoment : a.choreId.compareTo(b.choreId);
  });
  // The ONE truncation site: `armed` and `overflowCount` are produced from
  // the same list in the same expression, so they cannot disagree.
  final armed = eligible.length <= reminderCeiling
      ? eligible
      : eligible.sublist(0, reminderCeiling);
  return ReminderPlanResult(
    armed: List<ReminderPlan>.unmodifiable(armed),
    overflowCount: eligible.length - armed.length,
  );
}
```

- [ ] **Step 5: Run, go GREEN, then INVERT four times**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/reminder_planner_test.dart
```

Expected: all pass.

Inversions:

1. Replace `projectedDueDateOn(occurrence, today)` with
   `occurrence.dueDate`. **Expected RED:** *a SCHEDULE-anchored chore rolls
   forward* fails with
   `Expected: DateTime:<2026-08-30 18:00:00.000> Actual: <null>` — the
   occurrence is 3 days stale, so `armAt` lands in the past and the list is
   empty (`result.armed.single` throws `Bad state: No element`). Either
   failure is the red; it must come from THIS test, not from an analyzer
   complaint.
2. Change the tiebreak `a.choreId.compareTo(b.choreId)` to
   `a.occurrenceId.compareTo(b.occurrenceId)`. **Expected RED:** *sorted by
   fire moment ascending, tie-broken by CHORE id* fails with
   `Expected: ['c-bravo', 'c-zulu', 'c-alpha'] Actual: ['c-zulu', 'c-bravo',
   'c-alpha']`.
3. **(BLOCKING)** Change `overflowCount` to
   `occurrences.where((o) => o.reminderMinutes != null).length -
   armed.length`. **Expected RED:** *overflowCount counts ONLY the chores
   the CEILING turned away* fails with `Expected: <0> Actual: <8>`, and *...
   and it does count them when the ceiling really is what bit* fails with
   `Expected: <7> Actual: <12>`. This is the inversion that proves those two
   tests discriminate — it is the plausible wrong implementation, not a
   strawman. **If it does not go red, stop and fix the tests**: the overflow
   count is what slice 4's Settings sub-line puts in front of a user, and a
   number that cannot be wrong in a test will be wrong on a phone.
4. Move the `applyQuietHours` call to BEFORE the snooze override. **Expected
   RED:** *the quiet-hours shift is applied to a SNOOZED moment too* fails
   with
   `Expected: DateTime:<2026-09-01 07:00:00.000> Actual: DateTime:<2026-08-31 23:00:00.000>`.

Restore after each.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/domain test/application
git add lib/domain/reminder_planner.dart lib/domain/digest_projection.dart \
  lib/application/digest_plan_builder.dart test/domain/reminder_planner_test.dart \
  test/domain/digest_projection_test.dart
git commit -m "Add the reminder arming rule, its ceiling and its overflow count"
```

### Task 7: Rule D, and the honest cost to monotonicity (§2.4, §2.5)

**Files:**
- Modify: `lib/domain/digest_projection.dart:160-194` (`projectDigestCounts`)
- Modify: `test/domain/digest_projection_test.dart` (new Rule D group; the
  monotonicity group at line 271 is re-scoped in place)

**Interfaces:**
- Consumes: `ProjectedOccurrence` (Task 6).
- Produces: `projectDigestCounts(..., Map<String, PlainDate>
  armedReminderDates = const {})`.

- [ ] **Step 1: Write the failing tests**

Add a new group to `test/domain/digest_projection_test.dart`, after the
existing `projectDigestCounts` group:

```dart
  group('Rule D -- never announced twice (spec '
      'docs/specs/notifications-n2.md §2.4, D2)', () {
    test('an occurrence with a reminder armed on THIS date is omitted from '
        'dueCount', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30))],
        date: PlainDate(2026, 8, 30),
        recipientMemberId: null,
        armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
      );
      expect(counts.dueCount, 0);
      expect(counts.overdueCount, 0);
      expect(counts.isSilent, isTrue);
    });

    test('...and from overdueCount too, when a quiet-hours deferral moved '
        'the reminder onto a date the occurrence is already overdue on -- '
        '§2.4 states the GENERAL form for exactly this case', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30))],
        date: PlainDate(2026, 8, 31),
        recipientMemberId: null,
        armedReminderDates: {'bins': PlainDate(2026, 8, 31)},
      );
      expect(counts.overdueCount, 0);
      expect(counts.isSilent, isTrue);
    });

    test('an occurrence armed on a DIFFERENT date is counted normally -- '
        'the rule is keyed on the ARMED date, not on the chore', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30))],
        date: PlainDate(2026, 8, 31),
        recipientMemberId: null,
        armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
      );
      expect(
        counts.overdueCount,
        1,
        reason: 'bins reminded Tuesday and ignored MUST reappear in '
            "Wednesday's digest -- that is escalation, not repetition, and "
            'the digest is the overdue channel (§2.4, D8)',
      );
    });

    test('the omission clears the soleOccurrenceId gate as well as the '
        'counts -- a slot that now counts nothing may not carry a Done '
        'button for the thing it stopped counting', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30))],
        date: PlainDate(2026, 8, 30),
        recipientMemberId: null,
        armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
      );
      expect(counts.soleOccurrenceId, isNull);
    });

    test('omitting one of two occurrences promotes the OTHER to sole '
        'occurrence -- the gate is re-decided after the omission, not '
        'before it', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
          _occurrence(id: 'dishes', dueDate: PlainDate(2026, 8, 30)),
        ],
        date: PlainDate(2026, 8, 30),
        recipientMemberId: null,
        armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
      );
      expect(counts.dueCount, 1);
      expect(counts.soleOccurrenceId, 'dishes');
    });

    test('an empty armed map changes nothing at all -- which is what lets '
        'every existing caller and the monotonicity group below stay '
        'verbatim', () {
      final withMap = projectDigestCounts(
        occurrences: [_occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30))],
        date: PlainDate(2026, 8, 30),
        recipientMemberId: null,
        armedReminderDates: const {},
      );
      expect(withMap.dueCount, 1);
      expect(withMap.soleOccurrenceId, 'bins');
    });
  });
```

Then re-scope the monotonicity group. **Do not weaken any existing
assertion.** Make exactly two edits:

(a) Extend the group's "WHY THIS GROUP EXISTS" comment with the scope:

```dart
    // SCOPE, since N2 (spec `docs/specs/notifications-n2.md` §2.5): this
    // property holds over the digest TAKEN ALONE only for occurrence sets
    // with NO armed reminders, and every set below is deliberately such a
    // set -- none of them passes `armedReminderDates`, so the parameter
    // defaults to `const {}`. That is not a weakening: for these sets the
    // sparse tail's original safety argument is untouched and still
    // load-bearing, which is why the group is kept VERBATIM rather than
    // relaxed into an `isNotEmpty`-shaped assertion.
    //
    // What replaces it in general is §0.1's partition, which holds over the
    // UNION of the two channels and is tested in
    // `test/application/digest_plan_builder_test.dart`. The test directly
    // below this group's members proves the loss is real rather than
    // theoretical.
```

(b) Add one new test **inside** the group, after the last existing member:

```dart
    test('the property is GENUINELY LOST once a reminder is armed -- §2.5 '
        'records this as the honest cost, and a comment nobody can fail is '
        'not a record', () {
      final occurrences = [
        _occurrence(id: 'bins', dueDate: PlainDate(2026, 1, 20)),
      ];
      final armed = {'bins': PlainDate(2026, 1, 20)};
      final onItsOwnDate = projectDigestCounts(
        occurrences: occurrences,
        date: PlainDate(2026, 1, 20),
        recipientMemberId: null,
        armedReminderDates: armed,
      );
      final theDayAfter = projectDigestCounts(
        occurrences: occurrences,
        date: PlainDate(2026, 1, 21),
        recipientMemberId: null,
        armedReminderDates: armed,
      );
      expect(
        onItsOwnDate.isSilent,
        isTrue,
        reason: 'the reminder speaks for this date, so the digest does not',
      );
      expect(
        theDayAfter.isSilent,
        isFalse,
        reason: 'silent then non-silent: monotonicity over the digest '
            'alone is broken, exactly as §2.5 says. If this ever passes as '
            'monotone again, Rule D has stopped working.',
      );
    });
```

- [ ] **Step 2: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/digest_projection_test.dart
```

**Expected RED:** the file does not compile —
`Error: No named parameter with the name 'armedReminderDates'`. The
behavioural red comes at Step 4.

- [ ] **Step 3: Implement Rule D**

In `lib/domain/digest_projection.dart`, add the parameter and the skip. The
skip goes **before** the projection/bucketing, not after, so the omission
follows the reminder into whichever bucket the occurrence would have landed
in:

```dart
DigestCounts projectDigestCounts({
  required Iterable<ProjectedOccurrence> occurrences,
  required PlainDate date,
  required String? recipientMemberId,
  Map<String, PlainDate> armedReminderDates = const {},
}) {
  var dueCount = 0;
  var overdueCount = 0;
  String? lastCountedId;
  for (final occurrence in occurrences) {
    final assignee = occurrence.assignedMemberId;
    if (recipientMemberId != null &&
        assignee != null &&
        assignee != recipientMemberId) {
      continue;
    }
    // Rule D (spec `docs/specs/notifications-n2.md` §2.4, D2): this slot
    // omits an occurrence iff an individual reminder for it is armed to
    // fire on THIS slot's own calendar date. Being told twice on one day is
    // precisely the annoyance a per-chore reminder exists to cure.
    //
    // Keyed on the ARMED date, not the due date, so a quiet-hours deferral
    // cannot desynchronise the two channels -- and applied BEFORE bucketing
    // for the same reason: a deferral can move the reminder onto a date the
    // occurrence is already OVERDUE on, and the rule must follow the
    // reminder.
    if (armedReminderDates[occurrence.id] == date) {
      continue;
    }
    final projected = projectedDueDateOn(occurrence, date);
    ...
```

Extend the function's doc comment with a paragraph naming
`armedReminderDates` — "occurrence id -> the calendar date a reminder is
armed on, from `planReminders`; an empty map (the default) is 'no reminders',
which is what every pre-N2 caller means" — and note that the caller must pass
the map produced by the SAME planning pass, since §0.1's partition is a
property of one pass's answers, not of two.

- [ ] **Step 4: Run, go GREEN, then INVERT twice**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/digest_projection_test.dart
```

Expected: all pass.

Inversions:

1. Delete the `if (armedReminderDates[...] == date) continue;` line, keeping
   the parameter (so it still compiles). **Expected RED at the test step:**
   *an occurrence with a reminder armed on THIS date is omitted* fails with
   `Expected: <0> Actual: <1>`, and *the property is GENUINELY LOST* fails on
   `onItsOwnDate.isSilent` with `Expected: true Actual: <false>`.
2. Move the skip to AFTER the `projected` computation and make it only apply
   in the `projected == date` branch (i.e. key it on the due date instead of
   the armed date). **Expected RED:** *...and from overdueCount too* fails
   with `Expected: <0> Actual: <1>`.

Restore after each.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/domain/digest_projection.dart test/domain/digest_projection_test.dart
git commit -m "Add Rule D to the digest projection and re-scope the monotonicity group"
```

### Task 8: The evening re-reminder's slots (§5, D6, D7)

**Files:**
- Modify: `lib/domain/reminder_planner.dart`
- Modify: `test/domain/reminder_planner_test.dart`

**Interfaces:**
- Consumes: `ReminderPlan` (Task 6), `applyQuietHours` (Task 5),
  `digestSlots`/`nextDigestSlot` from `lib/domain/digest_planner.dart`.
- Produces: `class EveningPlan {DateTime fireAt; int openCount; String?
  soleOccurrenceId;}`; `List<EveningPlan?> planEveningSlots({required DateTime
  now, required bool enabled, required int eveningMinutes, required
  Iterable<ProjectedOccurrence> occurrences, required String?
  recipientMemberId, required List<ReminderPlan> armedReminders, required bool
  quietHoursEnabled, required int quietStartMinutes, required int
  quietEndMinutes})` — always exactly `eveningHorizonSlots` long.

- [ ] **Step 1: Write the failing tests**

Append to `test/domain/reminder_planner_test.dart`:

```dart
  group('planEveningSlots (spec docs/specs/notifications-n2.md §5)', () {
    List<EveningPlan?> plan(
      List<ProjectedOccurrence> occurrences, {
      DateTime? now,
      bool enabled = true,
      int eveningMinutes = 1200, // 20:00
      List<ReminderPlan> armed = const [],
      bool quietHoursEnabled = false,
      int quietStart = 1320,
      int quietEnd = 420,
      String? recipientMemberId,
    }) => planEveningSlots(
      now: now ?? DateTime(2026, 8, 30, 9),
      enabled: enabled,
      eveningMinutes: eveningMinutes,
      occurrences: occurrences,
      recipientMemberId: recipientMemberId,
      armedReminders: armed,
      quietHoursEnabled: quietHoursEnabled,
      quietStartMinutes: quietStart,
      quietEndMinutes: quietEnd,
    );

    test('always returns exactly eveningHorizonSlots entries, one per '
        'consecutive day, starting with today when the time is still '
        'ahead', () {
      final slots = plan([_occ(dueDate: PlainDate(2026, 8, 30),
          reminderMinutes: null)]);
      expect(slots, hasLength(eveningHorizonSlots));
      expect(slots.first!.fireAt, DateTime(2026, 8, 30, 20));
      expect(slots[1]!.fireAt, DateTime(2026, 8, 31, 20));
      expect(slots.last!.fireAt, DateTime(2026, 9, 5, 20));
    });

    test('when the evening time has already passed today, the first slot '
        'is tomorrow -- the same rule nextDigestSlot uses', () {
      final slots = plan(
        [_occ(dueDate: PlainDate(2026, 8, 31), reminderMinutes: null)],
        now: DateTime(2026, 8, 30, 21),
      );
      expect(slots.first!.fireAt, DateTime(2026, 8, 31, 20));
    });

    test('disabled: every slot is null', () {
      final slots = plan(
        [_occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        enabled: false,
      );
      expect(slots, everyElement(isNull));
      expect(slots, hasLength(eveningHorizonSlots));
    });

    test('fires on a due-today count, and says how many are open', () {
      final slots = plan([
        _occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
        _occ(id: 'b', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
      ]);
      expect(slots.first!.openCount, 2);
      expect(slots.first!.soleOccurrenceId, isNull);
    });

    test('names a sole occurrence when exactly one counts -- the same gate '
        'the digest uses', () {
      final slots = plan([
        _occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
      ]);
      expect(slots.first!.soleOccurrenceId, 'a');
    });

    test('an OVERDUE-only day does NOT fire (D6) -- this is the whole '
        'anti-nag design', () {
      final slots = plan(
        [_occ(dueDate: PlainDate(2026, 8, 29), reminderMinutes: null)],
      );
      expect(slots.first, isNull);
    });

    test('THE PROPERTY: the same occurrence cannot produce the evening '
        're-reminder two evenings running, because by the second evening '
        'it is overdue rather than due-today (D6). There is no state in '
        'which this feature settles into a nightly drumbeat.', () {
      final slots = plan(
        [_occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
      );
      expect(slots.first!.openCount, 1);
      expect(
        slots.skip(1),
        everyElement(isNull),
        reason: 'every later evening sees it as overdue, and overdue never '
            'counts',
      );
    });

    test('a still-to-come reminder at armAt >= M SUPPRESSES the summary -- '
        'it would arrive minutes later and say the same thing better', () {
      final slots = plan(
        [_occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        armed: [
          ReminderPlan(
            fireAt: DateTime(2026, 8, 30, 21), // after the 20:00 slot
            occurrenceId: 'a',
            choreId: 'c-a',
            choreTitle: 'Bins',
            dueDate: PlainDate(2026, 8, 30),
          ),
        ],
      );
      expect(slots.first, isNull);
    });

    test('a reminder that ALREADY FIRED earlier that evening does NOT '
        'suppress the summary', () {
      final slots = plan(
        [_occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        armed: [
          ReminderPlan(
            fireAt: DateTime(2026, 8, 30, 18), // before the 20:00 slot
            occurrenceId: 'a',
            choreId: 'c-a',
            choreTitle: 'Bins',
            dueDate: PlainDate(2026, 8, 30),
          ),
        ],
      );
      expect(slots.first!.openCount, 1);
    });

    test('a reminder armed on ANOTHER date does not suppress this slot', () {
      final slots = plan(
        [_occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        armed: [
          ReminderPlan(
            fireAt: DateTime(2026, 8, 31, 21),
            occurrenceId: 'a',
            choreId: 'c-a',
            choreTitle: 'Bins',
            dueDate: PlainDate(2026, 8, 30),
          ),
        ],
      );
      expect(slots.first!.openCount, 1);
    });

    test('an evening time inside quiet hours is DROPPED, not deferred (D7) '
        '-- an "evening" re-reminder delivered at 07:00 has a false '
        'premise and would collide with the 08:00 digest', () {
      final slots = plan(
        [_occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        eveningMinutes: 1350, // 22:30, inside 22:00-07:00
        quietHoursEnabled: true,
      );
      expect(slots, everyElement(isNull));
    });

    test('the shipped defaults do not collide: 20:00 evening sits an hour '
        'clear of the 22:00 quiet-hours start', () {
      final slots = plan(
        [_occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        quietHoursEnabled: true,
      );
      expect(slots.first, isNotNull);
    });

    test('recipient scoping applies, exactly as it does to the digest', () {
      final slots = plan(
        [
          _occ(id: 'theirs', dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: null, assignedMemberId: 'partner'),
        ],
        recipientMemberId: 'me',
      );
      expect(slots.first, isNull);
    });
  });
```

- [ ] **Step 2: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain/reminder_planner_test.dart
```

**Expected RED:** `Error: Undefined name 'planEveningSlots'` and
`'EveningPlan' isn't a type`.

- [ ] **Step 3: Implement**

Append to `lib/domain/reminder_planner.dart` (add the import for
`digest_planner.dart`):

```dart
/// One evening re-reminder slot (spec `docs/specs/notifications-n2.md` §5).
class EveningPlan {
  /// Creates a plan.
  const EveningPlan({
    required this.fireAt,
    required this.openCount,
    this.soleOccurrenceId,
  });

  /// The device-local moment this slot should fire.
  final DateTime fireAt;

  /// How many in-scope occurrences are still open on this slot's own date.
  /// `>= 1` by construction -- a slot counting nothing is `null`, not a
  /// plan with a zero -- which is why §11's ICU plural needs no `zero{}`
  /// branch.
  final int openCount;

  /// The single occurrence this slot is about, or `null` when it is about
  /// more than one -- the same gate the digest uses for its Done action.
  /// Unused until slice 7 (notification actions).
  final String? soleOccurrenceId;
}

/// The evening re-reminder's whole horizon: exactly [eveningHorizonSlots]
/// consecutive daily slots at [eveningMinutes], the first chosen by the same
/// "today if still ahead of now, else tomorrow" rule `nextDigestSlot` uses
/// (spec `docs/specs/notifications-n2.md` §5).
///
/// A `null` entry means that slot must be cancelled rather than scheduled.
///
/// A slot at moment `M` on date `D` fires iff at least one in-scope
/// occurrence's projected due date is `D` **and** that occurrence is not
/// about to be individually reminded -- precisely, and not `[armAt on D]`
/// alone: an occurrence is discounted iff it has an armed reminder on `D`
/// with `fireAt >= M`. A reminder that already fired earlier that evening
/// does not suppress the summary; one still to come does, because it would
/// arrive minutes later and say the same thing better.
///
/// **Overdue occurrences never count** (D6). That is the whole anti-nag
/// design, and it is a property rather than a rule: it is impossible to
/// receive this two evenings running about the same occurrence, because by
/// the second evening that occurrence is overdue, not due-today.
///
/// **Quiet hours DROP a slot rather than deferring it** (D7), which is the
/// one place this differs from every other candidate: an "evening"
/// re-reminder delivered at 07:00 has a false premise and would collide
/// with the 08:00 digest.
List<EveningPlan?> planEveningSlots({
  required DateTime now,
  required bool enabled,
  required int eveningMinutes,
  required Iterable<ProjectedOccurrence> occurrences,
  required String? recipientMemberId,
  required List<ReminderPlan> armedReminders,
  required bool quietHoursEnabled,
  required int quietStartMinutes,
  required int quietEndMinutes,
}) {
  final moments = digestSlots(
    now: now,
    digestMinutes: eveningMinutes,
    dailyDays: eveningHorizonSlots,
    weeklySlots: 0,
  );
  if (!enabled) {
    return List<EveningPlan?>.unmodifiable(
      List<EveningPlan?>.filled(moments.length, null),
    );
  }
  final plans = <EveningPlan?>[];
  for (final moment in moments) {
    // Dropped, never deferred (D7): if the shift would move it, it does
    // not fire at all.
    final shifted = applyQuietHours(
      candidate: moment,
      enabled: quietHoursEnabled,
      startMinutes: quietStartMinutes,
      endMinutes: quietEndMinutes,
    );
    if (shifted != moment) {
      plans.add(null);
      continue;
    }
    final date = PlainDate.fromDateTime(moment);
    var openCount = 0;
    String? lastCountedId;
    for (final occurrence in occurrences) {
      final assignee = occurrence.assignedMemberId;
      if (recipientMemberId != null &&
          assignee != null &&
          assignee != recipientMemberId) {
        continue;
      }
      // Due on THIS date. Overdue never counts (D6).
      if (projectedDueDateOn(occurrence, date) != date) {
        continue;
      }
      final stillToCome = armedReminders.any(
        (reminder) =>
            reminder.occurrenceId == occurrence.id &&
            PlainDate.fromDateTime(reminder.fireAt) == date &&
            !reminder.fireAt.isBefore(moment),
      );
      if (stillToCome) {
        continue;
      }
      openCount++;
      lastCountedId = occurrence.id;
    }
    plans.add(
      openCount == 0
          ? null
          : EveningPlan(
              fireAt: moment,
              openCount: openCount,
              soleOccurrenceId: openCount == 1 ? lastCountedId : null,
            ),
    );
  }
  return List<EveningPlan?>.unmodifiable(plans);
}
```

- [ ] **Step 4: Run, go GREEN, then INVERT three times**

Expected: all pass, then:

1. Change `projectedDueDateOn(occurrence, date) != date` to
   `projectedDueDateOn(occurrence, date).isAfter(date)` (i.e. let overdue
   count). **Expected RED:** *an OVERDUE-only day does NOT fire* fails with
   `Expected: null Actual: EveningPlan...`, and *THE PROPERTY* fails on
   `slots.skip(1)` because every later evening now fires.
2. Change `!reminder.fireAt.isBefore(moment)` to
   `reminder.fireAt.isBefore(moment)`. **Expected RED:** *a still-to-come
   reminder SUPPRESSES* fails with `Expected: null Actual: EveningPlan...`
   and *a reminder that ALREADY FIRED does NOT suppress* fails with
   `Expected: <1> Actual: <null>` (a null-dereference on `slots.first!`).
3. Change the quiet-hours block from `plans.add(null); continue;` to
   `moment = shifted` (deferring instead of dropping). **Expected RED:** *an
   evening time inside quiet hours is DROPPED* fails — `slots` is no longer
   all-null.

Restore after each.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/domain/reminder_planner.dart test/domain/reminder_planner_test.dart
git commit -m "Add the evening re-reminder's slot planning"
```

### Task 9: `buildNotificationPlans`, `NotificationPlanSet`, and THE PARTITION TEST (§0.1, §9.1, §13.1)

**This is the task the whole spec exists to make true.** Read §0.1 before
starting.

**Files:**
- Modify: `lib/application/digest_plan_builder.dart`
- Modify: `test/application/digest_plan_builder_test.dart`

**Interfaces:**
- Consumes: `planReminders`/`ReminderPlanResult`/`ReminderPlan` (Task 6),
  Rule D's `armedReminderDates` (Task 7), `planEveningSlots`/`EveningPlan`
  (Task 8).
- Produces: `class NotificationPlanSet {List<DigestPlan?> digest;
  List<ReminderPlan?> reminders; List<EveningPlan?> evening; int
  reminderOverflowCount;}`;
  `NotificationPlanSet buildNotificationPlans({required DateTime now, required
  DeviceSettings settings, required List<OccurrenceWithChore> pending,
  required String? recipientMemberId, Map<String, DateTime>
  snoozedUntilByOccurrenceId = const {}})`. `buildDigestPlans` keeps its
  existing signature and return type. **Slice 4 consumes
  `NotificationPlanSet.reminderOverflowCount` and cites §9.1 as its source;
  it must never re-derive the arming rule at the UI layer.**

- [ ] **Step 1: Write the failing tests**

Append to `test/application/digest_plan_builder_test.dart`. First the
straightforward shape tests (reuse the file's existing fixture helpers for
building `OccurrenceWithChore` rows — read the top of that file rather than
inventing new ones):

```dart
  group('buildNotificationPlans (spec docs/specs/notifications-n2.md §9.1)',
      () {
    test('returns exactly digestHorizonSlots / reminderCeiling / '
        'eveningHorizonSlots entries, always', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: const [],
        recipientMemberId: null,
      );
      expect(plans.digest, hasLength(digestHorizonSlots));
      expect(plans.reminders, hasLength(reminderCeiling));
      expect(plans.evening, hasLength(eveningHorizonSlots));
      expect(plans.reminderOverflowCount, 0);
    });

    test('with no chore carrying reminder_minutes, every reminder and '
        'every evening entry is null -- which is production today, and is '
        'why slices 1-3 change nothing a user can see', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: [_row(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
        recipientMemberId: null,
      );
      expect(plans.reminders, everyElement(isNull));
      expect(plans.evening, everyElement(isNull));
      expect(plans.digest.first, isNotNull);
    });

    test('an armed reminder is packed at the FRONT of the reminder list, '
        'so its position is its id offset', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: [
          _row(id: 'o1', dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: 1080),
        ],
        recipientMemberId: null,
      );
      expect(plans.reminders.first!.occurrenceId, 'o1');
      expect(plans.reminders.skip(1), everyElement(isNull));
    });

    test('buildDigestPlans still returns the digest half and still '
        'compiles for its three existing callers', () {
      final plans = buildDigestPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: [_row(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
        recipientMemberId: null,
      );
      expect(plans, hasLength(digestHorizonSlots));
    });

    test('the overflow count reaches the caller, and it is the PLANNER\'s '
        'number -- slice 4 reads this rather than re-deriving §2.3', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: [
          for (var i = 0; i < reminderCeiling + 4; i++)
            _row(
              id: 'o${i.toString().padLeft(3, '0')}',
              choreId: 'c${i.toString().padLeft(3, '0')}',
              dueDate: PlainDate(2026, 8, 31),
              reminderMinutes: 1080,
            ),
        ],
        recipientMemberId: null,
      );
      expect(plans.reminderOverflowCount, 4);
      expect(
        plans.reminders.whereType<ReminderPlan>(),
        hasLength(reminderCeiling),
      );
      expect(
        plans.reminders.whereType<ReminderPlan>().length +
            plans.reminderOverflowCount,
        reminderCeiling + 4,
        reason: 'the two halves cannot disagree: they come out of one '
            'truncation',
      );
    });

    test('a ceiling LOSER is still counted by the digest -- no chore is '
        'ever silent because of the ceiling (§3.2, D4)', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: [
          for (var i = 0; i < reminderCeiling + 1; i++)
            _row(
              id: 'o${i.toString().padLeft(3, '0')}',
              choreId: 'c${i.toString().padLeft(3, '0')}',
              dueDate: PlainDate(2026, 8, 31),
              reminderMinutes: 1080,
            ),
        ],
        recipientMemberId: null,
      );
      final armedIds = plans.reminders
          .whereType<ReminderPlan>()
          .map((plan) => plan.occurrenceId)
          .toSet();
      final loser = plans.reminders.isEmpty
          ? null
          : ['o${(reminderCeiling).toString().padLeft(3, '0')}']
              .firstWhere((id) => !armedIds.contains(id));
      expect(loser, isNotNull);
      // The 31st's slot must count exactly the one loser: the 33 armed
      // ones are omitted by Rule D, the loser is not.
      final slotForTheDay = plans.digest.firstWhere(
        (plan) => plan != null &&
            PlainDate.fromDateTime(plan.fireAt) == PlainDate(2026, 8, 31),
      )!;
      expect(slotForTheDay.dueTodayCount, 1);
      expect(slotForTheDay.soleOccurrenceId, loser);
    });

    test('the snooze map reaches the arming rule', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(),
        pending: [
          _row(id: 'o1', dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: 1080),
        ],
        recipientMemberId: null,
        snoozedUntilByOccurrenceId: {
          'o1': DateTime(2026, 8, 31, 18).toUtc(),
        },
      );
      expect(plans.reminders.first!.fireAt, DateTime(2026, 8, 31, 18));
    });
  });
```

Then **the partition test**, in its own group:

```dart
  group('THE PARTITION (spec docs/specs/notifications-n2.md §0.1) -- the '
      'one invariant every rule in §2-§6 exists to keep true', () {
    /// Test-local, deliberately independent re-derivation of "which
    /// in-scope occurrences would this date's digest slot count with N2
    /// switched off".
    ///
    /// Written as its own loop rather than by calling `projectDigestCounts`
    /// with an empty armed map: an oracle that calls the function under
    /// test can only ever agree with it, and the whole point of this test
    /// is to catch Rule D omitting the wrong set. It DOES use
    /// `projectedDueDateOn`, which this slice does not touch -- duplicating
    /// the recurrence roll-forward here would test the wrong thing and
    /// would rot.
    Set<String> oracleCountedOn(
      List<ProjectedOccurrence> occurrences,
      PlainDate date,
      String? recipientMemberId,
    ) {
      final counted = <String>{};
      for (final occurrence in occurrences) {
        final assignee = occurrence.assignedMemberId;
        if (recipientMemberId != null &&
            assignee != null &&
            assignee != recipientMemberId) {
          continue;
        }
        // Due on, or overdue as of, this date.
        if (!projectedDueDateOn(occurrence, date).isAfter(date)) {
          counted.add(occurrence.id);
        }
      }
      return counted;
    }

    void expectPartition({
      required List<OccurrenceWithChore> pending,
      required String? recipientMemberId,
      required bool quietHoursEnabled,
      required DateTime now,
      bool requireSilentSlot = false,
    }) {
      final plans = buildNotificationPlans(
        now: now,
        settings: _settings(quietHoursEnabled: quietHoursEnabled),
        pending: pending,
        recipientMemberId: recipientMemberId,
      );
      final projected = [
        for (final row in pending)
          ProjectedOccurrence(
            id: row.occurrence.id,
            choreId: row.chore.id,
            choreTitle: row.chore.title,
            reminderMinutes: row.chore.reminderMinutes,
            dueDate: row.occurrence.dueDate,
            startDate: row.chore.startDate,
            recurrence: row.chore.recurrence,
            assignedMemberId: row.occurrence.assignedMemberId,
          ),
      ];
      final armed = plans.reminders.whereType<ReminderPlan>().toList();

      // CORRECTED IN TASK 0. The original walk did `if (fireAt == null)
      // continue;`, which skipped every SILENT slot -- and a silent slot's
      // answer is "zero", not "no answer". An over-omitting Rule D that
      // drove a slot to zero would have been silently skipped by the one
      // test that exists to catch exactly that. So the slot moments are
      // derived here instead, independently of whether a plan came back,
      // and a `null` plan contributes a digestTotal of 0.
      //
      // The moments are `digestSlots` put through `applyQuietHours`,
      // mirroring what `buildNotificationPlans` does (§6: quiet hours
      // apply to the digest as well). `applyQuietHours` is not the
      // function under test here -- it has its own unit tests in
      // `test/domain/reminder_planner_test.dart` -- so re-using it is not
      // an oracle that agrees with itself.
      final moments = [
        for (final moment in digestSlots(
          now: now,
          digestMinutes: settings.digestMinutes,
        ))
          applyQuietHours(
            candidate: moment,
            enabled: quietHoursEnabled,
            startMinutes: settings.quietStartMinutes,
            endMinutes: settings.quietEndMinutes,
          ),
      ];
      expect(moments, hasLength(plans.digest.length));

      var sawAnArmedDate = false;
      var sawANonSilentSlot = false;
      var sawASilentSlot = false;
      for (var k = 0; k < moments.length; k++) {
        final digestPlan = plans.digest[k];
        final fireAt = moments[k];
        if (digestPlan != null) {
          expect(
            digestPlan.fireAt,
            fireAt,
            reason: 'slot $k fired at a moment the caller cannot predict',
          );
        } else {
          sawASilentSlot = true;
        }
        final date = PlainDate.fromDateTime(fireAt);
        final oracle = oracleCountedOn(projected, date, recipientMemberId);
        final armedOnThisDate = armed
            .where((plan) => PlainDate.fromDateTime(plan.fireAt) == date)
            .map((plan) => plan.occurrenceId)
            .toSet();
        // A null plan is a slot that counted ZERO -- an answer, not the
        // absence of one.
        final digestTotal = digestPlan == null
            ? 0
            : digestPlan.dueTodayCount + digestPlan.overdueCount;

        // (a) NEVER NEITHER, half one: an armed reminder is always for
        //     something this date's digest would otherwise have reported.
        //     A reminder armed for an occurrence outside the oracle set
        //     would be a notification about nothing.
        expect(
          armedOnThisDate.difference(oracle),
          isEmpty,
          reason: 'on $date, a reminder is armed for an occurrence the '
              'digest would not have counted at all',
        );

        // (b) NEVER BOTH and NEVER NEITHER, together: two disjoint subsets
        //     of a finite set whose sizes sum to the whole ARE a
        //     partition. Double-counting makes this sum too big; a hole
        //     makes it too small.
        expect(
          digestTotal + armedOnThisDate.length,
          oracle.length,
          reason: 'on $date the digest counted $digestTotal and '
              '${armedOnThisDate.length} reminders are armed, but '
              '${oracle.length} occurrences are open -- either something '
              'is announced twice or something is announced by nobody',
        );

        if (armedOnThisDate.isNotEmpty) {
          sawAnArmedDate = true;
        }
        if (digestTotal > 0) {
          sawANonSilentSlot = true;
        }
      }

      // Vacuity guards. A fixture that never arms anything, or never has
      // anything to say, satisfies the identity trivially and proves
      // nothing.
      expect(sawAnArmedDate, isTrue,
          reason: 'a walk in which no reminder is ever armed proves nothing');
      expect(sawANonSilentSlot, isTrue,
          reason: 'a walk in which the digest never speaks proves nothing');
      // Coverage rather than vacuity, added in Task 0. `mixedPending`
      // cannot produce a silent slot -- a one-off stays overdue forever,
      // so once anything is due every later slot has something to say --
      // which is precisely why the silent-slot branch needs a fixture of
      // its own (the last test in this group). Only that one asks for it.
      if (requireSilentSlot) {
        expect(sawASilentSlot, isTrue,
            reason: 'the fixture must reach at least one silent slot, '
                'since skipping those was the hole Task 0 closed');
      }
    }

    // A mixed set covering every projection path AND every §2-§6 rule at
    // once: one-off, completion-anchored, schedule-anchored daily and
    // weekly; some reminder-enabled and some not; enough reminder-enabled
    // chores on one date to cross the ceiling; assigned, unassigned and
    // partner-assigned.
    List<OccurrenceWithChore> mixedPending() => [
      _row(id: 'oneoff', choreId: 'c-oneoff',
          dueDate: PlainDate(2026, 9, 2)),
      _row(id: 'oneoff-rem', choreId: 'c-oneoff-rem',
          dueDate: PlainDate(2026, 9, 3), reminderMinutes: 1080),
      _row(id: 'comp', choreId: 'c-comp', dueDate: PlainDate(2026, 9, 4),
          recurrence: Recurrence.everyNDays(
            3, anchor: RecurrenceAnchor.completion)),
      _row(id: 'comp-rem', choreId: 'c-comp-rem',
          dueDate: PlainDate(2026, 9, 5), reminderMinutes: 1200,
          recurrence: Recurrence.everyNDays(
            3, anchor: RecurrenceAnchor.completion)),
      _row(id: 'daily', choreId: 'c-daily', dueDate: PlainDate(2026, 8, 31),
          startDate: PlainDate(2026, 8, 31),
          recurrence: Recurrence.everyNDays(1)),
      _row(id: 'daily-rem', choreId: 'c-daily-rem',
          dueDate: PlainDate(2026, 8, 31),
          startDate: PlainDate(2026, 8, 31), reminderMinutes: 1080,
          recurrence: Recurrence.everyNDays(1)),
      _row(id: 'weekly', choreId: 'c-weekly', dueDate: PlainDate(2026, 8, 31),
          startDate: PlainDate(2026, 8, 31),
          recurrence: Recurrence.weekly(weekdays: const {DateTime.monday})),
      _row(id: 'mine', choreId: 'c-mine', dueDate: PlainDate(2026, 9, 1),
          reminderMinutes: 1080, assignedMemberId: 'me'),
      _row(id: 'theirs', choreId: 'c-theirs', dueDate: PlainDate(2026, 9, 1),
          reminderMinutes: 1080, assignedMemberId: 'partner'),
      // Enough reminder-enabled chores on ONE date to push past the
      // ceiling, so the losers must land back in that date's digest count.
      for (var i = 0; i < reminderCeiling + 3; i++)
        _row(
          id: 'bulk${i.toString().padLeft(3, '0')}',
          choreId: 'c-bulk${i.toString().padLeft(3, '0')}',
          dueDate: PlainDate(2026, 9, 8),
          reminderMinutes: 1080,
        ),
    ];

    test('holds over a mixed set, unscoped, quiet hours OFF', () {
      expectPartition(
        pending: mixedPending(),
        recipientMemberId: null,
        quietHoursEnabled: false,
        now: DateTime(2026, 8, 30, 9),
      );
    });

    test('holds over the same set scoped to a recipient', () {
      expectPartition(
        pending: mixedPending(),
        recipientMemberId: 'me',
        quietHoursEnabled: false,
        now: DateTime(2026, 8, 30, 9),
      );
    });

    test('holds with quiet hours ON -- a deferral moves a reminder onto '
        'the FOLLOWING calendar date, and Rule D must follow the '
        'reminder rather than the due date (§2.4)', () {
      // Reminder times of 1080/1200 are outside 22:00-07:00, so this
      // fixture is re-pointed at a late reminder time to force deferrals.
      final pending = [
        for (final row in mixedPending())
          row.chore.reminderMinutes == null
              ? row
              : _reminderAt(row, 1380), // 23:00 -> deferred to 07:00 + 1 day
      ];
      expectPartition(
        pending: pending,
        recipientMemberId: null,
        quietHoursEnabled: true,
        now: DateTime(2026, 8, 30, 9),
      );
    });

    test('holds when the digest time has ALREADY PASSED today, so slot 0 '
        'is tomorrow and today has no slot at all', () {
      expectPartition(
        pending: mixedPending(),
        recipientMemberId: null,
        quietHoursEnabled: false,
        now: DateTime(2026, 8, 30, 20),
      );
    });

    test('holds across SILENT slots too -- a slot that counts zero has an '
        'answer, and §2.5 says the digest goes silent on exactly the date '
        'a reminder speaks for it', () {
      // Everything is far enough out that the horizon opens with genuinely
      // empty slots. `mixedPending` cannot do this: a one-off stays
      // overdue forever, so once anything is due every later slot speaks.
      expectPartition(
        pending: [
          _row(id: 'later', choreId: 'c-later', dueDate: PlainDate(2026, 9, 5)),
          _row(id: 'later-rem', choreId: 'c-later-rem',
              dueDate: PlainDate(2026, 9, 8), reminderMinutes: 1080),
        ],
        recipientMemberId: null,
        quietHoursEnabled: false,
        now: DateTime(2026, 8, 30, 9),
        requireSilentSlot: true,
      );
    });
  });
```

**CORRECTED IN TASK 0 — the helpers do not exist and the file is
deliberately integration-style.** `test/application/digest_plan_builder_test
.dart` builds every `OccurrenceWithChore` through a real in-memory
`AppDatabase` + real `ChoreService`, and its own doc comment says why:
"rather than hand-built drift rows that could drift from it". That cannot
serve this group — the partition fixture needs ~45 rows with DETERMINISTIC
chore ids (D4's tiebreak is "lowest chore id" and the ceiling test names a
specific loser), and `ChoreRepository.newId` hands out UUIDs.

So add these three helpers, and say at the top of the new groups that they
are hand-built on purpose:

- `_row({required String id, required PlainDate dueDate, String? choreId,
  String choreTitle = 'Chore', int? reminderMinutes, PlainDate? startDate,
  Recurrence? recurrence, String? assignedMemberId})` — constructs
  `OccurrenceWithChore` from a `Chore` and a `ChoreOccurrence` literal
  directly. `choreId` defaults to `id`.
- `_reminderAt(OccurrenceWithChore row, int minutes)` — returns a copy with
  `chore: row.chore.copyWith(reminderMinutes: Value(minutes))`.
- `_settings({bool quietHoursEnabled = false, int? digestMinutes})` —
  **`settings.copyWith(...)` over the REAL `ensureSettings()` row from
  `setUp`**, never a hand-built `DeviceSettings` literal. A literal would
  have to be edited every time any column is added to `settings`, and would
  silently disagree with the schema's own defaults in between.

Leave every pre-existing test in the file exactly as it is: they stay
integration-style, and this group is the only hand-built one.

- [ ] **Step 2: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application/digest_plan_builder_test.dart
```

**Expected RED:** `Error: Undefined name 'buildNotificationPlans'` and
`'NotificationPlanSet' isn't a type`.

- [ ] **Step 3: Implement**

In `lib/application/digest_plan_builder.dart`, add the import for
`lib/domain/reminder_planner.dart` and:

```dart
/// Everything one planning pass decided: the digest's horizon, the armed
/// individual reminders and the evening re-reminder's horizon (spec
/// `docs/specs/notifications-n2.md` §9.1).
///
/// Produced by a SINGLE call to [buildNotificationPlans] and applied by a
/// SINGLE enqueued write (`NotificationScheduler.applyPlans`, D9): Rule D
/// couples the digest's counts to the reminders' arming, so two passes or
/// two writes open a window in which a chore is announced twice or not at
/// all.
class NotificationPlanSet {
  /// Creates a plan set.
  const NotificationPlanSet({
    required this.digest,
    required this.reminders,
    required this.evening,
    required this.reminderOverflowCount,
  });

  /// Exactly `digestHorizonSlots` entries; index `k` is digest slot `k`.
  final List<DigestPlan?> digest;

  /// Exactly `reminderCeiling` entries; index `i` is notification id
  /// `reminderNotificationIdBase + i`. Armed reminders are packed at the
  /// FRONT in fire-moment order and the tail is `null`, because ids are
  /// position-relative (§2.3).
  final List<ReminderPlan?> reminders;

  /// Exactly `eveningHorizonSlots` entries; index `k` is notification id
  /// `eveningNotificationIdBase + k`.
  final List<EveningPlan?> evening;

  /// How many reminder-eligible occurrences the ceiling turned away (§3.2).
  ///
  /// **Slice 4's Settings sub-line reads THIS**, and must never re-derive
  /// §2.3's arming rule at the UI layer: a second copy of that rule would
  /// drift from this one the moment either changed. Forwarded verbatim from
  /// [ReminderPlanResult.overflowCount] -- see there for why it counts only
  /// ceiling losses and why it cannot be derived from [reminders].
  final int reminderOverflowCount;
}

/// The whole notification plan for [now] (spec
/// `docs/specs/notifications-n2.md` §9.1).
///
/// Computes in the order **reminders -> evening -> digest**, and that order
/// is load-bearing: Rule D (§2.4) and §5's suppression both read the armed
/// set, so it must exist before either runs.
///
/// [snoozedUntilByOccurrenceId] is `occurrenceId -> UTC instant`, from
/// `ReminderSnoozeRepository.activeSnoozes`. It is a parameter rather than a
/// read because this function must stay free of any I/O -- the same reason
/// [pending] is passed in.
NotificationPlanSet buildNotificationPlans({
  required DateTime now,
  required DeviceSettings settings,
  required List<OccurrenceWithChore> pending,
  required String? recipientMemberId,
  Map<String, DateTime> snoozedUntilByOccurrenceId = const {},
}) {
  final occurrences = _projected(pending);

  // 1. Reminders first -- everything below reads the armed set.
  final reminderResult = planReminders(
    now: now,
    occurrences: occurrences,
    recipientMemberId: recipientMemberId,
    snoozedUntilByOccurrenceId: snoozedUntilByOccurrenceId,
    quietHoursEnabled: settings.quietHoursEnabled,
    quietStartMinutes: settings.quietStartMinutes,
    quietEndMinutes: settings.quietEndMinutes,
  );

  // 2. Evening, which is suppressed by a still-to-come reminder (§5).
  final evening = planEveningSlots(
    now: now,
    enabled: settings.eveningReminderEnabled,
    eveningMinutes: settings.eveningReminderMinutes,
    occurrences: occurrences,
    recipientMemberId: recipientMemberId,
    armedReminders: reminderResult.armed,
    quietHoursEnabled: settings.quietHoursEnabled,
    quietStartMinutes: settings.quietStartMinutes,
    quietEndMinutes: settings.quietEndMinutes,
  );

  // 3. Digest, minus whatever a reminder is about to announce (Rule D).
  final armedReminderDates = <String, PlainDate>{
    for (final plan in reminderResult.armed)
      plan.occurrenceId: PlainDate.fromDateTime(plan.fireAt),
  };
  final digest = _digestPlans(
    now: now,
    settings: settings,
    occurrences: occurrences,
    recipientMemberId: recipientMemberId,
    armedReminderDates: armedReminderDates,
  );

  return NotificationPlanSet(
    digest: digest,
    reminders: List<ReminderPlan?>.unmodifiable([
      ...reminderResult.armed,
      for (var i = reminderResult.armed.length; i < reminderCeiling; i++) null,
    ]),
    evening: evening,
    reminderOverflowCount: reminderResult.overflowCount,
  );
}
```

Refactor the existing `buildDigestPlans` so both entry points share one
implementation — extract its `ProjectedOccurrence` mapping into
`List<ProjectedOccurrence> _projected(List<OccurrenceWithChore> pending)` and
its slot loop into `List<DigestPlan?> _digestPlans({...required Map<String,
PlainDate> armedReminderDates})`, then make `buildDigestPlans` call them with
`armedReminderDates: const {}`.

**`_digestPlans` puts every slot moment through `applyQuietHours` before
using it** (ADDED IN TASK 0 — see correction 1; §6 says in as many words
that "quiet hours apply to the **digest** as well", and D7 names the digest
first in "deferred, never dropped", but no task in this plan applied it):

```dart
  for (final rawFireAt in digestSlots(
    now: now,
    digestMinutes: settings.digestMinutes,
  )) {
    // Spec §6/D7: quiet hours DEFER the digest, never drop it -- the
    // evening re-reminder is the sole exception and it lives in
    // `planEveningSlots`. The counts are then computed for the SHIFTED
    // date, because the slot now speaks on that date and Rule D is keyed
    // on the date each channel actually fires on.
    //
    // Two slots can never collide: slot k at 23:30 on day k defers to
    // 07:00 on day k+1, and slot k+1 defers to day k+2.
    //
    // Nothing ships changed by this: quiet hours default OFF, and the
    // shipped 08:00 digest is outside the default 22:00-07:00 window
    // anyway (§6's closing paragraph).
    final fireAt = applyQuietHours(
      candidate: rawFireAt,
      enabled: settings.quietHoursEnabled,
      startMinutes: settings.quietStartMinutes,
      endMinutes: settings.quietEndMinutes,
    );
    ...
```

Add three tests for it to the `buildNotificationPlans` group:

```dart
    test('quiet hours DEFER a digest slot rather than dropping it (§6, '
        'D7) -- and the counts follow it onto the shifted date', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        // 23:30 digest, inside the default 22:00-07:00 window.
        settings: _settings(quietHoursEnabled: true, digestMinutes: 1410),
        pending: [_row(id: 'o1', dueDate: PlainDate(2026, 8, 31))],
        recipientMemberId: null,
      );
      expect(plans.digest.first!.fireAt, DateTime(2026, 8, 31, 7));
      expect(
        plans.digest.first!.dueTodayCount,
        1,
        reason: 'the slot deferred onto the 31st, so it must count the '
            "31st's work, not the 30th's",
      );
    });

    test('...and a digest slot OUTSIDE the window is untouched, which is '
        'every shipped install: 08:00 is outside 22:00-07:00', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(quietHoursEnabled: true),
        pending: [_row(id: 'o1', dueDate: PlainDate(2026, 8, 31))],
        recipientMemberId: null,
      );
      expect(plans.digest.first!.fireAt, DateTime(2026, 8, 31, 8));
    });

    test('quiet hours OFF leave a late digest exactly where it was -- the '
        'shift is opt-in, so v0.8.0 behaviour is byte-identical', () {
      final plans = buildNotificationPlans(
        now: DateTime(2026, 8, 30, 9),
        settings: _settings(digestMinutes: 1410),
        pending: [_row(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
        recipientMemberId: null,
      );
      expect(plans.digest.first!.fireAt, DateTime(2026, 8, 30, 23, 30));
    });
```

and a fourth inversion at step 4: drop the `applyQuietHours` call from
`_digestPlans`. **Expected RED:** *quiet hours DEFER a digest slot* fails
with `Expected: <2026-08-31 07:00:00.000> Actual: <2026-08-31 23:30:00.000>`.

Add to `buildDigestPlans`'s doc comment:

```dart
/// **Rule D is deliberately NOT applied here** (`armedReminderDates` is
/// empty): this entry point exists for the two callers that must not
/// rewrite reminders -- `DigestPrepromptBanner._enable`, which is about to
/// trigger a full recompute anyway via its settings write, and
/// `rewriteDigestHorizon` in the background isolate, which
/// `docs/specs/notifications-n2.md` §10.1 explicitly limits to the digest.
/// Both therefore write a digest horizon that can be stale by one
/// occurrence until the next recompute, and §10.1 accepts that because the
/// staleness always errs toward REPORTING a chore, never toward hiding one.
/// New callers should use [buildNotificationPlans].
```

- [ ] **Step 4: Run, go GREEN, then INVERT four times**

Expected: all pass. Then:

1. **(BLOCKING)** Reorder the pass to **digest -> reminders -> evening** (build
   `armedReminderDates` from an empty list before `planReminders` runs).
   **Expected RED:** the partition test fails with
   `digestTotal + armedOnThisDate.length` too big — e.g.
   `Expected: <34> Actual: <67>` on the 2026-09-08 bulk date.
2. Pad the reminder list at the FRONT instead of the back (`[...nulls,
   ...armed]`). **Expected RED:** *an armed reminder is packed at the FRONT*
   fails with a null-dereference on `plans.reminders.first!`. This is what
   protects the position-relative id contract.
3. **(BLOCKING)** Key `armedReminderDates` on `plan.dueDate` instead of
   `PlainDate.fromDateTime(plan.fireAt)`. **Expected RED:** the *holds with
   quiet hours ON* partition test fails on the cardinality identity — a
   deferred reminder is omitted from the wrong date's slot, so one date
   double-counts and the next has a hole.
4. Hard-code `reminderOverflowCount: 0`. **Expected RED:** *the overflow
   count reaches the caller* fails with `Expected: <4> Actual: <0>`.

Restore after each. **If inversion 1 or 3 does NOT go red, stop:** the
partition test is not discriminating and must be fixed before this task is
considered done — that is the exact failure shape wave 6 found four of.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/domain test/application
git add lib/application/digest_plan_builder.dart \
  test/application/digest_plan_builder_test.dart
git commit -m "Add buildNotificationPlans, the plan set and the partition test"
```

**Slice 2 is complete.** The whole planning core exists, is pure, and is not
called by anything yet.

---

# Slice 3 — The scheduler

Four tasks. The planning core gets wired to the OS, still with nothing to
schedule on a real device.

### Task 10: The plugin seam gains a channel, and the two new channels exist (§9.3, §11)

**Files:**
- Modify: `lib/application/notification_scheduler.dart` (the
  `DigestNotificationPlugin` interface, `FlutterLocalNotificationsAdapter`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Modify: `test/application/fake_digest_notification_plugin.dart`
- Modify: `test/application/notification_scheduler_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `const String remindersChannelId = 'reminders_v1';`,
  `const String eveningChannelId = 'evening_v1';`;
  `DigestNotificationPlugin.zonedSchedule({..., required String channelId,
  ...})`; `ScheduledCall.channelId`; l10n keys
  `notificationChannelRemindersName`, `notificationChannelRemindersDescription`,
  `notificationChannelEveningName`, `notificationChannelEveningDescription`,
  `reminderBodyDueToday`, `reminderBodyStillOpen`, `eveningReminderBody`.

- [ ] **Step 1: Add the l10n keys**

In `lib/l10n/app_en.arb`, after the existing digest channel keys:

```json
  "notificationChannelRemindersName": "Chore reminders",
  "@notificationChannelRemindersName": {
    "description": "Android notification channel name for per-chore reminders, shown in system Settings -> Apps -> Notifications. Android caches this at channel-creation time and cannot rename it later, which is why remindersChannelId is versioned (_v1). Any change to this copy must mint a new channel id AND delete the one it replaces."
  },
  "notificationChannelRemindersDescription": "Reminders for individual chores at the time you chose.",
  "@notificationChannelRemindersDescription": {
    "description": "Android notification channel description for per-chore reminders, shown under notificationChannelRemindersName in system Settings."
  },
  "notificationChannelEveningName": "Evening reminder",
  "@notificationChannelEveningName": {
    "description": "Android notification channel name for the evening re-reminder. Same channel-id versioning constraint as notificationChannelRemindersName."
  },
  "notificationChannelEveningDescription": "An evening nudge when chores are still open today.",
  "@notificationChannelEveningDescription": {
    "description": "Android notification channel description for the evening re-reminder, shown under notificationChannelEveningName in system Settings."
  },
  "reminderBodyDueToday": "Due today",
  "@reminderBodyDueToday": {
    "description": "Body of a per-chore reminder notification whose armed date IS the chore's due date. The notification's TITLE is the chore title verbatim (user data, not localized) -- that is what makes it actionable. Keep this short: it sits under the chore's own name."
  },
  "reminderBodyStillOpen": "Still open",
  "@reminderBodyStillOpen": {
    "description": "Body of a per-chore reminder notification whose armed date is LATER than the due date -- a snooze, or a quiet-hours deferral. Deliberately a second plain key rather than date arithmetic inside one string."
  },
  "eveningReminderBody": "{count, plural, one{1 chore still open today} other{{count} chores still open today}}",
  "@eveningReminderBody": {
    "description": "Body of the evening re-reminder notification. count >= 1 by construction (a slot counting nothing is never scheduled), hence no zero branch -- and CLDR has no distinct zero category in en or de anyway.",
    "placeholders": {
      "count": { "type": "int", "example": "3" }
    }
  },
```

In `lib/l10n/app_de.arb` (informal *du*; "Gerät", never "Handy"):

```json
  "notificationChannelRemindersName": "Aufgaben-Erinnerungen",
  "notificationChannelRemindersDescription": "Erinnerungen an einzelne Aufgaben zur von dir gewählten Zeit.",
  "notificationChannelEveningName": "Abend-Erinnerung",
  "notificationChannelEveningDescription": "Ein Hinweis am Abend, wenn heute noch Aufgaben offen sind.",
  "reminderBodyDueToday": "Heute fällig",
  "reminderBodyStillOpen": "Noch offen",
  "eveningReminderBody": "{count, plural, one{1 Aufgabe ist heute noch offen} other{{count} Aufgaben sind heute noch offen}}",
```

**No ICU `zero{}` branch anywhere** (§11): CLDR has no distinct zero category
in en or de, so the branch never fires.

```bash
flutter gen-l10n
```

- [ ] **Step 2: Write the failing tests**

In `test/application/notification_scheduler_test.dart`, add to the channel
group:

```dart
    test('the reminder and evening channel ids are minted fresh and are '
        'distinct from the digest\'s -- Android caches channel copy at '
        'creation and cannot rename, so reusing digest_v2 would give these '
        'two the digest\'s name forever (spec '
        'docs/specs/notifications-n2.md §9.3)', () {
      expect(remindersChannelId, 'reminders_v1');
      expect(eveningChannelId, 'evening_v1');
      expect({digestChannelId, remindersChannelId, eveningChannelId},
          hasLength(3));
    });

    test('the digest still schedules on its own channel after the seam '
        'gained a channelId -- E-1\'s localized name must not move', () async {
      await scheduler.applyDigestPlans(onlySlotZero());
      expect(plugin.scheduledCalls.single.channelId, digestChannelId);
    });
```

In `test/application/fake_digest_notification_plugin.dart`, add
`required this.channelId,` to `ScheduledCall`'s constructor, the field:

```dart
  /// The Android notification channel id passed to `zonedSchedule` (spec
  /// `docs/specs/notifications-n2.md` §9.3): one of `digestChannelId`,
  /// `remindersChannelId` or `eveningChannelId`.
  final String channelId;
```

include it in `toString()`, add `required String channelId,` to the fake's
`zonedSchedule` override and pass it into the recorded `ScheduledCall`.

- [ ] **Step 3: Run and watch it go RED**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application/notification_scheduler_test.dart
```

**Expected RED:** `Error: Undefined name 'remindersChannelId'`, plus
`Error: The named parameter 'channelId' is required, but there's no
corresponding argument` in the fake (its `zonedSchedule` no longer matches
the interface). Both are signature reds; the behavioural one is Step 5's
inversion.

- [ ] **Step 4: Implement**

In `lib/application/notification_scheduler.dart`, after `digestChannelId` /
`legacyDigestChannelId`:

```dart
/// The Android notification channel per-chore reminders are posted on (spec
/// `docs/specs/notifications-n2.md` §9.3).
///
/// Its own channel, not the digest's, so a user can mute one instrument
/// without losing the others. **Default importance**, matching the digest,
/// and that is a decision rather than an oversight: AC1's complaint is that
/// reminders are untimely and anonymous, not that they are quiet, and
/// shipping high-importance heads-up popups for household chores is what
/// gets an app muted wholesale. A user who wants more can raise it per
/// channel in system Settings.
///
/// Inherits E-1's constraints in full (see [digestChannelId]): the localized
/// name and description are passed per [DigestNotificationPlugin
/// .zonedSchedule] call and take effect only the FIRST time this app creates
/// the channel on a device, and **any future change to that copy must mint a
/// new id AND delete the one it replaces** -- Android has no rename. The
/// same accepted staleness applies: a language switch does not relabel an
/// existing channel.
const String remindersChannelId = 'reminders_v1';

/// The Android notification channel the evening re-reminder is posted on
/// (spec `docs/specs/notifications-n2.md` §9.3). Same importance and same
/// id-versioning constraint as [remindersChannelId].
const String eveningChannelId = 'evening_v1';
```

Add `required String channelId,` to `DigestNotificationPlugin.zonedSchedule`
(document it: "which Android channel to post on — the caller decides, because
one apply now writes three ranges with three different channels; ignored off
Android"), and in `FlutterLocalNotificationsAdapter.zonedSchedule` replace the
hard-coded `digestChannelId` in `AndroidNotificationDetails` with the
parameter. In `NotificationScheduler._applyDigestPlansNow`, pass
`channelId: digestChannelId`.

- [ ] **Step 5: Run, go GREEN, then INVERT**

Expected: all pass (the whole `test/application` and `test/app` directories,
since `ScheduledCall` changed shape).

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application test/app
```

Invert: make `_applyDigestPlansNow` pass `channelId: remindersChannelId`.
**Expected RED at the test step:** *the digest still schedules on its own
channel* fails with `Expected: 'digest_v2' Actual: 'reminders_v1'`. Restore.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/application/notification_scheduler.dart lib/l10n/app_en.arb \
  lib/l10n/app_de.arb test/application/fake_digest_notification_plugin.dart \
  test/application/notification_scheduler_test.dart
git commit -m "Give the notification seam a channel id and mint the reminder and evening channels"
```

### Task 11: `applyPlans` — one enqueued write over three id ranges (§9.2, D9)

**Files:**
- Modify: `lib/application/notification_scheduler.dart`
- Modify: `test/application/notification_scheduler_test.dart`

**Interfaces:**
- Consumes: `NotificationPlanSet` (Task 9); `remindersChannelId`,
  `eveningChannelId` (Task 10).
- Produces: `NotificationScheduler.applyPlans(NotificationPlanSet plans,
  {String? actingMemberId})`; the field rename `_digestWriteTail` ->
  `_notificationWriteTail`. `applyDigestPlans` is unchanged and still public.

- [ ] **Step 1: Write the failing tests**

Add a group to `test/application/notification_scheduler_test.dart`:

```dart
  group('applyPlans (spec docs/specs/notifications-n2.md §9.2)', () {
    NotificationPlanSet planSet({
      List<ReminderPlan?>? reminders,
      List<EveningPlan?>? evening,
      List<DigestPlan?>? digest,
    }) => NotificationPlanSet(
      digest: digest ??
          List<DigestPlan?>.filled(digestHorizonSlots, null),
      reminders: reminders ??
          List<ReminderPlan?>.filled(reminderCeiling, null),
      evening: evening ??
          List<EveningPlan?>.filled(eveningHorizonSlots, null),
      reminderOverflowCount: 0,
    );

    test('reminder i schedules id reminderNotificationIdBase + i', () async {
      await scheduler.applyPlans(
        planSet(
          reminders: [
            ReminderPlan(
              fireAt: DateTime(2026, 8, 30, 18),
              occurrenceId: 'o1',
              choreId: 'c1',
              choreTitle: 'Bins',
              dueDate: PlainDate(2026, 8, 30),
            ),
            ...List<ReminderPlan?>.filled(reminderCeiling - 1, null),
          ],
        ),
      );
      final call = plugin.scheduledCalls.single;
      expect(call.id, reminderNotificationIdBase);
      expect(call.title, 'Bins', reason: 'the TITLE is the chore title '
          'verbatim -- that is the whole of AC1 (§11)');
      expect(call.body, 'Due today');
      expect(call.channelId, remindersChannelId);
      expect(call.actionable, isFalse,
          reason: 'actions are slice 7; a reminder must NOT reuse '
              'digestDoneActionId (notifications.md requires each surface '
              'to mint its own)');
      expect(call.payload, isNull);
    });

    test('a reminder armed LATER than its due date says "Still open" -- a '
        'snooze or a quiet-hours deferral (§11)', () async {
      await scheduler.applyPlans(
        planSet(
          reminders: [
            ReminderPlan(
              fireAt: DateTime(2026, 8, 31, 7),
              occurrenceId: 'o1',
              choreId: 'c1',
              choreTitle: 'Bins',
              dueDate: PlainDate(2026, 8, 30),
            ),
            ...List<ReminderPlan?>.filled(reminderCeiling - 1, null),
          ],
        ),
      );
      expect(plugin.scheduledCalls.single.body, 'Still open');
    });

    test('evening slot k schedules id eveningNotificationIdBase + k, on '
        'its own channel, with the ICU plural body', () async {
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[2] = EveningPlan(
        fireAt: DateTime(2026, 9, 1, 20),
        openCount: 3,
      );
      await scheduler.applyPlans(planSet(evening: evening));
      final call = plugin.scheduledCalls.single;
      expect(call.id, eveningNotificationIdBase + 2);
      expect(call.channelId, eveningChannelId);
      expect(call.body, '3 chores still open today');
    });

    test('a single open chore uses the ICU singular', () async {
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[0] = EveningPlan(
        fireAt: DateTime(2026, 8, 30, 20),
        openCount: 1,
        soleOccurrenceId: 'o1',
      );
      await scheduler.applyPlans(planSet(evening: evening));
      expect(plugin.scheduledCalls.single.body, '1 chore still open today');
    });

    test('a null entry CANCELS its id rather than scheduling it, across '
        'all three ranges', () async {
      await scheduler.applyPlans(planSet());
      expect(plugin.scheduledCalls, isEmpty);
      expect(
        plugin.cancelCallCount,
        digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
      );
    });

    // CORRECTED IN TASK 0: the "ONE enqueued write, not three (D9)" test
    // that stood here asserted that the later of two concurrent applies
    // wins the reminder range. That is FIFO, and FIFO holds in BOTH shapes
    // -- the enqueue is synchronous, so three chained sub-writes still
    // leave A's reminder write ahead of B's. It could not fail through the
    // very inversion it existed to catch, which is wave 6's failure shape.
    // Two all-`applyPlans` callers cannot discriminate either: B's own
    // per-range sub-writes land behind A's, range by range, and the end
    // state is identical.
    //
    // What actually distinguishes one write from three is that three leave
    // GAPS a DIFFERENT KIND of write can be scheduled into -- and the only
    // other write is `cancelAll`, which arrives in Task 12. The replacement
    // test therefore lives in **Task 12 step 1**, where it can exist at
    // all. Nothing about D9 is untested; it is tested one task later.

    test('rejects a plan set whose lists are the wrong length', () {
      expect(
        () => scheduler.applyPlans(
          NotificationPlanSet(
            digest: const [],
            reminders: List<ReminderPlan?>.filled(reminderCeiling, null),
            evening: List<EveningPlan?>.filled(eveningHorizonSlots, null),
            reminderOverflowCount: 0,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
```

`_GatedPlugin` already exists at the top of
`test/application/notification_scheduler_test.dart` (it pauses the first call
of one kind until `release()`); reuse it rather than writing a second pausing
fake. Never add a `skip:` to any test here — a skipped test is a test that
cannot fail.

- [ ] **Step 2: Run and watch it go RED**

**Expected RED:** `Error: The method 'applyPlans' isn't defined for the class
'NotificationScheduler'`.

- [ ] **Step 3: Implement**

In `lib/application/notification_scheduler.dart`:

1. Rename the field `_digestWriteTail` to `_notificationWriteTail` and the
   method `_enqueueDigestWrite` to `_enqueueNotificationWrite`, updating the
   three call sites and every doc-comment reference. **Keep every property
   G-12 pinned, verbatim:** the enqueue stays **synchronous** (the tail is
   read and reassigned before any suspension point — an `async` version would
   let two callers in the same turn capture the same predecessor and the
   serialization would be silently vacuous); the tail is still assigned the
   error-swallowing variant while the caller is handed the raw one; ordering
   is still FIFO by arrival. Extend the field's doc comment to say it now
   covers all three ranges and why (D9).
2. Add:

```dart
  /// Rewrites ALL THREE notification id ranges -- the digest horizon, the
  /// individual reminders and the evening re-reminder horizon -- inside a
  /// SINGLE enqueued write (spec `docs/specs/notifications-n2.md` §9.2, D9).
  ///
  /// Not three enqueued writes: Rule D couples the digest's counts to the
  /// reminders' arming, and two writes with a gap between them is a window
  /// in which a chore is announced twice or not at all.
  ///
  /// A non-null entry is scheduled on its range's base plus its index; a
  /// `null` entry cancels that id. Rewriting every id on every call is what
  /// makes the whole thing self-correcting, exactly as [applyDigestPlans]
  /// documents for the digest alone.
  ///
  /// Reminders and evening slots are scheduled **non-actionable and with no
  /// payload**: their actions (`reminder.done`, `reminder.snooze`,
  /// `evening.done`) and payload `v:2` are slice 7's, and
  /// `docs/specs/notifications.md` forbids a new surface from reusing
  /// [digestDoneActionId].
  ///
  /// Throws [ArgumentError] if any of the three lists is the wrong length.
  Future<void> applyPlans(
    NotificationPlanSet plans, {
    String? actingMemberId,
  }) {
    _requireLength(plans.digest.length, digestHorizonSlots, 'digest');
    _requireLength(plans.reminders.length, reminderCeiling, 'reminders');
    _requireLength(plans.evening.length, eveningHorizonSlots, 'evening');
    return _enqueueNotificationWrite(() => _applyPlansNow(plans, actingMemberId));
  }

  Future<void> _applyPlansNow(
    NotificationPlanSet plans,
    String? actingMemberId,
  ) async {
    await ensureInitialized();
    final l10n = lookupAppLocalizations(localeResolver());
    await _writeDigestRange(plans.digest, actingMemberId, l10n);
    for (var i = 0; i < plans.reminders.length; i++) {
      final plan = plans.reminders[i];
      final id = reminderNotificationIdBase + i;
      if (plan == null) {
        await plugin.cancel(id);
      } else {
        await plugin.zonedSchedule(
          id: id,
          // The chore title verbatim: user data, never localized. This is
          // what makes an individual reminder actionable, and it is the
          // whole of AC1 (spec §11).
          title: plan.choreTitle,
          body: PlainDate.fromDateTime(plan.fireAt) == plan.dueDate
              ? l10n.reminderBodyDueToday
              : l10n.reminderBodyStillOpen,
          fireAt: plan.fireAt,
          channelId: remindersChannelId,
          channelName: l10n.notificationChannelRemindersName,
          channelDescription: l10n.notificationChannelRemindersDescription,
        );
      }
    }
    for (var k = 0; k < plans.evening.length; k++) {
      final plan = plans.evening[k];
      final id = eveningNotificationIdBase + k;
      if (plan == null) {
        await plugin.cancel(id);
      } else {
        await plugin.zonedSchedule(
          id: id,
          title: l10n.appTitle,
          body: l10n.eveningReminderBody(plan.openCount),
          fireAt: plan.fireAt,
          channelId: eveningChannelId,
          channelName: l10n.notificationChannelEveningName,
          channelDescription: l10n.notificationChannelEveningDescription,
        );
      }
    }
  }

  void _requireLength(int actual, int expected, String name) {
    if (actual != expected) {
      throw ArgumentError.value(actual, '$name.length', 'Must be $expected');
    }
  }
```

3. Extract `_applyDigestPlansNow`'s loop body into
   `Future<void> _writeDigestRange(List<DigestPlan?> plans, String?
   actingMemberId, AppLocalizations l10n)` so `applyDigestPlans` and
   `applyPlans` share one implementation of the digest range rather than two
   copies that can drift. `_applyDigestPlansNow` then becomes
   `ensureInitialized()` + `_writeDigestRange(...)`.

- [ ] **Step 4: Run, go GREEN, then INVERT twice**

Expected: all pass.

1. Change the reminder body to always use `l10n.reminderBodyDueToday`.
   **Expected RED:** *a reminder armed LATER than its due date* fails with
   `Expected: 'Still open' Actual: 'Due today'`.

Restore after each.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application test/app
git add lib/application/notification_scheduler.dart \
  test/application/notification_scheduler_test.dart
git commit -m "Add applyPlans, writing all three notification ranges in one enqueued write"
```

### Task 12: `cancelAll` replaces `cancelDigest`, and the wipe uses it (§9.2)

**Files:**
- Modify: `lib/application/notification_scheduler.dart`
- Modify: `lib/features/settings/reset_flow.dart:143-160`
- Modify: `test/application/notification_scheduler_test.dart`
- Modify: `test/features/settings/reset_flow_test.dart`

**Interfaces:**
- Consumes: `_enqueueNotificationWrite` (Task 11), the id-range constants.
- Produces: `NotificationScheduler.cancelAll()`;
  `List<int> reminderNotificationIds`, `List<int> eveningNotificationIds`.
  **`cancelDigest` is removed**, not wrapped.

- [ ] **Step 1: Write the failing tests**

Rename the `cancelDigest` group to `cancelAll` and update its four tests to
call `scheduler.cancelAll()`. Change the exact-count assertion at what is
currently line 610:

```dart
    test('cancels every id in all three ranges -- all 64 -- because a wipe '
        'that leaves per-chore reminders armed is strictly worse than the '
        'digest case G-12 fixed: a reminder NAMES a chore that no longer '
        'exists (spec docs/specs/notifications-n2.md §9.2)', () async {
      await scheduler.cancelAll();
      expect(
        plugin.cancelCallCount,
        digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
      );
      expect(
        digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
        64,
        reason: 'the whole iOS budget, spent exactly (§3.1)',
      );
    });
```

Add:

```dart
    test('ONE enqueued write, not three (D9): a wipe arriving DURING an '
        'apply must leave nothing armed in any range -- three enqueued '
        'writes would leave gaps for it to land in, and Rule D couples '
        'the ranges (spec docs/specs/notifications-n2.md §9.2)', () async {
      // MOVED HERE IN TASK 0 from Task 11, where `cancelAll` did not yet
      // exist. The version that stood in Task 11 asserted that the later
      // of two concurrent applies wins the reminder range -- that is FIFO,
      // it holds in both shapes, and the test could not fail.
      //
      // Gate the first `cancel`, which pauses `applyPlans` inside its
      // DIGEST range (the digest list here is all-null, so its first act
      // is a cancel). Then enqueue `cancelAll()` behind it. With ONE write
      // the cancel waits for all three ranges and clears everything. With
      // THREE, the reminder and evening sub-writes are only enqueued once
      // the digest sub-write completes -- i.e. BEHIND the cancel -- so
      // they arm ids the wipe has already cleared.
      final gatedPlugin = _GatedPlugin(target: _DigestCall.cancel);
      final gated = NotificationScheduler(
        plugin: gatedPlugin,
        localeResolver: () => const Locale('en'),
      );
      final reminders = List<ReminderPlan?>.filled(reminderCeiling, null);
      reminders[0] = ReminderPlan(
        fireAt: DateTime(2026, 8, 30, 18),
        occurrenceId: 'o1',
        choreId: 'c1',
        choreTitle: 'Bins',
        dueDate: PlainDate(2026, 8, 30),
      );
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[0] = EveningPlan(fireAt: DateTime(2026, 8, 30, 20), openCount: 1);

      final apply = gated.applyPlans(
        NotificationPlanSet(
          digest: List<DigestPlan?>.filled(digestHorizonSlots, null),
          reminders: reminders,
          evening: evening,
          reminderOverflowCount: 0,
        ),
      );
      // Let the apply actually reach the gate, so the wipe arrives
      // mid-apply rather than before it.
      await pumpEventQueue();
      final wipe = gated.cancelAll();
      gatedPlugin.release();
      await Future.wait([apply, wipe]);

      expect(gatedPlugin.pending, isEmpty);
    });

    test('leaves nothing armed in ANY range', () async {
      final reminders = List<ReminderPlan?>.filled(reminderCeiling, null);
      reminders[0] = ReminderPlan(
        fireAt: DateTime(2026, 8, 30, 18),
        occurrenceId: 'o1',
        choreId: 'c1',
        choreTitle: 'Bins',
        dueDate: PlainDate(2026, 8, 30),
      );
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[0] = EveningPlan(fireAt: DateTime(2026, 8, 30, 20), openCount: 1);
      await scheduler.applyPlans(
        NotificationPlanSet(
          digest: List<DigestPlan?>.filled(digestHorizonSlots, null),
          reminders: reminders,
          evening: evening,
          reminderOverflowCount: 0,
        ),
      );
      expect(plugin.pending, isNotEmpty);

      await scheduler.cancelAll();
      expect(plugin.pending, isEmpty);
    });
```

Also update the two G-12 serialization tests (`cancelDigest is serialized
against applyDigestPlans`) to call `cancelAll` and to expect the wider cancel
counts. **Do not weaken them**: they still assert that a cancel arriving
during an apply leaves nothing armed, and an apply arriving during a cancel
still ends up armed.

- [ ] **Step 2: Run and watch it go RED**

**Expected RED:** `Error: The method 'cancelAll' isn't defined`. Once
implemented but before the range widening, the count assertion fails with
`Expected: <64> Actual: <24>`.

- [ ] **Step 3: Implement**

In `lib/application/notification_scheduler.dart`, beside
`digestNotificationIds`:

```dart
/// Every notification id per-chore reminders own, in position order (spec
/// `docs/specs/notifications-n2.md` §3.1).
///
/// Derived from [reminderCeiling], never a literal range, for the same
/// reason [digestNotificationIds] is derived from `digestHorizonSlots`.
final List<int> reminderNotificationIds = List<int>.unmodifiable([
  for (var i = 0; i < reminderCeiling; i++) reminderNotificationIdBase + i,
]);

/// Every notification id the evening re-reminder horizon owns, in slot
/// order (spec `docs/specs/notifications-n2.md` §3.1).
final List<int> eveningNotificationIds = List<int>.unmodifiable([
  for (var k = 0; k < eveningHorizonSlots; k++) eveningNotificationIdBase + k,
]);
```

Replace `cancelDigest`/`_cancelDigestNow` with:

```dart
  /// Cancels every notification this app can have armed: the digest
  /// horizon, every individual reminder and every evening slot (spec
  /// `docs/specs/notifications-n2.md` §9.2).
  ///
  /// Widened from the digest-only `cancelDigest` it replaces, deliberately
  /// and without leaving a narrow wrapper behind: a wipe that leaves
  /// per-chore reminders armed is strictly worse than the digest case G-12
  /// fixed, because a reminder NAMES a chore that no longer exists.
  ///
  /// Rides the same [_notificationWriteTail] queue as [applyPlans] and
  /// [applyDigestPlans] (backlog G-12), so a cancel and an apply can never
  /// interleave their writes to the same ids. Because the queue is FIFO by
  /// arrival, a cancel issued while an apply is in flight runs after it
  /// (nothing stays armed) and an apply issued while a cancel is in flight
  /// runs after it (a legitimate post-wipe recompute still arms). See
  /// [_enqueueNotificationWrite].
  ///
  /// One consequence for the wipe path, accepted deliberately and unchanged
  /// from G-12: this may WAIT behind an in-flight apply. That path is
  /// best-effort and must never block the wipe, but it already awaited
  /// [ensureInitialized] -- i.e. a `plugin.initialize()` platform call -- so
  /// the wipe already depended on this plugin's calls returning. A timeout
  /// on the queue wait would reintroduce precisely the interleaving this
  /// fixes.
  Future<void> cancelAll() => _enqueueNotificationWrite(_cancelAllNow);

  Future<void> _cancelAllNow() async {
    // Inside the serialized body, not in front of the queue wait: an await
    // before the tail is captured would be a suspension point that
    // subverts the ordering. Same placement as _applyPlansNow's.
    await ensureInitialized();
    for (final id in [
      ...digestNotificationIds,
      ...reminderNotificationIds,
      ...eveningNotificationIds,
    ]) {
      await plugin.cancel(id);
    }
  }
```

In `lib/features/settings/reset_flow.dart`, rename `_cancelDigest` to
`_cancelNotifications`, call `cancelAll()` inside it, and update the two doc
comments (the function's own, and `confirmAndResetAppData`'s reference at line
59) to say "cancels every scheduled notification" and to name §9.2's reason.
**Keep the `on Object` catch exactly as it is** — its breadth is load-bearing
(a `LateInitializationError` from `initialize()` is an `Error`, not an
`Exception`) and the wipe must survive it.

- [ ] **Step 4: Run, go GREEN, then INVERT**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application test/app test/features/settings
```

Expected: all pass.

1. Make `_cancelAllNow` iterate `digestNotificationIds` only. **Expected
   RED at the test step:** *cancels every id in all three ranges* fails with
   `Expected: <64> Actual: <24>`, and *leaves nothing armed in ANY range*
   fails with `Expected: empty Actual: {2001: ..., 3001: ...}`. Restore.
2. Split `applyPlans` into three separate `_enqueueNotificationWrite` calls
   (one per range, each awaited in turn). **Expected RED at the test step:**
   *ONE enqueued write, not three (D9)* fails with
   `Expected: empty Actual: {2001: ..., 3001: ...}` — the reminder and
   evening sub-writes are enqueued behind the wipe and arm ids it already
   cleared. Restore. **This is the only test in the plan that discriminates
   on D9; if it does not go red, fix it before this task is done.**

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze --fatal-infos --fatal-warnings
git add lib/application/notification_scheduler.dart \
  lib/features/settings/reset_flow.dart \
  test/application/notification_scheduler_test.dart \
  test/features/settings/reset_flow_test.dart
git commit -m "Replace cancelDigest with cancelAll across all three notification ranges"
```

### Task 13: The budget guard, and the recompute moves to `applyPlans` (§3.3, §9.3, §13.2)

**Files:**
- Modify: `test/application/notification_scheduler_test.dart:162-189` (the
  budget group — the assertion is **replaced**, not deleted)
- Modify: `lib/domain/digest_planner.dart:160-175` (the doc comment that names
  the old guard)
- Modify: `lib/app/providers.dart:1290-1317` (`DigestRescheduleController
  ._recompute`) and the controller's class doc comment
- Modify: `test/app/digest_reschedule_test.dart`

**Interfaces:**
- Consumes: `applyPlans` (Task 11), `buildNotificationPlans` (Task 9),
  `ReminderSnoozeRepository.activeSnoozes`/`collectGarbage` (Task 3).
- Produces: nothing new; this is the wiring task.

- [ ] **Step 1: Replace the budget guard**

In `test/application/notification_scheduler_test.dart`, replace the
`the digest leaves at least 32 of iOS's 64 pending slots` test with:

```dart
    test('the three ranges spend at most the 64 ids iOS allows, computed '
        'from the constants rather than from literals (spec '
        'docs/specs/notifications-n2.md §3.3)', () {
      // REPLACES `digestHorizonSlots <= 32`, deliberately and not by
      // deletion. That guard's job was to make N2 renegotiate the split
      // explicitly rather than let the digest eat it; N2 IS that
      // renegotiation, and deleting the guard instead of replacing it would
      // leave the 64 undefended for the first time since N1.
      //
      // The total is now EXACTLY 64 and there is no slack left. Anything
      // new must take ids from one of these three ranges, by amending
      // §3.1's table.
      expect(
        digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
        lessThanOrEqualTo(64),
        reason: "iOS caps an app at 64 pending notifications, and all "
            'three ranges are now spent against it',
      );
    });

    test('the three id ranges are pairwise disjoint -- the bases are '
        'deliberately far apart (1001/2001/3001) so an off-by-one inside '
        'one range cannot silently land in another', () {
      final ranges = {
        'digest': digestNotificationIds.toSet(),
        'reminders': reminderNotificationIds.toSet(),
        'evening': eveningNotificationIds.toSet(),
      };
      for (final a in ranges.entries) {
        for (final b in ranges.entries) {
          if (a.key == b.key) {
            continue;
          }
          expect(
            a.value.intersection(b.value),
            isEmpty,
            reason: '${a.key} and ${b.key} overlap',
          );
        }
      }
      // ...and nothing is double-counted in the sum above.
      expect(
        ranges.values.expand((ids) => ids).toSet(),
        hasLength(digestHorizonSlots + reminderCeiling + eveningHorizonSlots),
      );
    });

    test('reminder and evening ids are exactly consecutive from their '
        'bases', () {
      expect(reminderNotificationIds, [
        for (var i = 0; i < reminderCeiling; i++)
          reminderNotificationIdBase + i,
      ]);
      expect(eveningNotificationIds, [
        for (var k = 0; k < eveningHorizonSlots; k++)
          eveningNotificationIdBase + k,
      ]);
    });
```

Update `lib/domain/digest_planner.dart`'s `digestHorizonSlots` doc comment:
the paragraph currently claiming the test "asserts `digestHorizonSlots <= 32`"
is now false. Replace that sentence with a pointer to the three-way split and
to §3.1/§3.3, and say the total is now exactly 64 with no slack.

**On what these two guards can and cannot do:** they are characterization
guards, and their red is produced by moving a constant, not by a logic bug.
That is their whole job. Confirm both are live rather than vacuous:

- [ ] **Step 2: Run, then INVERT the guards**

```bash
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= \
  test/application/notification_scheduler_test.dart
```

Expected: pass.

1. Set `digestDailyHorizonDays = 25` in `lib/domain/digest_planner.dart`.
   **Expected RED:** the sum guard fails with
   `Expected: a value less than or equal to <64> Actual: <75>`. Restore.
2. Set `eveningNotificationIdBase = 1010`. **Expected RED:** the disjointness
   test fails with `digest and evening overlap`, and the set-cardinality
   assertion fails. Restore.

If either inversion does NOT go red, the guard is computed from a literal
somewhere and must be fixed before proceeding.

- [ ] **Step 3: Move the recompute onto `applyPlans`**

In `lib/app/providers.dart`, add a `reminderSnoozeRepositoryProvider`
alongside the existing repository providers (follow the shape of whichever
repository provider sits nearest — read that region rather than inventing a
shape), then rewrite `DigestRescheduleController._recompute`'s tail:

```dart
    final actingMemberId = _ref.read(actingMemberProvider)?.id;
    final snoozeRepository = _ref.read(reminderSnoozeRepositoryProvider);
    // Garbage-collect first, so the plan pass never reads a snooze whose
    // occurrence is gone or whose moment has passed (spec
    // `docs/specs/notifications-n2.md` §4.2). Cheap, and it means the table
    // never grows.
    await snoozeRepository.collectGarbage(
      pendingOccurrenceIds: {
        for (final row in pending) row.occurrence.id,
      },
      nowUtc: DateTime.now().toUtc(),
    );
    await scheduler.applyPlans(
      buildNotificationPlans(
        now: _ref.read(clockProvider).now(),
        settings: settings,
        pending: pending,
        recipientMemberId: actingMemberId,
        snoozedUntilByOccurrenceId: await snoozeRepository.activeSnoozes(),
      ),
      // Carried into each actionable slot's payload so the background
      // isolate never has to re-derive it -- see
      // `DigestActionPayload.actingMemberId`.
      actingMemberId: actingMemberId,
    );
```

Update the controller's class doc comment: it now rebuilds "the whole
notification plan (`buildNotificationPlans`)" and pushes all three ranges at
once, and `reminder_snoozes` plus the new `settings` columns join the mutation
set that triggers it (§9.3 — `settingsProvider` already covers the columns
because it watches the whole row; a snooze write reaches it via the explicit
`triggerRecompute` the slice-7 action handler will add, and until then only
through the ordinary triggers).

- [ ] **Step 4: Add the one-write-per-recompute test**

In `test/app/digest_reschedule_test.dart`, add:

```dart
  testWidgets(
    'a recompute that changes BOTH reminders and the digest costs exactly '
    'ONE apply -- D9: two writes with a gap between them is a window in '
    'which a chore is announced twice or not at all',
    (tester) async {
      // (build the container the way this file's existing tests do, create
      // two chores through `choreServiceProvider`, then give one of them a
      // reminder via
      // `container.read(choreRepositoryProvider).updateChore(id,
      // reminderMinutes: const Value(1080))` -- CORRECTED IN TASK 0:
      // `ChoreService.createChore` has no `reminderMinutes` parameter and
      // adding one is slice 4's job, so the repository is the right seam
      // here. Then:)
      await tester.pump(digestRescheduleDebounce);

      // One apply writes every id exactly once: schedules plus cancels.
      final touched = <int>[];
      for (final call in plugin.scheduledCalls) {
        touched.add(call.id);
      }
      expect(
        plugin.scheduledCalls.length + plugin.cancelCallCount,
        digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
        reason: 'exactly one write over all three ranges; two applies '
            'would be twice this',
      );
      expect(touched.toSet(), hasLength(touched.length),
          reason: 'no id is scheduled twice in one apply');
    },
  );
```

and verify the existing cost bounds still hold. **They are expected to pass
unchanged** — with no chore carrying `reminder_minutes`, the 40 new entries
are all null, so they produce `cancel` calls and not `zonedSchedule` calls, and
every existing assertion in that file is on `scheduledCalls` or on
`plugin.pending`. Do not "fix" any of them pre-emptively; run them and only
adjust one if it actually fails, and say in the commit message which and why.

- [ ] **Step 5: Run the whole suite**

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
```

Expected: green. Pay attention to `test/app/day_change_catchup_test.dart:286`
(`cancelCallCount >= cancelCountBefore + digestHorizonSlots`) and
`test/app/digest_reschedule_test.dart:439` (`scheduledCalls.length <= 2 *
digestHorizonSlots`) — both are bounds the 40 extra cancels cannot break, but
they are the two most likely to surprise.

- [ ] **Step 6: INVERT the wiring**

Change `_recompute` back to `applyDigestPlans(buildDigestPlans(...))`.
**Expected RED at the test step:** the new one-write test fails with
`Expected: <64> Actual: <24>` — the reminder and evening ranges are never
touched, so an id armed by a previous build would stay armed forever.
Restore.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Replace the digest budget guard with the three-way split and move the recompute to applyPlans"
```

**Slice 3 is complete.** All three ranges are written in one serialized write,
the wipe clears all 64, the budget is defended by a guard computed from
constants — and a user sees no difference.

---

## Self-review

**Spec coverage.** §3.1 constants → Task 5. §3.2 ceiling and overflow →
Task 6. §3.3 enforcement point → Task 13. §2.2 scoping → Tasks 6, 8. §2.3
arming → Task 6. §2.4 Rule D → Task 7. §2.5 monotonicity → Task 7. §5 evening
→ Task 8. §6 quiet hours → Tasks 4, 5. §8.1/8.2/8.3/8.4 schema → Tasks 1–3.
§9.1 one pass → Task 9. §9.2 one write → Tasks 11, 12. §9.3 channels →
Task 10 (Android channels only; iOS categories belong to slice 7 with the
actions they carry — recorded in Interpretation note 7). §0.1 partition →
Task 9. §13.1 pure tests → Tasks 5–9. §13.2 scheduler/data tests → Tasks 1–3,
10–13, **except** the four items that belong to later slices by §14: the
snooze write path and payload `v:2` (slice 7), and the chore-form/settings
widget tests (slices 4–6). §4.2's cascade and GC → Task 3.

**Deliberately out of scope, and why:** §4.3's Snooze action, §10's payload
and isolate work, §11's settings/chore-form copy, §12's UI and semantic ids,
§13.3's hand checks. All are slices 4–7.

**Type consistency.** `ReminderPlan` is defined once (Task 6) and used by
Tasks 8, 9, 11, 12 with the same five fields. `ReminderPlanResult.armed/
overflowCount` (Task 6) feeds `NotificationPlanSet.reminders/
reminderOverflowCount` (Task 9), consumed by `applyPlans` (Task 11).
`EveningPlan` (Task 8) is used by Tasks 9, 11, 12. `armedReminderDates`
(Task 7) is built in Task 9. `zonedSchedule`'s `channelId` (Task 10) is passed
by Tasks 10 and 11. `activeSnoozes` (Task 3) feeds
`snoozedUntilByOccurrenceId` (Tasks 6, 9, 13).

**Known sharp edges for the implementer.**

1. Every migration test that rewinds below 13 needs **three** new collateral
   drops (Tasks 1, 2, 3). Missing one shows up as a duplicate-column or
   already-exists error in an unrelated test, not in the one you edited.
2. `ScheduledCall` gaining `channelId` (Task 10) touches every test that reads
   `plugin.scheduledCalls` — additively, but run `test/app` as well as
   `test/application`.
3. `ProjectedOccurrence` gaining two required fields (Task 6) is a compile
   break by design; there are exactly three construction sites in the tree
   (`digest_plan_builder.dart`, `digest_projection_test.dart`, and the new
   `reminder_planner_test.dart`).
4. `applyDigestPlans` deliberately does **not** apply Rule D. If a future
   reviewer calls that a bug, the answer is Interpretation note 6 and §10.1.
