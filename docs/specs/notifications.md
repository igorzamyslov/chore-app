# Spec: Notifications (v1 — local, digest-first)

*The retention maker/breaker. Design principle from DESIGN.md §2: digest by
default, never nag. v1 is entirely LOCAL notifications (no server, no
push) — that covers the single-device household until the sync phase.*

## Phasing

- **N1 (this spec)**: one daily digest notification + settings UI +
  permission handling.
- **N2 (later, own spec)**: per-chore opt-in reminders, notification
  actions (Done / Snooze to tomorrow), evening re-reminder. **N2 has a
  reserved notification-id budget of 40 — see "Notification id budget"
  under Architecture before planning it.**
- **N3 (sync phase)**: server-scheduled push, cross-user events.

## N1 behavior

> **Amendment 2026-08-14 (A-1b, `docs/plans/2026-08-14-digest-horizon-ceiling.md`).**
> The horizon was a flat 7 consecutive days (ids 1001..1007) and went silent
> after 8 unopened days. Three product decisions were taken and are settled
> — do not re-open them:
> - **Horizon shape:** 14 daily + 10 weekly = **24 slots, reaching day 83**.
>   Two weeks of daily cadence matches a plausible holiday, and the weekly
>   tail is where the reach comes from — the same id budget that buys 27 flat
>   days buys 83 segmented.
> - **Tail spacing: weekly** (`digestHorizonTailStepDays = 7`). Someone who
>   has not opened the app in a fortnight is not helped by a daily reminder
>   they are already ignoring. Costs up to 7 days' delay on the first
>   notification after work appears — a postponement, never a miss.
> - **Finite reach, no repeating backstop.** After the last slot the digest
>   is silent until the app is opened. N3 server push covers the far tail
>   when it lands; a `matchDateTimeComponents` backstop does not, and is
>   broken as specified (see below).

- One notification per day at a user-chosen time (default 08:00):
  title = app name, body = localized digest, e.g. '3 chores today' /
  '2 chores today · 1 overdue' / German equivalents (ICU plurals).
- **No notification at all when there is nothing due and nothing overdue**
  (silence is a feature: it keeps the signal meaningful).
