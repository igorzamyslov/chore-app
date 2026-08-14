# Digest Horizon Ceiling (A-1b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the daily digest going silent after 8 unopened days. Extend the
armed horizon from 7 consecutive days to 24 slots spanning ~12 weeks —
14 consecutive daily slots followed by 10 weekly slots — while keeping every
slot a genuine one-shot `zonedSchedule` with its own projected counts and its
own per-day silence decision.

**Architecture:** No new mechanism, no new dependency, no new platform
capability, no new permission or manifest entry. `digestSlots` in
`lib/domain/digest_planner.dart` — today a flat `horizonDays`-long run of
consecutive calendar days — grows a second segment: `digestDailyHorizonDays`
consecutive days, then `digestWeeklyHorizonSlots` slots at 7-day spacing.
Everything downstream (`buildDigestPlans`, `applyDigestPlans`,
`digestNotificationIds`, `cancelDigest`, the pre-prompt banner) already
derives its size from the one constant, so it follows automatically once the
constant is renamed to reflect that the unit is no longer "days".

**Tech Stack:** Flutter 3.44.8 / Dart SDK `^3.12.2`, `flutter_riverpod ^2.6.1`,
drift + SQLite, `flutter_local_notifications ^22.1.0`, `timezone ^0.11.1`,
`package:clock`, gen_l10n.

**Source ticket:** backlog `A-1b` (`docs/backlog.md`), from
`docs/handover-2026-08-14-planning.md` §3.1.
**Specs touched:** `docs/specs/notifications.md` (binding — Task 5 amends it).

---

## Global Constraints

- **Do not edit `docs/backlog.md` or anything under `docs/feedback/`.** Other
  agents work in those files concurrently. `docs/specs/notifications.md` is
  yours (Task 5). Report A-1b as closable in the final summary instead of
  editing the row.
- **Run every test as**
  `env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <path>`
  — exactly as `lefthook.yml:42` does. Without the two dart-defines six
  unrelated tests fail and read as regressions. The `env -u` prefix keeps git
  hooks/worktrees from poisoning the environment. Do not run more than 2
  concurrent `flutter test` processes.
- **This plan adds no user-visible strings and no widgets.** The weekly tail
  slots reuse the existing `notificationDigestDueOnly` /
  `notificationDigestOverdueOnly` / `notificationDigestBoth` bodies with their
  own projected counts. If you find yourself editing `lib/l10n/app_en.arb`,
  you have gone off-plan. (For reference if that ever changes: template
  `app_en.arb` with `@`-descriptions **and** `app_de.arb` in informal du-form,
  "Gerät" never "Handy"; generated `app_localizations*.dart` are committed.)
