# Spec: Notifications (v1 — local, digest-first)

*The retention maker/breaker. Design principle from DESIGN.md §2: digest by
default, never nag. v1 is entirely LOCAL notifications (no server, no
push) — that covers the single-device household until the sync phase.*

## Phasing

- **N1 (this spec)**: one daily digest notification + settings UI +
  permission handling.
- **N2 (later, own spec)**: per-chore opt-in reminders, notification
  actions (Done / Snooze to tomorrow), evening re-reminder.
- **N3 (sync phase)**: server-scheduled push, cross-user events.

## N1 behavior

- One notification per day at a user-chosen time (default 08:00):
  title = app name, body = localized digest, e.g. '3 chores today' /
  '2 chores today · 1 overdue' / German equivalents (ICU plurals).
- **No notification at all when there is nothing due and nothing overdue**
  (silence is a feature: it keeps the signal meaningful).
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
   Each notification stays a genuine one-shot `zonedSchedule`; the daily
   repeat comes from the 7-id horizon, never from
   `matchDateTimeComponents` (see N1 behavior for why).
- Permission denied → digest stays 'enabled' in settings but the
  settings screen shows the inline hint (the OS state is the source of
  truth, re-checked on app resume via the plugin's API).

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
