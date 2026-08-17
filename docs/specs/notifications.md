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
>   tail is where the reach comes from — the same 24 ids spent as
>   consecutive days would reach only day 23.
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

### Saying so when the digest cannot be delivered (backlog B-5 / triage T2.6)

A switch resting in its ON position is a claim. While the OS permission is
denied that claim is false — nothing is scheduled and nothing will arrive —
so two further always-current signals are binding. Both are pure
projections of state that already exists (`digestEnabled`, the live OS
permission state, `digestPrepromptShownAt`): no new stored flag, no
one-shot bookkeeping, nothing to dismiss, nothing that can go stale.

- **Toggle sub-line.** While the toggle is ON and the permission is denied,
  `settings.digest.toggle` carries a short factual sub-line
  (`settingsDigestToggleDeniedHint`, "Not delivering — notifications are
  off"). Presentation only: it must never write back to the stored
  `digestEnabled` (see the "Permission denied" rule below), or granting the
  permission later would find the digest quietly switched off.
- **Settings-tab attention dot.** An 8dp dot on the Settings tab's icon in
  the bottom nav (`lib/app/app_shell.dart`, semantic id
  `shell.tab.settings.attentionBadge`), shown iff `digestEnabled &&
  !permissionGranted && digestPrepromptShownAt != null`, carrying the same
  string as its accessibility label. Visible from every tab, because the
  user it exists for is precisely the one who dismissed the digest
  pre-prompt and will never open Settings on their own initiative. It
  clears itself the instant the permission is granted or the digest is
  switched off.

  The `digestPrepromptShownAt != null` clause is load-bearing, not
  incidental: `digestEnabled` defaults to true and an OS permission that
  has never been *requested* is indistinguishable from a denied one on iOS
  and Android 13+, so without it a brand-new install would launch already
  complaining about a question the app has not asked yet. This is the rule
  the pre-prompt banner already follows (spec
  `docs/specs/polish-round-1.md` A3: the permission question surfaces only
  after an explicit user tap), extended to cover the dot.

Together these are the ONLY durable recovery signals: the pre-prompt banner
is never re-armed. See `docs/specs/polish-round-1.md` A3.

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
   'upgrade' to exact). Channel id `'digest_v2'`, importance default (not
   high — it's a summary, not an alarm). The channel's NAME and DESCRIPTION
   are localized like every other user-visible string — they appear in
   system Settings → Apps → Notifications — and are passed per
   `zonedSchedule` call, because only the caller knows the current locale.
   **The `_v2` suffix is load-bearing, and so is the constant pair
   `digestChannelId`/`legacyDigestChannelId`.** Android caches a channel's
   name and description at CREATION time and has no rename operation, so
   re-localizing the original `'digest'` id would have changed nothing on
   any device that already had it. The fix therefore minted a new id and
   DELETES the legacy `'digest'` channel from `ensureInitialized`; without
   that delete an upgrading user holds two digest entries in system
   Settings, one of them dead and English-named. Any future change to this
   channel's copy faces the same constraint: bump the id AND delete the one
   it replaces. **Recorded decision — a LANGUAGE SWITCH does not update the
   channel name, and that is accepted.** The same caching freezes the name
   at whatever locale was active when the channel was first created, so a
   user who later switches language keeps the old label in system Settings
   forever. Minting a per-language id instead would accumulate one dead
   channel row per language the user ever tried AND discard their own
   importance/sound customization each time, since channel identity carries
   it — a worse trade than one stale label. The copy the user actually reads
   is unaffected: title and body are re-resolved on every reschedule.
   iOS: standard alert+badge+sound
   authorization requested ON FIRST ENABLE (not app launch — first-run
   permission prompts are hostile), i.e. from the settings toggle or the
   bootstrap default-enabled path's first schedule attempt.
   Each notification stays a genuine one-shot `zonedSchedule`; the repeat
   comes from the `digestHorizonSlots`-id horizon, never from
   `matchDateTimeComponents` (see N1 behavior for why).
4. **Which locale the copy is rendered in**: `resolveDigestLocale` — the
   in-app language override (`localeOverrideProvider`, backed by the
   persisted `settings.locale`) when the user has chosen one, else the OS
   locale. **The OS locale ALONE is wrong and was a real defect**: the UI
   honours the override, so a user who picked German on an English-language
   phone got English digest notifications behind a German app. It is
   resolved afresh on every apply — never cached in a field — so a language
   switch reaches the next reschedule; `notificationSchedulerProvider`
   therefore `read`s the override inside the resolver rather than `watch`ing
   it, since rebuilding the scheduler would drop its `_initialized` flag and
   its in-flight serialized-apply queue.
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
- **Notification ACTIONS spend nothing.** N2's digest "Done" action (see
  "N2: digest notification actions" below) attaches to notifications that
  already exist, so it consumes no id at all and leaves the 40 intact. The
  corollary is a constraint on anyone extending it: an action must never be
  answered with a *new* notification (a confirmation, an "undone" toast), as
  that would spend G-6's budget.

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