- **The schedule must survive the app not being opened.** The digest is
  armed as a rolling **segmented horizon** of `digestHorizonSlots` distinct
  one-shot notifications, ids `digestNotificationIdBase + k`. The horizon is
  `digestDailyHorizonDays` consecutive daily slots followed by
  `digestWeeklyHorizonSlots` slots at `digestHorizonTailStepDays` spacing,
  so its reach in days is
  `digestDailyHorizonDays - 1 + digestHorizonTailStepDays *
  digestWeeklyHorizonSlots`. At the shipped values (14 / 10 / 7) that is
  **24 slots reaching day 83** — ids `1001..1024`, roughly twelve weeks.
  Note the unit is **slots, not days**: past the daily segment, slot `k` is
  not `k` days out.
  Every recompute rewrites ALL of them: slots with something to say are
  scheduled, slots without are cancelled — so the silence rule is evaluated
  **per slot's own date**, never once for the whole horizon. Counts for a
  future date are projected by `lib/domain/digest_projection.dart` under the
  assumption that nothing happens in between (which is exactly true when the
  app isn't opened), mirroring `catchUpOverdue`'s roll-forward rule for
  schedule-anchored chores. The digest therefore degrades only after ~12
  unopened weeks, and degrades into silence rather than into wrong counts.
- **Why a sparse tail loses no coverage.** Sampling one day in seven sounds
  like it could miss work that appears on an unsampled day. It cannot, and
  the reason is worth stating because the tail's safety rests entirely on
  it: while the app is closed nothing can complete or delete an occurrence,
  so an occurrence contributes to a date's counts iff its projected due date
  is on or before that date — a condition that, once true, stays true.
  **The set of non-silent dates is therefore an up-set: once a date is
  non-silent, every later date is too, and its counts already include
  everything the skipped days would have reported.** A sparse tail loses
  *cadence*, never *coverage*; the only cost is up to one sampling interval
  of delay on the first notification after work appears, and none at all
  inside the daily segment. Pinned by
  `test/domain/digest_projection_test.dart`'s monotonicity group.
- **Deliberately NOT a repeating OS alarm** (`matchDateTimeComponents`).
  Three independent reasons, the first of which is a correctness bug rather
  than a trade-off:
  - **A repeating trigger cannot be positioned at the end of the horizon.**
    Both platforms discard the scheduled date's calendar date and keep only
    the sub-day components: Android's
    `getNextFireDateMatchingDateTimeComponents` starts from *today* and
    walks forward to the next matching weekday, and iOS builds a
    `UNCalendarNotificationTrigger` from weekday/hour/minute/second with
    `repeats:YES`, dropping year/month/day. (The plugin's
    `validateDateIsInTheFuture` is skipped entirely when
    `matchDateTimeComponents != null`, confirming the date is a template,
    not a start.) So a "backstop past the horizon" fires *inside* the
    horizon instead — on a day the horizon may have deliberately silenced,
    and alongside that day's own digest if the times match.
  - It cannot honour the silence rule, and it freezes its body text at
    whatever the counts were when it was armed — a body no local recompute
    can ever correct.
  - It would require a named `Location` (the `flutter_timezone` dependency
    architecture #3 avoids); a UTC-anchored weekly repeat drifts an hour
    across every DST transition.
- **The digest is scoped to the device's acting member** (`actingMemberProvider`,
  triage T2.3): an occurrence counts when it is unassigned ("anyone" — that
  is genuinely everyone's business) or assigned to the acting member. Both
  partners must not receive the identical household-wide number. When the
  acting member cannot be resolved, everything counts.
- Tapping opens the app on the chores tab (default launch — no deep-link
  plumbing needed in N1).
- Overdue-only days still notify ('1 overdue chore') — overdue items are
  precisely what must not silently rot.

## Settings (device-level, single row)

New `settings` table (key-value would be exotic for 3 fields; a 1-row
table matches existing conventions): `id` TEXT PK (constant 'device'),
`digest_enabled` INTEGER (bool, default 1), `digest_minutes` INTEGER
(minutes since midnight, default 480), `created_at`/`updated_at` as
usual. `SettingsRepository` with `watchSettings()` / `setDigestEnabled` /
`setDigestTime`. schemaVersion 1→2 with an onUpgrade migration creating
the table (first real migration — write the drift migration test).

Settings tab gets its first built-in section (above the category
management entry point when #14 lands): 'Daily summary' toggle
(`settings.digest.toggle`), time row opening a time picker
(`settings.digest.time`), and — when the OS permission is denied — an
inline hint row with a button opening the system settings
(`settings.digest.permission`). Copy per design-language tone; all l10n.

## Architecture (testability first)

1. **Pure planner + projection** — `lib/domain/digest_planner.dart` and
   `lib/domain/digest_projection.dart`, zero deps beyond
   `lib/domain/recurrence/`:
   ```dart
   const int digestDailyHorizonDays = 14;   // consecutive daily slots
   const int digestWeeklyHorizonSlots = 10; // trailing slots
   const int digestHorizonTailStepDays = 7; // trailing slot spacing
   const int digestHorizonSlots =
       digestDailyHorizonDays + digestWeeklyHorizonSlots;
   List<DateTime> digestSlots({required DateTime now,
       required int digestMinutes, int dailyDays = digestDailyHorizonDays,
       int weeklySlots = digestWeeklyHorizonSlots});
   DigestPlan? planDigestSlot({required DateTime fireAt, required bool enabled,
       required int dueTodayCount, required int overdueCount});
   DigestCounts projectDigestCounts({
       required Iterable<ProjectedOccurrence> occurrences,
       required PlainDate date, required String? recipientMemberId});
   ```
   Slot rule: slot 0 is today at digest time if that is still ahead of
   `now`, else tomorrow. Daily slot `k` (`k < dailyDays`) is at day offset
   `k` from slot 0; trailing slot `j` is at day offset
   `(dailyDays - 1) + digestHorizonTailStepDays * (j + 1)`, so exactly one
   tail step separates the last daily slot from the first trailing one. All
   slots are the same local wall-clock time, built from calendar components,
   so a DST transition never shifts the hour — this holds for trailing slots
   too, which can be months out. Each slot's counts are projected for
   that slot's own DATE and its silence decision is made independently. The
   planner and projection stay pure; `lib/application/digest_plan_builder.dart`
   (`buildDigestPlans`) is the one place that joins them to real data, and
   is shared by the reschedule controller and the pre-prompt banner.
2. **`NotificationScheduler`** — `lib/application/notification_scheduler.dart`:
   wraps `flutter_local_notifications` behind a 3-method interface
   (`ensureInitialized`, `applyDigestPlans(List<DigestPlan?>)`,
   `cancelDigest()`), so everything above the plugin is testable with a
   fake. `applyDigestPlans` takes exactly `digestHorizonSlots` entries
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
3. **Plugin config**: `flutter_local_notifications` + `timezone`.
   `zonedSchedule` in the device's local zone. Android:
   `AndroidScheduleMode.inexactAllowWhileIdle` — a morning digest does
   not need second-precision, and inexact scheduling COMPLETELY avoids
   the SCHEDULE_EXACT_ALARM permission dance (deliberate; do not
   'upgrade' to exact). Channel id 'digest', importance default (not
   high — it's a summary, not an alarm). iOS: standard alert+badge+sound
   authorization requested ON FIRST ENABLE (not app launch — first-run
   permission prompts are hostile), i.e. from the settings toggle or the
   bootstrap default-enabled path's first schedule attempt.
   Each notification stays a genuine one-shot `zonedSchedule`; the repeat
   comes from the `digestHorizonSlots`-id horizon, never from
   `matchDateTimeComponents` (see N1 behavior for why).
- Permission denied → digest stays 'enabled' in settings but the
  settings screen shows the inline hint (the OS state is the source of
  truth, re-checked on app resume via the plugin's API).

### Notification id budget

*Whoever plans N2 / per-chore reminders must be able to find their budget
here, without reading any plan.*

- **The total: 64.** iOS caps an app at 64 pending notifications. Android
  imposes no equivalent per-app cap on the inexact alarms this app uses, so
  this is an iOS constraint — and it binds even though releases are
  currently Android-only (backlog A-3b).
- **The digest's share: 24.** `digestNotificationIdBase` (1001) through
  1024, i.e. `digestHorizonSlots` consecutive ids. The range is **derived
  from the constant, not hard-coded**, so it moves if
  `digestDailyHorizonDays` or `digestWeeklyHorizonSlots` moves.
- **The reservation: the remaining 40 are reserved for N2 / per-chore
  reminders (backlog G-6 / F16).** That is the feature the digest actually
  competes with for this budget — not the raw 64. A plan that spends
  against 64 rather than 40 is spending someone else's budget.
- **The enforcement point.**
  `test/application/notification_scheduler_test.dart` asserts
  `digestHorizonSlots <= 32`. A future horizon raise trips that guard rather
  than silently eating the reminder budget, and changing the guard means
  renegotiating this split — not quietly editing a number.

## Testing

- Planner: pure unit tests — slot arithmetic around midnight/DST-change
  days (schedule in local wall time; the 'today vs tomorrow slot'
  boundary at exactly digest time), enabled=false, zero-counts rule.
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
- **The far-horizon regression test (required):** the day-8+ analogue of
  the above, and the one that would catch a silent shrink of the horizon.
  Seed a daily chore, let one recompute run, then assert the furthest armed
  `fireAt` is **at least 80 days out** (an absolute date, deliberately NOT
  derived from `digestHorizonSlots`, so it cannot follow a shrinking horizon
  downwards) and that something is still armed after delivering 60 days'
  worth with no app interaction. A test exercising only days 1–7 passes
  identically before and after the horizon raise and proves nothing.
  Lives in `test/app/digest_reschedule_test.dart`.
- **The monotonicity guard (required):** the sparse tail is only safe
  because the silence decision is monotone in the date (see N1 behavior).
  `test/domain/digest_projection_test.dart` walks 120 days — past the
  furthest slot the horizon can reach — over a one-off, a
  completion-anchored chore, a schedule-anchored daily and weekly chore, and
  a mixed scoped/unscoped set, asserting `isSilent` never returns to `true`
  and `dueCount + overdueCount` never decreases. **If the horizon is ever
  raised past day 120, extend that walk.**
- **The cost bounds (required):** `test/app/digest_reschedule_test.dart`
  pins that five mutations in one debounce window cost exactly one apply,
  and that recomputes arriving during an in-flight apply coalesce into one
  trailing re-run (at most two applies per burst). These are exact counts on
  purpose — an `isNotEmpty` here would pass whether the debounce and the
  depth-1 queue work or not.
- Projection: pure unit tests — one-off and completion-anchored occurrences
  never move; a schedule-anchored one rolls forward to its latest slot on or
  before the queried date; recipient scoping counts mine + unassigned.
- Migration: drift schemaVersion 2 upgrade test (v1 db opens, table
  created, defaults present).
- Widget: settings section states (enabled/disabled/permission-denied
  hint), time picker round-trip.
- E2E (iOS + Android): enable toggle → OS permission dialog appears →
  grant (Maestro handles system dialogs) → settings show the chosen
  time. Actual fire-time verification is NOT E2E-testable in reasonable
  time; the scheduler's pending-request state is covered by an
  integration test via `pendingNotificationRequests()` in a dedicated
  `integration_test/` target instead.

## Out of scope for N1 (explicitly)

Per-chore reminders, actions on the notification, quiet hours beyond the
single digest time, per-member settings (meaningless until accounts),
badge counts, and anything requiring background execution.
