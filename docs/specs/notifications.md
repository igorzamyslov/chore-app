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

1. **Pure planner** — `lib/domain/digest_planner.dart`, zero deps:
   ```dart
   DigestPlan? planDigest({
     required DateTime now,            // device-local
     required int digestMinutes,
     required bool enabled,
     required int dueTodayCount,       // pending occurrences due today
     required int overdueCount,
   });
   // -> null (don't schedule: disabled, or counts both zero for the
   //    remaining slot today AND tomorrow's counts unknowable -> schedule
   //    tomorrow's slot with today's-close counts is WRONG; see rule
   //    below) or DigestPlan(fireAt, dueTodayCount, overdueCount).
   ```
   Scheduling rule: compute the NEXT slot (today at digest time if still
   ahead of `now`, else tomorrow). Content counts are computed for the
   slot's DATE: for a tomorrow slot, 'due today' means occurrences due on
   that tomorrow date plus everything currently overdue (recomputed by
   the caller). Planner stays pure; the counting queries live in the
   scheduler service.
2. **`NotificationScheduler`** — `lib/application/notification_scheduler.dart`:
   wraps `flutter_local_notifications` behind a 3-method interface
   (`ensureInitialized`, `scheduleDigest(DigestPlan)`, `cancelDigest()`),
   so everything above the plugin is testable with a fake. Reschedules
   (cancel + schedule, fixed notification id 1001) on: bootstrap, app
   resume, and any occurrence/chore/settings mutation — debounced 500ms
   via the existing stream providers (listen, not poll).
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
- Permission denied → digest stays 'enabled' in settings but the
  settings screen shows the inline hint (the OS state is the source of
  truth, re-checked on app resume via the plugin's API).

## Testing

- Planner: pure unit tests — slot arithmetic around midnight/DST-change
  days (schedule in local wall time; the 'today vs tomorrow slot'
  boundary at exactly digest time), enabled=false, zero-counts rule.
- Scheduler: fake-plugin tests — reschedule-on-mutation (complete a chore
  → scheduleDigest called with updated counts), debounce collapses
  bursts, cancel on disable.
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