## N2: digest notification actions

Adds a single "Done" action to the digest notification (`docs/backlog.md`
F-1) — NOT the per-chore reminders/evening-re-reminder parts of N2, which
remain unbuilt (G-6). Spends **zero** notification ids: actions attach to the
existing horizon, so G-6's reserved 40 are untouched.

**Gate, evaluated PER SLOT.** The action is attached to a slot IF AND ONLY IF
that slot's own projected counts sum to exactly one occurrence
(`dueTodayCount + overdueCount == 1`) — the only case where "the chore" the
action names is unambiguous. Every other case (silent, or two-or-more) gets
no action; tapping the notification body still opens the app on the chores
tab, unchanged from N1. Slots are judged independently, so actionability is
NOT monotone along the horizon even though the silence decision is — counts
only grow, so a one-occurrence slot is often followed by two-occurrence ones.
The gate is deliberately NOT restricted to the daily segment: a pending
slot's payload is exactly as fresh as the last recompute whether it is slot 0
or slot 23, and the projection's accuracy is binary and slot-independent.

**What "Done" means.** Complete the specific occurrence ROW named in the
payload, if it is still pending; otherwise do nothing. Deliberately NOT
"complete whatever is due on the date this notification describes" — that is
what makes the answer independent of which slot fired and of how long the
notification sat unread. A row that is no longer pending (completed
elsewhere, or replaced by `catchUpOverdue` after an app open) is a silent
no-op. For a schedule-anchored overdue occurrence this records `done` where
in-app catch-up would have recorded `missed`; that divergence is accepted —
the user is asserting they did it, and `missed` is what catch-up infers from
the absence of any such assertion.

**Not shipped in N2 as scoped here:** "Snooze to tomorrow" — its own ticket
(decision closed in `docs/backlog.md` F-1).

**Payload.** Notification ids are SLOT-RELATIVE (`digestNotificationIdBase +
k`, k = offset from the next slot), so an id names neither a chore nor a date
and cannot be used to address anything; `NotificationResponse.id` is
additionally unreliable on the background path. The payload is therefore the
only channel, and carries JSON
`{"v":1,"occ":"<occurrenceId>","by":"<memberId>"|null}`:

- `occ` — the sole pending occurrence's id.
- `by` — the acting member the slot was computed and scoped for, resolved in
  the MAIN isolate. The background isolate must NOT re-derive this: the real
  chain needs `memberIdentityModeProvider`/`currentAuthUserProvider` (a live
  auth session), and in **pinned** mode with no resolvable claim it returns
  `null` rather than guessing — guessing is the misattribution A-5 closed. A
  `null` `by` becomes an unattributed completion.

Action id is namespaced **`digest.done`**; a future per-chore reminder (G-6)
mints its own rather than reusing it, because the background callback is
process-global.

**Handling:** `flutter_local_notifications`'
`onDidReceiveBackgroundNotificationResponse`, a SEPARATE background isolate
with no Riverpod container, no open `AppDatabase`, no `BuildContext`, and no
Supabase session. The top-level entrypoint
(`lib/application/notification_action_handler.dart`) opens its own
`AppDatabase(openConnection())` and, **in this order** (the callback is a
synchronous `void` typedef and the hosting context is time-boxed, so the
work must degrade gracefully if cut short):

1. calls the existing `ChoreService.completeOccurrence(occ, completedBy: by)`
   — the user's intent, must never be lost;