- **Do not hand-roll a widget test.** No task here needs one, but if you reach
  for a `ProviderScope` pump: use `testChoreApp` / `testFreshChoreApp` from
  `test/test_utils/pump_app.dart` and `find.bySemanticsIdentifier`. A
  hand-rolled pump that closes the database in `tearDown` **hangs** rather
  than fails (flutter_test's pending-Timer leak check runs before tear-downs,
  so drift's stream-cleanup timer never drains), which hangs the whole suite
  and therefore the pre-commit hook. The container-level tests in
  `test/app/digest_reschedule_test.dart` are the reference pattern for this
  plan's integration-shaped tests — copy their `_awaitBootstrap` /
  `_disposeAndClose` discipline, do not invent a new one.
- `semantic()` is `Widget semantic(String id, {required Widget child})` —
  NAMED child. Positional will not compile. (Not needed by this plan.)
- Strict lints: `very_good_analysis` with `--fatal-infos`. Every public member
  needs a doc comment — including every new top-level constant and every new
  named parameter's behaviour in the enclosing function's doc.
- `lib/domain/` is `dart:core`-only by convention (see the headers of
  `digest_planner.dart`, `digest_projection.dart`, `plain_date.dart`). Add no
  imports there.
- TDD, one commit per task: write the failing test → run it → confirm it fails
  **for the stated reason** → implement → run → commit.
- Never add `Co-Authored-By:` or any co-author trailer to commit messages.
- Verify before asserting. Every codebase claim below was checked against
  source at `b6e9aa0`; if you find one that is wrong, say so rather than
  working around it.

---

## Analysis (why this design)

### 1. Verifying the handover's accuracy argument

The handover's §3.1 claims horizon length buys no accuracy, because the
projection assumes the local DB does not change and while the app is closed it
does not. **The mechanism half of that claim holds. The absolute form of it
("day 28 is exactly as accurate as day 8") is slightly overstated.** Both
verified:

**Holds — the local DB really is frozen while the app is closed.** Every
recompute trigger requires a running app: `DigestRescheduleController` listens
to `bootstrapProvider`, `pendingOccurrencesProvider`, `settingsProvider`,
`actingMemberProvider` and is externally poked by `main.dart`'s resume
observer (`lib/app/providers.dart:864-1029`); `CatchUpController`'s day-change
timer is an in-process `Timer` (`:1097-1167`); the sync engine's pull is
likewise resume-driven. `pubspec.yaml` has **no** `workmanager`,
`background_fetch`, `firebase_*` or any background-execution package, and
`android/app/src/main/AndroidManifest.xml` declares only `POST_NOTIFICATIONS`,
`RECEIVE_BOOT_COMPLETED` (for the plugin's own boot receiver) and `INTERNET`.
Nothing writes the local database with the app closed. So
`buildDigestPlans`' inputs are frozen and `projectDigestCounts` is a
deterministic function of `(frozen inputs, date)`. Its correctness does not
decay with distance.

**Overstated — for a linked household, expected accuracy does decay, just not
because of the horizon.** Another device can complete or add a chore; the
probability that it has done so grows with elapsed time. The handover is right
that the horizon is not the *cause* and that the same staleness exists at day
2, but "exactly as accurate" is not literally true. It does not change the
conclusion, for two reasons worth writing down:

- The comparison at day 8 is not *stale count vs. correct count*. It is
  **stale count vs. no notification at all**. A possibly-stale count is
  strictly more informative than silence.
- The dangerous direction is under-reporting to zero (another device added
  work, we silence that day). That failure already exists at day 2 and is not
  made worse in kind by a longer horizon.

**And the counts cannot run away.** A chore only ever has one pending
occurrence (`lib/domain/digest_projection.dart:22-24`), and
`projectedDueDateOn` rolls a schedule-anchored one forward rather than
replaying the series. So a daily chore left undone for 80 days contributes
exactly 1 to the day-80 counts, not 80. There is no "247 overdue chores" body
at the far end of a long horizon.

**Corollary: `digestHorizonDays`' doc comment is indeed not load-bearing.**
"Seven is comfortably inside iOS's 64-pending-notification cap" is true of 7
and equally true of 24. Task 5 rewrites it to say what the number actually
trades off.

### 2. The new load-bearing finding: the silence decision is monotone

This is what makes a *sparse* long tail safe, and it is not in the handover.

While the DB is frozen, an occurrence contributes to `dueCount + overdueCount`
at date `D` iff its projected due date is `<= D`. For a one-off or
completion-anchored occurrence the projected date is constant
(`digest_projection.dart:99-111`). For a schedule-anchored one it is
`latestScheduledOnOrBefore(..., notAfter: D)`, which is by construction `<= D`
and non-decreasing in `D`, falling back to the unchanged `dueDate` when no
slot has come due yet. Recipient scoping (`digest_projection.dart:132-138`) is
date-independent. Therefore:

> **Once a date is non-silent, every later date is non-silent.** The set of
> non-silent dates is an up-set `[D*, ∞)`.

**Read the consequence off that sentence directly, without re-deriving the
proof: a silent→non-silent transition is a one-way door.** There is no
"work appeared and then went away" while the app is closed, because nothing
can complete or delete an occurrence with no app running. So sparse sampling
**cannot skip a transition permanently — it can only postpone detecting
it.** If work appears on a day the tail does not sample, the very next
sampled slot is still non-silent, and its counts already include everything
the skipped days would have reported. Nothing is lost; it is only reported
later.

Two consequences the design leans on:

1. **A sparse tail loses *cadence*, never *coverage*.** The cost is bounded
   by exactly one sampling interval of delay on the first notification after
   work appears — see OPD-2, where that cost is weighed. In the daily
   segment the interval is one day, so this never applies before day 14.
2. Any long-tail slot that the projection says is silent is genuinely silent,
   so the spec's "no notification when nothing is due and nothing overdue"
   rule survives intact at every distance.

Task 2 pins this as a guard test, because the tail's safety now depends on it.

### 3. Approaches considered

| Approach | What it buys | Verdict |
|---|---|---|
| **1. Raise `digestHorizonDays` to N consecutive days** | N days of coverage for N ids | **Partially adopted.** Cheapest possible change, but coverage grows 1:1 with the iOS pending budget. 28 ids buys only 28 days. |
| **2. A repeating backstop via `matchDateTimeComponents`** | One slot, unlimited horizon | **Rejected — see below. The handover's framing of this option does not survive contact with the plugin source.** |
| **2′. A sparse tail of genuine one-shots** | ~12 weeks for 24 ids, silence rule intact, no new API | **Chosen**, together with option 1's raise for the near term. |
| **3. Server-driven push (FCM/APNs)** | Correct for a synced household | Out of scope. It cannot *replace* the local horizon (never-signed-in users are the local-first premise), it needs a device-token table, a scheduled function and a new platform capability, and it is already tracked as N3/G-6. A project, not a fix. |
| **4. Background execution (`WorkManager` / `BGTaskScheduler`)** | Re-arm while closed | Rejected, per the handover. iOS `BGAppRefreshTask` is opportunistic and fires least often for users who rarely open the app — exactly the failing population. Also a new capability to verify on a release artifact. |

#### Why option 2 is rejected — verified against the plugin source

> **Do not re-propose this.** `docs/handover-2026-08-14-planning.md` §3.1
> recommends it in writing, so a future reader will arrive here already
> persuaded. The section below is the reason it was rejected, with the
> file:line citations needed to re-check it. **It is a correctness bug, not a
> trade-off**: the handover assumes a repeating trigger can be *placed* at the
> end of the horizon, and neither platform lets you do that.

The handover argues the P0 plan rejected `matchDateTimeComponents` for the
digest because it freezes the body, and that a count-free body
("Open Famdo to see this week's chores") cannot go stale, so the objection
does not transfer. **That answers the freshness half of the objection and
leaves the silence half untouched** — and the silence half is the one the P0
plan actually raised against this exact hybrid
(`docs/plans/2026-08-08-daily-digest-scheduling.md:106`, option 4: "Inherits
option 2's fatal flaw (the backstop fires on silent days)"). Three things were
checked in `flutter_local_notifications-22.1.0`:

- **You cannot position a repeating trigger's first fire at the end of the
  horizon.** Android's `getNextFireDateMatchingDateTimeComponents`
  (`android/.../FlutterLocalNotificationsPlugin.java:1347-1387`) discards the
  scheduled date's calendar date entirely: it starts from *today*, copies only
  hour/minute/second, and walks forward to the next matching weekday. iOS's
  `buildUserNotificationCalendarTrigger`
  (`ios/.../FlutterLocalNotificationsPlugin.m:812-874`) builds a
  `UNCalendarNotificationTrigger` from `NSCalendarUnitWeekday | Hour | Minute
  | Second` with `repeats:YES` — year/month/day are dropped. So a weekly
  backstop armed today first fires **within 7 days, inside the horizon**, on a
  day the horizon may have deliberately silenced, and (worse) alongside that
  day's own digest if the times match.
- **`validateDateIsInTheFuture` is skipped entirely when
  `matchDateTimeComponents != null`** (`lib/src/helpers.dart:7-23`), which
  confirms the scheduled date is treated as a template, not a start.
- **It needs a named `Location`.** Both platforms resolve the repeat in
  `timeZoneName`. The adapter deliberately passes `tz.UTC`
  (`lib/application/notification_scheduler.dart:148-162`) to avoid the
  `flutter_timezone` dependency and `initializeTimeZones()`. A UTC-anchored
  weekly repeat drifts an hour across every DST transition and can land on the
  wrong local weekday for digest times near midnight.

The monotonicity result of §2 does give a provably silence-safe formulation
(arm the backstop only when **slot 0** is non-silent, so every later day is
non-silent too). But that fixes only the silence half. It still leaves the
**duplicate**: a repeating trigger whose first fire lands inside the horizon
posts a second notification alongside that day's own digest, every morning,
for as long as it is armed. Plus the DST drift and a permanently-armed
notification that no local recompute can correct once the counts diverge.
Option 2′ has none of those and costs only notification ids.

#### The chosen shape

`digestSlots` returns `digestDailyHorizonDays` consecutive daily slots
(offsets `0 .. dailyDays-1`) followed by `digestWeeklyHorizonSlots` slots at
7-day spacing (offsets `(dailyDays - 1) + 7*(j+1)`). With **14 daily + 10
weekly = 24 slots**, the last slot is at offset 83 — the digest survives ~12
weeks unopened instead of 7 days, a 12× improvement.

Every slot stays a one-shot `zonedSchedule` with its own
`projectDigestCounts` result and its own `planDigestSlot` silence decision.
Nothing about the plugin seam, the ids, the serialization in
`applyDigestPlans`, or the body copy changes shape.

### 4. The two budgets this spends

**iOS pending-notification slots.** 24 of 64, leaving 40 for the unbuilt
per-chore reminders (backlog G-6 / F16) — which the handover correctly names
as the real competitor, not 64. Today's 7 leaves 57. A household with 20
reminder-enabled chores needs ~20 pending, so 40 is comfortable headroom. Task
3 encodes this as an assertion so a future raise cannot silently eat the
reminder budget, and **Task 6 writes the split into
`docs/specs/notifications.md`** so N2's planner finds it there rather than
here. Note this budget is currently hypothetical in one sense: releases are
Android-only (`docs/backlog.md` A-3b: iOS "only matters if a release ever
ships iOS"). Android imposes no per-app cap on inexact alarms.

**Work per recompute.** Verified numbers, not the ticket's estimates:

- **CORRECTION — the digest debounce is 500ms, not ~2s.** It is
  `digestRescheduleDebounce = Duration(milliseconds: 500)`
  (`lib/app/providers.dart:834`). The ~2s figure that circulates in the older
  docs and in the A-1b ticket is a **different constant**:
  `SyncEngine.pushDebounce = Duration(seconds: 2)`
  (`lib/application/sync_engine.dart:224`), which debounces the sync *push*,
  not the digest recompute. The two are routinely conflated; when reasoning
  about the cost of a larger horizon, 500ms is the number that applies.
- A recompute becomes 24 sequential platform-channel calls instead of 7. Each
  is one channel round trip plus one `AlarmManager.setAndAllowWhileIdle`
  (inexact — `AndroidScheduleMode.inexactAllowWhileIdle`, deliberate, do not
  "upgrade" it).
- Bursts are already bounded twice over: the 500ms debounce collapses a burst
  into one firing, and `DigestRescheduleController`'s depth-1
  `_inFlightRecompute`/`_recomputeQueued` queue collapses everything arriving
  during a run into **one** trailing re-run. Worst case per burst is therefore
  2 applies = 48 calls, not 24-per-mutation. Task 4 pins that bound.
- Projection cost grows too, and is worth the arithmetic because it is the
  one place a long horizon is not free. `latestScheduledOnOrBefore` walks one
  step per series slot between the occurrence's due date and the queried date
  (`lib/domain/recurrence/recurrence_engine.dart:165-182`). Summed over 24
  slots with offsets `0..13, 20, 27 … 83`, the total offset sum is ~600, so a
  daily schedule-anchored occurrence costs ~600 `nextScheduledOnOrAfter` steps
  per recompute; 50 such occurrences ≈ 30k steps of pure `PlainDate`
  arithmetic. That is single-digit milliseconds and needs no optimisation —
  but it is why this plan stops at 24 slots rather than, say, 60.

**No mitigation beyond what exists is warranted.** Do not add a
diff-against-last-applied cache: rewriting every id on every apply is
precisely what makes the horizon self-correcting
(`notification_scheduler.dart:241-244`), and a cache would reintroduce the
bookkeeping that design exists to avoid.

### 5. What this plan deliberately does NOT close

- **The slot-relative id scheme stays.** Ids are `base + k` where k is the
  offset from the *next* slot, so id 1001 means Monday's slot today and
  Tuesday's slot tomorrow (handover §4). A process kill mid-apply can leave
  one stale armed notification. Growing 7 → 24 ids widens that window
  proportionally. A date-derived mapping would make a partial apply idempotent
  but needs a cancel-ring larger than the horizon (more platform calls, not
  fewer) and is a separate ticket. The exposure is bounded by the
  serialization already in `applyDigestPlans`; worst case remains one
  duplicate morning notification.
- **`cancelDigest()` remains unserialized against `applyDigestPlans`**
  (handover §4). No concurrent caller exists today; unchanged by this plan.
- **Cross-device staleness is not addressed.** That is option 3, N3.
- **The digest still goes silent eventually** — after ~12 weeks instead of 8
  days. See Open product decision 3.
- **E2E covers none of this.** The suite runs fully offline with empty
  Supabase dart-defines (`NoopAuthGateway`) and cannot verify fire times; the
  spec already records that actual fire-time verification is not E2E-testable
  in reasonable time. There is no `integration_test/` target in this repo
  (verified: the directory does not exist), so the `pendingNotificationRequests()`
  integration test the spec contemplates has never been built. Creating it is
  out of scope. Everything here is covered by unit and container-level tests
  against `FakeDigestNotificationPlugin`.

---

## Product decisions — ALL RESOLVED 2026-08-14

*Genuine product judgments, underivable from the code, and — per the ticket's
standing constraint — not measurable, because the app deliberately ships no
telemetry. **All three were accepted as recommended on 2026-08-14. The
options are retained below as the record of what was weighed, not as open
questions.** Execute with the accepted values; no decision is outstanding.*

### OPD-1 — How many notification slots does the digest get, and how are they spread? — **ACCEPTED: (a)**

The digest and the unbuilt per-chore reminders (backlog G-6 / F16) share
iOS's 64-pending cap.

- **(a) 14 daily + 10 weekly = 24 slots, reaching day 83.** ~12 weeks of
  coverage; 40 iOS slots left for reminders.
- **(b) 7 daily + 8 weekly = 15 slots, reaching day 62.** Keeps today's daily
  cadence unchanged and still buys 9× the reach; 49 slots left.
- **(c) 28 daily = 28 slots, reaching day 27.** No tail at all — option 1
  alone. Simplest, but 4 weeks for more ids than (a) spends.

**DECIDED — (a), accepted 2026-08-14.** Two weeks of daily coverage matches a
plausible holiday, and the weekly tail is where the reach actually comes from
— the same budget that buys 27 days flat buys 83 days segmented. (c) is worse
on every axis except a few lines of code. Twenty-four of 64 leaves **forty**
for per-chore reminders, which is the number that actually matters and is
comfortable for a family-scale chore list.

**Values:** `digestDailyHorizonDays = 14`, `digestWeeklyHorizonSlots = 10`.

**Obligation attached to this decision:** that 40-slot reserve is currently a
fact only this plan knows. **Task 6 writes it into
`docs/specs/notifications.md`** so whoever plans N2 / per-chore reminders
(backlog G-6 / F16) finds their budget without reading this plan.

### OPD-2 — After the daily stretch ends, how often should a disengaged user hear from the app? — **ACCEPTED: (a)**

The tail's spacing is a nagging-vs-re-engagement judgment, not a technical
one. Coverage is unaffected by the choice (§2 monotonicity: a sparser tail
loses cadence, never coverage — the next sampled day still reports everything
the skipped days would have).

- **(a) Weekly.** One nudge per week, ten of them.
- **(b) Every 3 days.** Denser, reaches only day ~44 for the same 10 slots.
- **(c) Every 14 days.** Reaches day ~153 for the same 10 slots; a very quiet
  presence.

**DECIDED — (a) weekly, accepted 2026-08-14.** Someone who has not opened the
app in two weeks is not helped by a daily reminder they are already ignoring,
and a weekly rhythm is the one people already recognise from every other
"here's what's waiting" product. It also aligns each tail slot to the same
weekday, which reads as deliberate rather than arbitrary.

**The cost, stated plainly:** in the tail, the first notification after work
appears can be delayed by up to one sampling interval — seven days. Per §2
that is a *postponement*, never a miss: the next sampled slot still reports
everything, because work cannot disappear while the app is closed. For
someone who has not opened the app in two weeks, seven days of delay on a
re-engagement nudge is an acceptable cost. **For someone at day 3 it never
applies at all** — the first 14 slots are consecutive days, so nothing inside
the daily segment is ever delayed.

**Value:** the tail step is 7 days, `digestHorizonTailStepDays`, a named
constant so a future revisit is a one-line change.

### OPD-3 — Should the digest ever be truly unlimited, or is a finite reach the right answer? — **ACCEPTED: (c)**

Option 2′ has a far edge: after the last slot, silence, forever, until the app
is opened. Only a repeating OS alarm removes that edge, at the costs verified
in §3.

- **(a) Finite reach (~12 weeks), accept the far edge.**
- **(b) Add a weekly repeating backstop on top**, armed only when slot 0 is
  non-silent (the provably silence-safe formulation from §2), offset from the
  digest time so it never collides with a horizon slot on the same morning.
  Costs: a `flutter_timezone` dependency or an accepted ±1h DST drift, one new
  l10n string pair, a notification whose body no local recompute can ever
  correct, and — because it is an evening nudge — overlap with the "evening
  re-reminder" that `DESIGN.md` §3 and the N2 spec already own.
- **(c) Do (a) now, and let N3 server push cover the far tail** when it lands.

**DECIDED — (c), accepted 2026-08-14: finite reach now, N3 server push covers
the far tail when it lands. No repeating backstop.** A user who has not opened
the app in three months has churned; a notification is not what brings them
back.

**The deciding reason is the correctness finding in §3, not the trade-off.**
(b) is not "more reach for a small cost" — it is broken as specified. The
handover assumes the backstop can be *placed* at the end of the horizon;
neither platform allows that, so it fires inside the horizon and duplicates
the digest every morning. The count-free body answers only the freshness half
of the P0 objection. Even the silence-safe variant enabled by §2 keeps the
duplicate, the DST drift, and a permanently-armed body no local recompute can
correct. If the far edge is ever judged unacceptable, the correct follow-up is
option 3 (server push), not (b).

**Value:** no repeating backstop, no `matchDateTimeComponents`, no
`flutter_timezone`.

---

## Tasks

### Task 1 — Reshape `digestSlots` into daily + weekly segments (behaviour unchanged)

**Files:** `lib/domain/digest_planner.dart`,
`test/domain/digest_planner_test.dart`, plus the mechanical rename in
`lib/application/notification_scheduler.dart`,
`lib/application/digest_plan_builder.dart`, `lib/app/providers.dart`,
`lib/domain/digest_projection.dart` (doc comment),
`test/application/notification_scheduler_test.dart`,
`test/application/digest_plan_builder_test.dart`,
`test/app/digest_reschedule_test.dart`, `test/app/day_change_catchup_test.dart`.

**Does NOT make the fix live.** The shipped constants keep the current values,
so this task changes zero runtime behaviour. It exists so the flip in Task 3 is
one line.

**Produces:**

- `const int digestDailyHorizonDays = 7;` — number of consecutive daily slots.
- `const int digestWeeklyHorizonSlots = 0;` — number of trailing slots at
  `digestHorizonTailStepDays` spacing.
- `const int digestHorizonTailStepDays = 7;` — the tail's spacing (OPD-2).
- `const int digestHorizonSlots = digestDailyHorizonDays + digestWeeklyHorizonSlots;`
- `digestSlots({required DateTime now, required int digestMinutes, int dailyDays = digestDailyHorizonDays, int weeklySlots = digestWeeklyHorizonSlots})`.

**Consumes:** `nextDigestSlot` (unchanged).

**Requirements:**

1. **Rename `digestHorizonDays` → `digestHorizonSlots` everywhere.** The unit
   is no longer days and leaving the old name would actively mislead. The
   compiler finds every site; the complete list at `b6e9aa0` is the eight
   files above. Two of them need more than a rename:
   - `test/application/notification_scheduler_test.dart:283` asserts
     `expect(digestNotificationIds, [1001, 1002, 1003, 1004, 1005, 1006, 1007])`.
     This is the one hard-coded 7 in the suite. Replace it with an assertion
     derived from `digestHorizonSlots` — first id is `digestNotificationIdBase`,
     length is `digestHorizonSlots`, ids are consecutive — so it survives Task 3.
   - `test/domain/digest_planner_test.dart:181-190` passes `horizonDays: 0`;
     that parameter no longer exists (see requirement 3).
2. **Slot construction.** Daily slot `k` (`0 <= k < dailyDays`) is at day
   offset `k` from the first slot. Weekly slot `j` (`0 <= j < weeklySlots`) is
   at day offset `(dailyDays - 1) + digestHorizonTailStepDays * (j + 1)`. So
   the segments join with exactly one tail step between the last daily slot and
   the first weekly one. Keep building every slot from calendar components
   (`DateTime(first.year, first.month, first.day + offset, hour, minute)`) with
   `hour`/`minute` re-derived from `digestMinutes` — the DST rationale in the
   existing doc comment applies unchanged to tail slots and must be preserved.
   The returned list must be in ascending `fireAt` order.
3. **Validation.** Replace the `horizonDays < 1` check with: `dailyDays < 1`
   throws `ArgumentError`, `weeklySlots < 0` throws `ArgumentError`. Keep the
   existing `_validateDigestMinutes` call and its behaviour.
4. **Doc comments** on all four new constants and on `digestSlots`' two new
   parameters (`--fatal-infos` will reject a missing one). `digestHorizonSlots`'
   doc replaces the current "comfortably inside iOS's 64-pending-notification
   cap" rationale — Task 5 owns the final wording; a placeholder that does not
   assert anything unverified is fine here.

**Tests** (`test/domain/digest_planner_test.dart`, `digestSlots` group):

- Update `returns digestHorizonDays consecutive slots by default` and the two
  sibling tests that assert `slots.last` — with the shipped constants at 7/0
  their current expectations (`hasLength(7)`, `slots.last` at day+6) are still
  correct, so these should keep passing unchanged apart from the rename.
- Update the `rejects a horizon below one day` test to pass `dailyDays: 0`,
  and add one for `weeklySlots: -1`.
- **New:** with explicit `dailyDays: 3, weeklySlots: 2`, assert exactly 5
  slots at day offsets `0, 1, 2, 9, 16` from `now`'s first slot. Pass the
  parameters explicitly rather than relying on the shipped constants, so this
  test does not have to change again in Task 3.
- **New:** with `dailyDays: 3, weeklySlots: 2` starting 2026-03-27 (European
  spring-forward is 2026-03-29), assert every slot still has `hour == 8,
  minute == 0`. This is the tail's own DST proof; the existing DST test only
  covers daily slots.
- **New:** with `weeklySlots: 0`, assert the result is identical to a plain
  daily run — the "the tail is genuinely optional" guard that makes this task
  provably behaviour-preserving.

**Expected RED:** the two new `dailyDays:`/`weeklySlots:` tests fail to
compile — `No named parameter with the name 'dailyDays'` — before the
implementation lands. That is the signal; a *passing* run at this point means
you edited the implementation first. The renamed constant will also produce
`Undefined name 'digestHorizonDays'` across the eight files until the rename
is complete.

**Verify:** the full suite, not just this file — the rename touches five test
files.

```
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
git commit -m "Give digestSlots a daily segment and an optional weekly tail"
```

---

### Task 2 — Guard test: the digest's silence decision is monotone

**Files:** `test/domain/digest_projection_test.dart` only. **No production
code changes.**

**Does NOT make the fix live.**

**Why this task exists:** §2 above proves that once a date is non-silent every
later date is non-silent, and the sparse tail's safety rests entirely on that
property. It holds today by accident of how `projectedDueDateOn` is written.
Pinning it makes a future change to the projection fail loudly here rather
than silently turning the tail into a coverage hole.

**This is a characterization test, not a TDD red-green cycle.** It passes
against unchanged code. Do not go hunting for a red.

**Requirements:**

- Add a `group('the silence decision is monotone', ...)` to the existing file,
  reusing its `_occurrence(...)` helper.
- For each of: a one-off, a completion-anchored recurring chore, a
  schedule-anchored daily chore, a schedule-anchored weekly chore, and a mixed
  set of all four — walk `date` across ~120 consecutive days from a fixed
  start and assert that once `projectDigestCounts(...).isSilent` is `false` it
  is never `true` again. Cover both `recipientMemberId: null` and a set
  recipient with a mix of assigned and unassigned occurrences, since scoping
  is what would break the property if it ever became date-dependent.
- Assert the stronger form too: `dueCount + overdueCount` is non-decreasing
  across the walk. This is what guarantees a skipped week's work is still
  reported by the next sampled slot.
- The 120-day span must comfortably exceed the largest horizon this plan can
  produce under any OPD-1 option (day 83 under (a)). State that in a comment
  so a future horizon raise knows to extend the walk.

**Proving it is not vacuous** (mandatory, since there is no natural RED): once
green, temporarily invert one assertion — e.g. assert `isSilent` stays `true`
after becoming `false` — and confirm the test fails with a real comparison
failure, not a skipped body or an empty loop. Then revert the inversion. Note
in the commit message that this was done. A test that walks zero dates or
whose occurrence set is empty would pass vacuously; the assertion that at
least one date in each walk is non-silent guards against that — include it.

```
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/domain/digest_projection_test.dart
git commit -m "Pin the digest projection's monotone silence property"
```

---

### Task 3 — THE FLIP: extend the horizon to 14 daily + 10 weekly slots

**⚠️ This is the task that makes the fix live.** Tasks 1 and 2 changed no
shipping behaviour. Everything downstream of `digestHorizonSlots` — the id
list, `applyDigestPlans`' length check, `cancelDigest`, `buildDigestPlans`,
the pre-prompt banner — follows automatically from these two constants, so
this task's diff in `lib/` is two numbers.

**Files:** `lib/domain/digest_planner.dart` (two constant values),
`test/app/digest_reschedule_test.dart`,
`test/application/notification_scheduler_test.dart`,
`test/domain/digest_planner_test.dart`.

**Requirements:**

1. Set `digestDailyHorizonDays = 14` and `digestWeeklyHorizonSlots = 10` (per
   OPD-1(a) — if Igor chose (b) or (c), use those numbers; nothing else in this
   task changes).
2. **Write the new regression test first.** In
   `test/app/digest_reschedule_test.dart`, alongside the existing
   `THE REGRESSION (audit P0)` test and following its exact container setup
   (`_awaitBootstrap`, `_disposeAndClose`, `FakeDigestNotificationPlugin`,
   `Clock(() => currentTime)`): seed one daily recurring chore, let one
   recompute run, then assert
   - `plugin.pending` has `digestHorizonSlots` entries;
   - the furthest-out armed `fireAt` is at least 80 days after `now` —
     the day-8 analogue of the P0 test, and the direct statement of the
     ticket;
   - after `plugin.deliverDue(now + 60 days)` with **no** app interaction of
     any kind, at least one notification is still armed. Capture
     `plugin.scheduledCalls.length` before the pump and assert it is unchanged
     afterwards, exactly as the existing P0 test does, so the assertion cannot
     be satisfied by some other recompute quietly re-arming.
   Prefer asserting on `plugin.pending` over pumping 80 days of fake time —
   the existing P0 test already establishes that delivery does not re-arm, and
   a long pump only adds runtime.
3. **Update the existing size-coupled expectations.** These read `7` today via
   the constant and will simply follow the new value, but their *comments* say
   "digestHorizonDays plugin calls" and their reasoning must still hold at 24:
   - `test/app/digest_reschedule_test.dart:216, 280, 324, 334, 374` — all
     already derive from the constant; re-read each comment and correct any
     that now says something false.
   - `test/app/day_change_catchup_test.dart:277` — derives from the constant.
   - `test/features/chores/digest_preprompt_banner_test.dart:182` — uses
     `everyElement(isIn(digestNotificationIds))`, which follows automatically.
     **Verified: no change needed.** Confirm it still passes rather than
     assuming.
   - `test/domain/digest_planner_test.dart:139-149, 171` — `slots.last`
     expectations are absolute dates computed for a 7-day horizon and **will
     fail**. Recompute them for the new shape: with `digestMinutes: 480` and
     `now = 2026-07-24 07:00`, the first slot is 2026-07-24 08:00 and the last
     is offset 83 → 2026-10-15 08:00. Derive each expected date rather than
     copying this one.
4. **Add the budget guard**, in `test/application/notification_scheduler_test.dart`:
   assert `digestHorizonSlots <= 32`, with a `reason` naming backlog G-6/F16 —
   at least 32 of iOS's 64 pending slots must stay available for per-chore
   reminders. This is the ticket's "protect that number, not 64" instruction
   made mechanical. Also assert `digestNotificationIds.length ==
   digestHorizonSlots` and that the ids are consecutive from
   `digestNotificationIdBase`.

**Expected RED** (before the constants are flipped): the new regression test
fails on the furthest-armed-`fireAt` assertion — the armed set spans only 6
days, so the assertion reports something around `2026-01-11` against an
expected `>= 2026-03-26`. It must **not** fail with an empty `pending` map or a
null dereference; if it does, the container setup is wrong, not the horizon.
The recomputed `slots.last` expectations in `digest_planner_test.dart` will
also be red until the flip — that is expected and is the point.

**Stub check:** the "stub" here is the two constants, and they can pass every
assertion above on their own — there is no partially-implemented function in
this task.

```
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
git commit -m "Extend the digest horizon to 14 daily plus 10 weekly slots"
```

---

### Task 4 — Pin the cost of a larger horizon

**Files:** `test/app/digest_reschedule_test.dart`. **No production code
changes.**

**Does NOT make the fix live** (Task 3 did).

**Why:** the ticket asks the plan to "address battery". §4 argues no mitigation
is needed because two existing mechanisms already bound the work. That
argument is only worth as much as the tests behind it, and the existing
debounce test asserts the *lower* bound (one burst produced `digestHorizonSlots`
calls) without ever pinning an *upper* bound on applies per burst.

**Requirements:**

- Extend the existing `the burst must collapse into a single reschedule call`
  test, or add one beside it: issue five mutations inside one debounce window
  and assert `plugin.scheduledCalls.length` is **exactly**
  `digestHorizonSlots`, not merely non-empty — proving five mutations cost one
  apply, not five.
- Add a case for the depth-1 trailing queue: use the existing `_PausingPlugin`
  to hold one apply mid-loop, trigger three further recomputes while it is
  paused, release, settle, and assert the total call count is at most
  `2 * digestHorizonSlots` — i.e. the in-flight apply plus exactly one
  coalesced trailing re-run, never one per trigger. This is the bound §4
  claims; `_PausingPlugin`'s existing doc comment explains its one-shot gate.
- Add a short comment recording the arithmetic from §4 (24 calls per apply, ≤2
  applies per burst, 500ms debounce, ~30k `PlainDate` steps for the
  projection) so a future horizon raise has the numbers to hand.

**Expected RED:** write the exact-count assertions first against a
deliberately wrong expected value (e.g. `2 * digestHorizonSlots` for the
five-mutation case) and confirm the failure names the real count, so you know
the assertion is live before pinning the true bound. A test that asserts
`isNotEmpty` or `greaterThan(0)` here is vacuous and must not be committed —
that is exactly the class of never-failing assertion the handover §5 warns
about.

```
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= test/app/digest_reschedule_test.dart
git commit -m "Bound the digest recompute's work per mutation burst"
```

---

### Task 5 — Amend the binding spec and the stale doc comments

**Files:** `docs/specs/notifications.md`, `lib/domain/digest_planner.dart`,
`lib/application/notification_scheduler.dart`,
`lib/domain/digest_projection.dart`, `lib/app/providers.dart`.

**Does NOT make the fix live.** Documentation only — but the spec is binding,
and leaving it describing a 7-day horizon of ids 1001..1007 would make it
wrong about shipped behaviour.

**Requirements:**

1. **`docs/specs/notifications.md` "N1 behavior"** (lines 22-36): the horizon
   is no longer "a rolling 7-day horizon … ids 1001..1007". Restate it as
   `digestHorizonSlots` slots — `digestDailyHorizonDays` consecutive days then
   `digestWeeklyHorizonSlots` at `digestHorizonTailStepDays` spacing — ids
   `digestNotificationIdBase + k`. Keep the existing sentence about the silence
   rule being evaluated per day, and **add the monotonicity result from §2 as
   the reason a sparse tail is safe**: work never disappears while the app is
   closed, so a sampled day reports everything the skipped days would have.
   Keep and strengthen the `matchDateTimeComponents` rejection — it currently
   cites the silence rule, the frozen body and the named `Location`; add the
   verified finding that neither platform lets a repeating trigger's first fire
   be positioned past the next matching component (Android
   `getNextFireDateMatchingDateTimeComponents`, iOS
   `UNCalendarNotificationTrigger`), so a backstop cannot sit at the end of a
   horizon at all.
2. **`docs/specs/notifications.md` "Architecture" #1** (lines 66-86): update the
   quoted signature block to the new `digestSlots` signature and constants.
3. **`docs/specs/notifications.md` "Testing"**: record the new far-horizon
   regression test and the monotonicity guard alongside the existing "horizon
   regression test (required)" entry.
4. **`digest_planner.dart`'s `digestHorizonSlots` doc comment**: delete
   "Seven is comfortably inside iOS's 64-pending-notification cap" — true but,
   as §1 establishes, not the reason for the number. Replace it with what the
   number actually trades: notification ids against unopened-day coverage, with
   the budget split against per-chore reminders (backlog G-6/F16) named
   explicitly, and a pointer to this plan.
5. **`notification_scheduler.dart:15-26`**: `digestNotificationIds`' doc says
   the horizon is one id per calendar day. With a tail that is no longer true —
   it is one id per *slot*. Fix the wording; keep the "fixed and exhaustive on
   purpose" paragraph, which is still exactly right and is what keeps the
   pre-prompt banner test's `everyElement(isIn(digestNotificationIds))` honest.
6. **`digest_projection.dart:11-13`** and **`providers.dart:843-844, 1161`**
   reference `digestHorizonDays` by name in prose; update to
   `digestHorizonSlots` and check each surrounding sentence is still true.
7. Record the three resolved OPD answers (all accepted as recommended
   2026-08-14), with the chosen values, at the top of the spec's N1 section or
   in a short "Decisions" note — following the precedent of `DESIGN.md` §3's
   inline amendment note for OPD-1 of the P0 plan. The **notification-id
   budget** is deliberately NOT part of this task; Task 6 owns it, because it
   needs to be findable by someone who is not reading this section.

**Do not edit `docs/backlog.md`.** Report in the final summary that A-1b is
closable, and by which commits.

**Verify:** re-read each edited doc comment against the code beside it. This
task has no test; its acceptance criterion is that no statement in the touched
docs is falsifiable by grepping the code they describe.

```
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
git commit -m "Document the segmented digest horizon in the notifications spec"
```

---

### Task 6 — Record the notification-id budget in the spec

**Files:** `docs/specs/notifications.md`. **No production code changes.**

**Does NOT make the fix live.** Documentation — but it is a standing
obligation attached to OPD-1, not a nicety.

**Why this task exists:** the decision to spend 24 ids rests on leaving 40 for
per-chore reminders. Right now that reserve exists only in this plan's §4 and
in an `expect(digestHorizonSlots <= 32, ...)` in a test file. **Whoever plans
N2 / per-chore reminders (backlog G-6 / F16) must be able to find their budget
without reading this plan** — otherwise they will either re-derive it, or
quietly exceed it and discover the 64-cap on a device.

**Requirements:**

Add a short, clearly-titled subsection to `docs/specs/notifications.md` — a
"Notification id budget" heading under Architecture, not a parenthetical
buried in prose — stating all four of:

1. **The total.** iOS caps an app at **64 pending notifications**; Android
   imposes no equivalent per-app cap on the inexact alarms this app uses. The
   budget is therefore an iOS constraint, and it binds even though releases
   are currently Android-only (backlog A-3b).
2. **This feature's share.** The daily digest owns **24** ids —
   `digestNotificationIdBase` (1001) through 1024, i.e. `digestHorizonSlots`
   consecutive ids. State that the range is derived from the constant, not
   hard-coded, so it moves if the constant does.
3. **The reservation.** The remaining **40** are **reserved for N2 /
   per-chore reminders (backlog G-6 / F16)**, which is the feature the digest
   is actually competing with for this budget — not the raw 64. Name that
   explicitly: a plan that spends against 64 rather than 40 is spending
   someone else's budget.
4. **The enforcement point.** `test/application/notification_scheduler_test.dart`
   asserts `digestHorizonSlots <= 32` (Task 3). Say so, so a future raise of
   the horizon finds the guard rather than tripping over it, and knows that
   changing the guard means renegotiating the split.

Also add a one-line pointer to this budget from the N1 phasing bullet that
already names N2, so a reader arriving at "per-chore reminders (later, own
spec)" is routed to the number.

**Verify:** the stated 24 and 40 must agree with the shipped constants and
with the test assertion. Re-derive both from
`lib/domain/digest_planner.dart` rather than copying them from this plan — if
Igor later revisits OPD-1, this section is the thing most likely to go stale.

```
git commit -m "Record the notification id budget and the N2 reservation in the notifications spec"
```

---

### Task 7 — Whole-branch review

Per handover §7: two of the most valuable findings in the v0.5.0 work were
things no per-task review could structurally have seen. Run
`superpowers:requesting-code-review` over the **whole branch diff**, not
task-by-task, and specifically ask the reviewer to check:

- **Nothing hard-codes 7 or 1007 anywhere.** `grep -rn "1007\|horizonDays" lib
  test docs` must return only intentional historical references in
  `docs/plans/2026-08-08-*.md` (which are shipped history and must not be
  rewritten).
- **Every armed slot is still individually silence-checked.** The tail must not
  have acquired an "always schedule the last one" shortcut anywhere.
- **`applyDigestPlans`' length validation, `digestNotificationIds`,
  `cancelDigest` and `buildDigestPlans` all still agree on the same size**, and
  the pre-prompt banner arms exactly the same set as the controller.
- **The `lib/domain/` purity rule survived** — `digest_planner.dart` still
  imports nothing beyond `dart:core`.
- **No test in the branch can pass vacuously.** Every new assertion should have
  been observed failing at least once; Task 2's characterization test is the
  one exception and its inversion check is the substitute.
- **No user-visible string, widget, permission or manifest entry was added.**
  If any appeared, that is off-plan and needs justification — capability
  boundaries have to be verified on the release artifact, not a debug run.

---

## Success criteria

- [ ] An app left unopened for 60 days still has a digest armed, proven by a
      test that performs no app interaction during the gap.
- [ ] Every armed slot — daily or weekly — carries counts projected for its
      own date and is cancelled rather than scheduled when that date is silent.
- [ ] `digestHorizonSlots <= 32`, asserted, leaving at least 32 iOS pending
      slots for per-chore reminders.
- [ ] The id budget — 64 total, 24 spent, 40 reserved for N2 / per-chore
      reminders — is stated in `docs/specs/notifications.md` and findable
      without reading this plan.
- [ ] A burst of mutations still costs at most two applies, asserted.
- [ ] No new dependency, string, widget, permission or manifest entry.
- [ ] `docs/specs/notifications.md` describes the shipped horizon, and no doc
      comment claims a rationale §1 showed to be non-load-bearing.
- [ ] `flutter analyze --fatal-infos` clean; full suite green with the two
      Supabase dart-defines.