2. pings the main isolate via `IsolateNameServer` (best-effort; a `null`
   lookup means the app isn't running, which is fine);
3. rewrites the WHOLE horizon from the now-updated database via
   `buildDigestPlans` + `applyDigestPlans`, so a device whose app is never
   re-opened is not re-nagged about the chore it was just told is done. This
   is the only correct option: leaving the remaining slots armed means
   knowingly wrong counts, and cancelling them all means up to 83 days of
   silence, at identical cost.

then closes the connection in a `finally`. It never calls `cancel` on a
specific id: `AndroidNotificationAction.cancelNotification` defaults to
`true`, so the tapped notification is dismissed by the platform, and it has
already fired so nothing is pending on its id.

**Locale in the isolate.** The isolate's own `NotificationScheduler` resolves
copy through the SAME path the main isolate uses: `resolveDigestLocale` over
the persisted `settings.locale` (backlog E-1), read from the isolate's own
database connection by `readDigestLocale`. It must NOT fall back to
`NotificationScheduler`'s bare `PlatformDispatcher.instance.locale` default,
which would give a user who chose German on an English phone an English
"Done" button under a German app — exactly the defect E-1 closed for the
title and body, and more glaring on a button than in body text. The
stored-value → `Locale` mapping is shared with `localeOverrideProvider` via
`localeFromStoredSetting` so the two cannot drift apart.

**Known, bounded hazard:** `applyDigestPlans`' `_applyTail` serialization is
per-instance and does NOT cross isolates, so the background isolate and the
main isolate can interleave writes to the same 24 ids. Self-correcting
whenever it can occur — it requires the app to be alive, and an alive app
receives the ping after the isolate's write, so the main isolate's last apply
always runs on post-completion data. Do not attempt a cross-isolate lock.
Relatedly, `cancelDigest()` remains unserialized against `applyDigestPlans`;
with a second process-level writer that is now reachable in principle (a wipe
racing an action) and is tracked rather than fixed here.

**Cross-isolate UI refresh:** the main isolate registers a well-known
`IsolateNameServer` port at bootstrap. On a ping, it invalidates
`pendingOccurrencesProvider`/`closedTodayOccurrencesProvider` (so any open
screen re-reads the file fresh — a write through a second connection is
invisible to the first connection's stream-invalidation bus) and re-runs the
same recompute/push calls the existing app-resume observer already makes. The
invalidate is what guarantees correctness: the recompute fired in the same
handler may read pre-invalidation data, and `DigestRescheduleController`'s
existing `ref.listen` on the invalidated stream is what delivers the correct
second recompute. See `NotificationActionSignalController` in
`lib/app/providers.dart`.

**Platform setup:**
- Android: `AndroidNotificationAction('digest.done', <localized 'Done'>,
  showsUserInterface: false)` in `AndroidNotificationDetails.actions`,
  attached per-notification (so it always uses the current locale) only for
  slots carrying a sole occurrence id. New manifest receiver
  `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` (no new
  permission, and **no new channel id** — actions are per-notification, and
  the channel id is E-1's `digest_v2`).
- iOS: `DarwinNotificationCategory('digestActions', actions:
  [DarwinNotificationAction.plain('digest.done', <localized 'Done'>)])`
  registered once at `initialize()` via
  `DarwinInitializationSettings.notificationCategories`, and referenced
  per-notification through `DarwinNotificationDetails.categoryIdentifier`.
  Category action titles are fixed at registration, not per-notification — a
  known, accepted staleness window across a locale change until the next
  full app relaunch. `ios/Runner/AppDelegate.swift` needs
  `UNUserNotificationCenter.current().delegate = self` plus
  `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` wired inside
  `didInitializeImplicitFlutterEngine`, before the existing
  `GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)`
  call — without it the background engine's other plugins (path_provider and
  sqlite3, which drift needs) never register and the isolate can't touch the
  database.

**Testing.** The completion/attribution/rewrite logic
(`notification_action_processor.dart`) is fully unit-testable against an
in-memory `AppDatabase`, including the horizon rewrite that silences the stale
slots, and both are covered. The ping receiver is testable to the extent that
`IsolateNameServer` is same-process: `test/app/notification_action_signal_test.dart`
covers port registration/release and that a ping causes a recompute in a window
it first proves quiet. It does NOT reproduce the cross-connection invisibility
the invalidates exist for — that needs a second `AppDatabase` over a real file,
and on-disk drift inside `testWidgets`' fake-async zone hangs the suite. That
half is GATE-verified by hand (below), not by any automated test here.

**What no test in this repo covers, stated so nobody mistakes green CI for a
working feature.** The real background-isolate spawn, the manifest receiver,
the AppDelegate change, and whether `openConnection()`'s `path_provider`
channel lookup succeeds inside a background engine are all
platform-integration facts — the same carve-out N1 already accepts for
fire-time verification. `e2e.yml` cannot reach them either: it drives a
Maestro flow on an Android emulator, which can neither wait for a scheduled
digest nor tap a notification action. So the following are ASSUMED, and are
verified once per platform by hand against
`docs/plans/2026-08-08-notification-actions.md` Task 10, whose three **GATE**
items name each assumption and its fallback:

1. a background isolate can open the drift database at all (fallback: hand
   the isolate an explicit file path instead of a `path_provider` channel
   lookup — `AppDatabase` takes a plain `QueryExecutor`, so it is a change of
   executor, not of the class);
2. an action tap while the app is in the FOREGROUND still routes to the
   background callback (fallback: also handle
   `onDidReceiveNotificationResponse` in the main isolate, where a live
   Riverpod container makes it simpler, and keep the background path for the
   app-dead case);
3. the isolate lives long enough to finish the horizon rewrite (fallback:
   accept the truncation and document it — NOT a switch to `cancelDigest()`,
   which trades one wrong notification for up to 83 days of silence).

## Out of scope for N1 (explicitly)

Per-chore reminders, actions on the notification, quiet hours beyond the
single digest time, per-member settings (meaningless until accounts),
badge counts, and anything requiring background execution.

**Forward pointer:** "actions on the notification" is out of scope for *N1*
and is now specified above, under "N2: digest notification actions" — but
only the single "Done" action on the digest. Per-chore reminders, the evening
re-reminder, and "Snooze to tomorrow" all remain unbuilt.
