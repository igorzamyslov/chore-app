# Digest notification actions (F-1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user mark a chore done directly from the daily digest
notification, without opening the app — but only when doing so is
unambiguous. Ship "Done ✓"; do NOT ship "Snooze to tomorrow" in this ticket
(see Open product decisions).

**Ticket:** `docs/backlog.md` F-1. **Spec:** `docs/specs/notifications.md`
(BINDING; N2 phase). Also touches `docs/feedback/2026-08-06-conventions-audit.md`
C11.

**Architecture, one paragraph:** the digest stays a summary. A "Done"
action is only attached when the digest's counts add up to exactly one
occurrence household-wide (`dueTodayCount + overdueCount == 1`) — the one
case where "the chore" is unambiguous. The action's `payload` carries that
occurrence's id. Tapping it fires `flutter_local_notifications`'
`onDidReceiveBackgroundNotificationResponse` in a **separate background
isolate** (no Riverpod, no open `AppDatabase`, no `BuildContext`): a thin
top-level entrypoint opens its own drift connection, resolves the acting
member the same way `actingMemberProvider` does, calls the existing
`ChoreService.completeOccurrence`, cancels the notification, closes the
connection, and — if the main app process is alive — pings it over
`dart:isolate`'s `IsolateNameServer` so the open `AppDatabase` connection's
Riverpod streams refresh and the digest/sync engine re-run immediately
instead of waiting for the next app-resume.

## Hard dependency: A-1 (digest scheduling rewrite)

`docs/plans/2026-08-08-daily-digest-scheduling.md` does not exist yet at
time of planning. **Assumption, stated per the ticket's instruction:** A-1
will keep `DigestRescheduleController` (or whatever supersedes it)
computing, at some call site, a `dueTodayCount`/`overdueCount` pair plus a
`fireAt` per digest slot — it may do this once or several times (per
remaining slot today, per recipient), and it may schedule several
notification ids instead of the fixed `1001`. This plan is written to be
robust to that:

- The new `DigestPlan.soleOccurrenceId` field is additive data, not new
  counting logic — whatever A-1's counting call site becomes, it captures
  "the occurrence's id, if the total is exactly 1" using the same loop that
  already produces the counts (Task 2 below shows today's version; A-1's
  author re-applies the same one-line addition to its replacement).
- The action handler reads the notification's own id off `NotificationResponse.id`
  (falling back to the constant only if null) rather than assuming `1001`,
  so it cancels the right notification even if A-1 introduces multiple ids.
- Nothing here assumes single-fire-per-day; the isolate-ping-triggers-recompute
  design (Task 7) works identically whether recompute runs once or many
  times a day.

If A-1 lands first and changes `DigestRescheduleController`'s shape
materially, Task 2 needs re-applying by hand to the new call site — flagged
inline there.

## Global Constraints

- Every user-visible string goes through gen_l10n: add to `lib/l10n/app_en.arb`
  (template) AND `lib/l10n/app_de.arb` (du-form). This includes notification
  action labels — they render from a background isolate with no
  `BuildContext`, so they go through `lookupAppLocalizations` +
  `NotificationScheduler`'s existing `localeResolver` seam, exactly like the
  digest title/body already do.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members
  need doc comments.
- Widget/unit tests are integration-style: real in-memory `AppDatabase` +
  fixed clock, overriding only `appDatabaseProvider`/`clockProvider` plus
  the documented `digestNotificationPluginProvider` seam. Never mock
  repositories or services.
- Never `await` a drift stream outside a widget pump in a **test** — that's
  what deadlocks under `flutter test`'s fake-async zone. This rule does NOT
  apply to real production code running under the real VM (the background
  isolate is real, not fake-async) — but this plan avoids the question
  entirely by adding one-shot `Future`-returning repository methods
  (Task 1a) instead of `.watch().first`, so there's no ambiguity either way.
- Never bare-await `bootstrapProvider.future` in a `ProviderContainer` test;
  use the existing `_awaitBootstrap` polling helper style from
  `test/app/digest_reschedule_test.dart`.
- `tester.pump(small duration)` between `container.dispose()` and
  `database.close()`.
- Run Flutter/Dart commands as `env -u GIT_DIR -u GIT_INDEX_FILE flutter ...`
  when anywhere near git hooks or worktrees. Do NOT run more than 2
  concurrent `flutter test`/`build` processes.
- Never add `Co-Authored-By` trailers to commits.
- TDD: write-failing-test → run → implement → run → commit, per task below.

## Analysis: what can "Done" mean on a digest?

**The problem:** "Done ✓" on a notification that says "3 chores today" is
ambiguous — which of the three? DESIGN.md §3 named the action without
resolving this; the ticket explicitly asks not to invent a confusing
affordance.

**Option A — act on all of them.** "Done" marks every currently-pending
occurrence the digest counted as done. Rejected: silently completing chores
the user never looked at is worse than the ambiguity it resolves — a wrong
one-tap bulk action on physical chores (not todo-list items) is exactly the
kind of "trust" bug this project's `docs/feedback/` audits keep flagging.
Also can't attribute misses/skips sensibly (what if one was meant to be
skipped, not done?).

**Option B — tap-through only, no action button at all.** Simplest, zero
ambiguity, matches the ticket's suggested "honest alternative." Rejected as
the *sole* answer because it leaves F-1 basically undone (it's exactly
today's N1 behavior) when a real, common case — a single remaining chore —
has an obviously correct action.

**Option C (chosen) — actions only when the digest is provably about one
occurrence.** Gate on `dueTodayCount + overdueCount == 1`. In that case the
digest body already reads as a single-chore sentence ("1 chore today" / "1
overdue chore") and there is exactly one occurrence id the action can mean.
Every other case (0 — no notification at all anyway; ≥2) gets no action,
falling back to tap-through (today's existing, already-correct behavior).
This is additive and never wrong: the label always matches what it acts on.

**Why not widen "sole occurrence" to "sole *chore*, multiple would-be
occurrences"?** Can't happen — a chore has at most one pending occurrence
at a time (see `ChoreService`'s invariants), so "one occurrence" and "one
chore's pending item" are the same condition.

## Analysis: the background isolate / cross-connection problem

The genuinely hard part, per the ticket. Two sub-problems:

**1. Opening a second DB connection safely.** `drift_flutter`'s
`openConnection()` (`lib/data/db/app_database.dart:156`) opens a WAL-mode
SQLite file at a fixed path per device. Two `AppDatabase(openConnection())`
instances — one in the main isolate, one freshly created inside the
background isolate for the single action-handling transaction — are two
independent native sqlite3 connections to the *same file*, in the *same OS
process* (Android/iOS both run the background notification-response
isolate as a second Dart isolate inside the same app process via the
plugin's own headless `FlutterEngineManager`, not a separate OS process).
SQLite's own file locking handles concurrent connections to one file
correctly (that's what WAL mode is for) — no corruption risk from opening a
second connection, as long as each side only holds it open for the single
transaction's lifetime and closes it immediately after (never left dangling
across isolate messages). This plan's `NotificationActionProcessor`
(Task 5) does exactly one `database.transaction(...)` worth of work (via
the existing `ChoreService`) and the entrypoint (Task 6) closes the
connection immediately after, in a `finally`.

**2. How does the in-app UI learn about a change made from outside it?**
This is the part with no free lunch. Drift's reactive `.watch()` streams
only re-emit on writes made **through the same `AppDatabase`/`QueryExecutor`
instance** — a write via a second, independently-opened connection to the
same file is invisible to the first connection's stream-invalidation bus.
Two isolates in the same process do not share that bus. Considered:

- **Rely solely on the existing app-resume observer.** Free, but wrong:
  `flutter_local_notifications` routes any action with
  `showsUserInterface: false` (which "Done" must be — it shouldn't launch
  the app) to the background isolate **even if the app is already in the
  foreground** (confirmed in the plugin's own doc comment: the routing
  decision is per-action, not per-app-state). A user who pulls down the
  notification shade while the app is open and taps "Done" would see no
  UI update at all until they happen to background/foreground the app.
- **Full recompute inside the background isolate, reschedule there too.**
  Correct in principle but duplicates `DigestRescheduleController._recompute`'s
  counting/planning logic in a second place with no Riverpod to share it
  through, and re-introduces the exact "shape may change under A-1" risk
  this plan is trying to stay robust to. Rejected as more code for a
  same-or-worse result than the option below.
- **Chosen: cross-isolate ping via `dart:isolate`'s `IsolateNameServer`,
  cancel eagerly, let the main isolate recompute.** The background isolate
  (a) unconditionally cancels the acted-on notification (a summary that no
  longer reflects reality is worse than briefly showing nothing — consistent
  with the "silence is a feature" rule already in the spec), then (b) looks
  up a well-known port name and sends a no-payload ping, ignoring failure
  (`null` result — main isolate not alive right now). If the app is alive,
  the ping arrives essentially instantly and a new controller
  (`NotificationActionSignalController`, Task 7) invalidates the two
  drift-stream providers that read pending/closed occurrences and reruns
  the exact same three calls `main.dart`'s app-resume observer already
  makes (`digestController.triggerRecompute()`,
  `syncEngineController.triggerOnResume()`, implicitly re-catching-up via
  the invalidated stream). If the app is NOT alive, the notification stays
  cancelled and the change is picked up for free the next time anything
  triggers a recompute (next app open, most likely) — an accepted gap
  identical in kind to the app's already-documented "no background sync
  while the app is closed" trade-off (`docs/backlog.md`, Known trade-offs).
  `IsolateNameServer` is in-process and OS-independent, so this also works
  identically in tests (Task 7's test looks the port up and sends to it
  directly, no real isolate spawn needed).

This also solves sync propagation for free: `ChoreService.completeOccurrence`
already marks the row `syncDirty` regardless of which `AppDatabase`
connection called it (it's a column write, not a stream side effect), and
`syncEngineController.triggerOnResume()` (called by the same ping handler)
already knows how to push dirty rows — no new sync-engine code needed.

## Platform setup, concretely

**Android:** no new *permission* (correct per the ticket). It DOES need one
new manifest **receiver** the app doesn't have yet:
`com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` (verified
against the plugin's own example manifest — only `ScheduledNotificationReceiver`
and `ScheduledNotificationBootReceiver` are registered today). Action
buttons render fine at the digest channel's existing default importance —
no channel change needed.

**iOS:** needs (a) a `DarwinNotificationCategory` with the "Done" action
registered at `initialize()` time (`DarwinInitializationSettings.notificationCategories`),
and (b) `ios/Runner/AppDelegate.swift` wiring that the app does not have
today — verified against the plugin's own example `AppDelegate.swift`:
`UNUserNotificationCenter.current().delegate` must be set, and
`FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` must run
*inside* `didInitializeImplicitFlutterEngine`, *before*
`GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)` —
otherwise the background engine's own plugin channels (including drift's
sqlite3 plugin) never get registered and the isolate silently can't do
anything. This file is 100% untestable from `flutter test`; verify manually
on a real device/simulator once (see Testing).

iOS category action titles are fixed at `initialize()` time (`UNNotificationCategory`
has no per-notification title override, unlike Android). Since
`NotificationScheduler.ensureInitialized()` is idempotent for the process's
lifetime, the iOS "Done" label is fixed at whichever locale was active on
the very first `ensureInitialized()` call of that process — same
class of limitation the existing `localeResolver` doc comment already
lives with for the body text refreshing per-call; Android's per-notification
action title has no such staleness. Documented, not solved — a language
change taking a relaunch to fully propagate is normal on both platforms.

## Open product decisions

**D1 — Ship "Done" only, defer "Snooze to tomorrow."**
- *Option A:* ship both now.
- *Option B (recommended):* ship "Done" only in this ticket; "Snooze"
  becomes its own follow-up ticket.
- *Option C:* ship neither; tap-through only (see Option B in the
  ambiguity analysis above — rejected as leaving F-1 undone).

*Why B:* "Snooze to tomorrow" needs domain semantics that don't exist yet.
`skipOccurrence` advances the chore's *entire* recurrence schedule (wrong —
snoozing shouldn't burn the slot or touch rotation); there is no existing
"shift this one occurrence's due date by a day, keep everything else" op.
Worse, its meaning is genuinely undefined for the overdue case this ticket
also has to handle: does "snooze to tomorrow" on a 3-days-overdue occurrence
make it due tomorrow (quietly erasing how overdue it was) or shift it one
day *from its current due date* (still overdue, just less so — confusing)?
That's a real product call with no derivable answer, and bundling it into
this ticket would block the unambiguous, clearly-scoped "Done" half on it.

**D2 — Confirmed via code, not a decision, but flagging for visibility:**
attributing "Done" to `settings.actingMemberId`'s fallback chain (not
"whoever physically tapped the phone") is identical to the app's existing
single-device-acting-member model for the in-app complete button
(`chores_list_screen.dart:205`) — not a new ambiguity this ticket
introduces, so not listed as an open decision.

## File map

**New:**
- `lib/application/notification_action_processor.dart` — testable
  completion logic (occurrence id → resolve acting member → `ChoreService.completeOccurrence`).
- `lib/application/notification_action_handler.dart` — the `@pragma('vm:entry-point')`
  top-level background-isolate entrypoint; thin glue only.
- `test/application/notification_action_processor_test.dart`
- `test/app/notification_action_signal_test.dart`

**Edited:**
- `docs/specs/notifications.md` — new N2 section.
- `lib/domain/digest_planner.dart` + `test/domain/digest_planner_test.dart`
  — `DigestPlan.soleOccurrenceId`.
- `lib/app/providers.dart` — `_recompute` captures the sole occurrence id;
  new `NotificationActionSignalController` + provider.
- `test/app/digest_reschedule_test.dart` — sole-occurrence-id coverage.
- `lib/application/notification_scheduler.dart` +
  `test/application/notification_scheduler_test.dart` — actionable
  scheduling, localized action title.
- `test/application/fake_digest_notification_plugin.dart` — record the new
  `zonedSchedule`/`initialize` parameters.
- `lib/data/repositories/household_repository.dart` +
  `test/data/repositories/household_repository_test.dart` — one-shot
  `getMembers`.
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` — `notificationActionDone`.
- `main.dart` — construct `NotificationActionSignalController` alongside
  the other three bootstrap controllers.
- `android/app/src/main/AndroidManifest.xml` — `ActionBroadcastReceiver`.
- `ios/Runner/AppDelegate.swift` — plugin registrant callback + delegate.

---

## Task 1: Spec first — extend `docs/specs/notifications.md`

**Files:** Edit `docs/specs/notifications.md`.

Add a new section after "## Testing" and before "## Out of scope for N1"
(and amend that out-of-scope line, which currently lists "actions on the
notification" as N2 scope — leave it, but add a forward pointer):

```markdown
## N2: digest notification actions

Adds a single "Done" action to the digest notification (`docs/backlog.md`
F-1) — NOT the per-chore reminders/evening-re-reminder parts of N2, which
remain unbuilt (G-6).

**Gate:** the action is attached IF AND ONLY IF the digest's counts sum to
exactly one occurrence (`dueTodayCount + overdueCount == 1`) — the only
case where "the chore" the action names is unambiguous. Every other case
(nothing due, or two-or-more) gets no action; tapping the notification body
still opens the app on the chores tab, unchanged from N1.

**Not shipped in N2 as scoped here:** "Snooze to tomorrow" — deferred; see
`docs/plans/2026-08-08-notification-actions.md`'s Open product decisions
D1 for why.

**Payload:** the sole occurrence's id, as the notification's plain-string
`payload` (no JSON needed for one field).

**Handling:** `flutter_local_notifications`'
`onDidReceiveBackgroundNotificationResponse`, a SEPARATE background isolate
with no Riverpod container, no open `AppDatabase`, no `BuildContext`. The
top-level entrypoint (`lib/application/notification_action_handler.dart`)
opens its own `AppDatabase(openConnection())`, resolves the acting member
exactly as `actingMemberProvider` does (device settings'
`actingMemberId` if it names a current member, else the household's first
admin, else its first member), calls the existing
`ChoreService.completeOccurrence`, closes the connection, cancels the
notification (by `NotificationResponse.id`, not a hardcoded id), and pings
the main isolate via `IsolateNameServer` (best-effort; a `null` lookup
means the app isn't running, which is fine — the file write already
persisted, and the next app open reads it correctly with no extra work).
A stale payload (the occurrence was already closed/deleted/reassigned
since the digest was computed) is caught and treated as a silent no-op, not
a crash — the same "don't fight the user over a foot-gun that's already
happened" posture as `ChoreService`'s other lifecycle guards.

**Cross-isolate UI refresh:** the main isolate registers a well-known
`IsolateNameServer` port at bootstrap. On a ping, it invalidates
`pendingOccurrencesProvider`/`closedTodayOccurrencesProvider` (so any open
screen re-reads the file fresh) and re-runs the same recompute/push calls
the existing app-resume observer already makes. See
`NotificationActionSignalController` in `lib/app/providers.dart`.

**Platform setup:**
- Android: `AndroidNotificationAction('done', <localized 'Done'>,
  showsUserInterface: false)`, attached per-notification (so it always uses
  the current locale) only when the plan carries a sole occurrence id. New
  manifest receiver `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver`
  (no new permission).
- iOS: `DarwinNotificationCategory('digestActions', actions:
  [DarwinNotificationAction.plain('done', <localized 'Done'>)])` registered
  once at `initialize()` (category action titles are fixed at registration,
  not per-notification — a known, accepted staleness window across a
  locale change until the next full app relaunch). `ios/Runner/AppDelegate.swift`
  needs `UNUserNotificationCenter.current().delegate = self` plus
  `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` wired
  inside `didInitializeImplicitFlutterEngine`, before the existing
  `GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)`
  call — without it the background engine's other plugins (including
  drift's sqlite3 plugin) never register and the isolate can't touch the
  database.

**Testing:** the completion/attribution logic
(`NotificationActionProcessor`) is fully unit-testable against an in-memory
`AppDatabase`. The plugin-level wiring (real background isolate spawn, real
`IsolateNameServer` cross-process delivery, the AppDelegate change) is not
E2E-testable in reasonable time — same carve-out N1's spec already accepts
for fire-time verification — and needs one manual on-device check per
platform before release.
```

No code changes in this task. Commit message: "Spec the F-1 digest notification actions design".

---

## Task 2: `DigestPlan.soleOccurrenceId`

TDD: extend the existing pure-domain test first.

**Files:**
- Edit `test/domain/digest_planner_test.dart`
- Edit `lib/domain/digest_planner.dart`

**Test additions** (mirror the existing table-driven style in that file;
add a new `group('soleOccurrenceId')`):

```dart
group('soleOccurrenceId', () {
  test('planDigest carries a provided soleOccurrenceId through unchanged', () {
    final plan = planDigest(
      now: DateTime(2026, 7, 24, 7),
      digestMinutes: 480,
      enabled: true,
      dueTodayCount: 1,
      overdueCount: 0,
      soleOccurrenceId: 'occ-1',
    );
    expect(plan!.soleOccurrenceId, 'occ-1');
  });

  test('defaults to null when omitted', () {
    final plan = planDigest(
      now: DateTime(2026, 7, 24, 7),
      digestMinutes: 480,
      enabled: true,
      dueTodayCount: 3,
      overdueCount: 0,
    );
    expect(plan!.soleOccurrenceId, isNull);
  });

  test('DigestPlan equality/hashCode include soleOccurrenceId', () {
    final a = DigestPlan(
      fireAt: DateTime(2026, 7, 25, 8),
      dueTodayCount: 1,
      overdueCount: 0,
      soleOccurrenceId: 'occ-1',
    );
    final b = DigestPlan(
      fireAt: DateTime(2026, 7, 25, 8),
      dueTodayCount: 1,
      overdueCount: 0,
      soleOccurrenceId: 'occ-2',
    );
    expect(a == b, isFalse);
    expect(a.hashCode == b.hashCode, isFalse);
  });
});
```

Run: `flutter test test/domain/digest_planner_test.dart` — new tests fail
(no such named parameter yet).

**Implementation** — `lib/domain/digest_planner.dart`: add the field,
constructor param, `==`/`hashCode`/`toString` inclusion, and thread it
through `planDigest` untouched (this function stays pure — it doesn't
*decide* the sole occurrence, only carries whatever the caller determined):

```dart
class DigestPlan {
  const DigestPlan({
    required this.fireAt,
    required this.dueTodayCount,
    required this.overdueCount,
    this.soleOccurrenceId,
  });

  final DateTime fireAt;
  final int dueTodayCount;
  final int overdueCount;

  /// The id of the single pending occurrence this digest is about, set only
  /// when [dueTodayCount] + [overdueCount] == 1 — the one case where "the
  /// chore" a notification action would name is unambiguous (spec
  /// `docs/specs/notifications.md` N2). `null` otherwise, including when
  /// the caller simply didn't compute it (this class doesn't enforce the
  /// invariant itself — see [planDigest]'s doc comment).
  final String? soleOccurrenceId;

  @override
  bool operator ==(Object other) =>
      other is DigestPlan &&
      other.fireAt == fireAt &&
      other.dueTodayCount == dueTodayCount &&
      other.overdueCount == overdueCount &&
      other.soleOccurrenceId == soleOccurrenceId;

  @override
  int get hashCode =>
      Object.hash(fireAt, dueTodayCount, overdueCount, soleOccurrenceId);

  @override
  String toString() =>
      'DigestPlan(fireAt: $fireAt, dueTodayCount: $dueTodayCount, '
      'overdueCount: $overdueCount, soleOccurrenceId: $soleOccurrenceId)';
}
```

And `planDigest`'s signature grows one optional parameter, documented as
the caller's responsibility to only pass when the count invariant holds:

```dart
DigestPlan? planDigest({
  required DateTime now,
  required int digestMinutes,
  required bool enabled,
  required int dueTodayCount,
  required int overdueCount,
  String? soleOccurrenceId,
}) {
  _validateDigestMinutes(digestMinutes);
  if (!enabled) return null;
  if (dueTodayCount == 0 && overdueCount == 0) return null;
  return DigestPlan(
    fireAt: nextDigestSlot(now: now, digestMinutes: digestMinutes),
    dueTodayCount: dueTodayCount,
    overdueCount: overdueCount,
    soleOccurrenceId: soleOccurrenceId,
  );
}
```

Run tests again — all pass. Commit: "Add DigestPlan.soleOccurrenceId".

---

## Task 3: capture the sole occurrence id in `DigestRescheduleController`

**Files:**
- Edit `test/app/digest_reschedule_test.dart`
- Edit `lib/app/providers.dart`

**Test addition** (new `testWidgets` case in the existing file, following
the same structure as "reschedules after a mutation creates a due-today
occurrence"):

```dart
testWidgets(
  'a single pending occurrence is scheduled as actionable with its id',
  (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final plugin = FakeDigestNotificationPlugin();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 7))),
        digestNotificationPluginProvider.overrideWithValue(plugin),
      ],
    );
    addTearDown(container.dispose);
    await container.read(householdRepositoryProvider).createLocalHousehold('Me');

    container.read(digestRescheduleControllerProvider);
    final householdId = await _awaitBootstrap(tester, container);
    final today = PlainDate.fromDateTime(container.read(clockProvider).now());
    final chore = await container.read(choreServiceProvider).createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: today,
      assignmentMode: AssignmentMode.anyone,
    );
    await tester.pump(digestRescheduleDebounce);

    expect(plugin.scheduledCalls, hasLength(1));
    final pending = await container
        .read(choreRepositoryProvider)
        .pendingOccurrenceOf(chore.id);
    expect(plugin.scheduledCalls.single.payload, pending!.id);

    await database.close();
  },
);

testWidgets(
  'two pending occurrences are scheduled without a payload',
  (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final plugin = FakeDigestNotificationPlugin();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 7))),
        digestNotificationPluginProvider.overrideWithValue(plugin),
      ],
    );
    addTearDown(container.dispose);
    await container.read(householdRepositoryProvider).createLocalHousehold('Me');

    container.read(digestRescheduleControllerProvider);
    final householdId = await _awaitBootstrap(tester, container);
    final today = PlainDate.fromDateTime(container.read(clockProvider).now());
    final choreService = container.read(choreServiceProvider);
    await choreService.createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: today,
      assignmentMode: AssignmentMode.anyone,
    );
    await choreService.createChore(
      householdId: householdId,
      title: 'Take out the trash',
      startDate: today,
      assignmentMode: AssignmentMode.anyone,
    );
    await tester.pump(digestRescheduleDebounce);

    expect(plugin.scheduledCalls, hasLength(1));
    expect(plugin.scheduledCalls.single.payload, isNull);

    await database.close();
  },
);
```

`ScheduledCall`/`FakeDigestNotificationPlugin` don't have `payload` yet —
add it now (small, do it before running the test):

**`test/application/fake_digest_notification_plugin.dart`:** add a
`payload` field to `ScheduledCall` and thread it through
`zonedSchedule`'s recorded call (see Task 4 for the interface change this
depends on — do Task 4's interface edit first, or do both together since
they're tightly coupled; either order is fine as long as both compile
before running Task 3's test).

Run: fails (payload always null; `_recompute` doesn't compute it).

**Implementation — `lib/app/providers.dart`, inside `DigestRescheduleController._recompute`:**
capture the sole occurrence alongside the existing counts (the loop already
visits every pending occurrence once; this is one more local, not a second
pass):

```dart
var dueTodayCount = 0;
var overdueCount = 0;
String? soleOccurrenceId;
for (final occurrence in pending) {
  final dueDate = occurrence.occurrence.dueDate;
  if (dueDate == slotDate) {
    dueTodayCount++;
    soleOccurrenceId = occurrence.occurrence.id;
  } else if (dueDate.isBefore(slotDate)) {
    overdueCount++;
    soleOccurrenceId = occurrence.occurrence.id;
  }
}
if (dueTodayCount + overdueCount != 1) {
  soleOccurrenceId = null;
}

final plan = planDigest(
  now: now,
  digestMinutes: settings.digestMinutes,
  enabled: settings.digestEnabled,
  dueTodayCount: dueTodayCount,
  overdueCount: overdueCount,
  soleOccurrenceId: soleOccurrenceId,
);
```

(`soleOccurrenceId` ends up holding whichever qualifying occurrence's id
was seen last; the final `!= 1` check is what actually enforces the
invariant regardless of iteration order — simpler than tracking a
`matchCount` separately.)

Run tests — pass. Commit: "Capture the sole pending occurrence for digest actions".

**Note for whoever re-applies this after A-1 lands:** if A-1's replacement
recompute logic scopes counts per-recipient/per-slot rather than in one
household-wide loop like today's, apply the same pattern to WHICHEVER loop
produces the final `dueTodayCount`/`overdueCount` pair that gets handed to
`planDigest` for a given slot — the invariant is always "total count for
this specific plan == 1".

---

## Task 4: `NotificationScheduler`/`DigestNotificationPlugin` — actionable scheduling

TDD: scheduler tests first.

**Files:**
- Edit `test/application/fake_digest_notification_plugin.dart`
- Edit `test/application/notification_scheduler_test.dart`
- Edit `lib/application/notification_scheduler.dart`
- Edit `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`

**l10n additions** (`app_en.arb`, near the other `notificationDigest*`
entries):

```json
"notificationActionDone": "Done",
"@notificationActionDone": {
  "description": "Label of the 'mark done' action button on the daily digest notification, shown only when the digest is unambiguously about a single chore."
},
```

`app_de.arb`: `"notificationActionDone": "Erledigt",` with the matching
`@notificationActionDone` metadata block (match this file's existing
convention of repeating the same `@`-key structure — check a neighboring
entry, e.g. `notificationDigestDueOnly`, for the exact du-form/metadata
style already used there).

**`DigestNotificationPlugin` interface change** — `initialize()` gains a
required localized action title (used only for iOS category registration;
Android ignores it since its action title is set per-notification):

```dart
abstract class DigestNotificationPlugin {
  Future<void> initialize({required String doneActionTitle});
  // ... requestPermission / isPermissionGranted unchanged ...

  /// [payload] is the sole occurrence id when [actionable] is true, else
  /// `null`. [actionable] attaches the localized 'Done' action (spec
  /// `docs/specs/notifications.md` N2) — Android per-notification, iOS via
  /// the 'digestActions' category registered in [initialize].
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    String? payload,
    bool actionable = false,
  });

  Future<void> cancel(int id);
}
```

**`FakeDigestNotificationPlugin`:** update `initialize()` to accept/record
`doneActionTitle`, add fields, and extend `ScheduledCall`:

```dart
class ScheduledCall {
  const ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    this.payload,
    this.actionable = false,
  });
  // ... existing fields ...
  final String? payload;
  final bool actionable;
}

class FakeDigestNotificationPlugin implements DigestNotificationPlugin {
  // ... existing fields ...
  String? lastDoneActionTitle;

  @override
  Future<void> initialize({required String doneActionTitle}) async {
    initializeCallCount++;
    lastDoneActionTitle = doneActionTitle;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    String? payload,
    bool actionable = false,
  }) async {
    scheduledCalls.add(
      ScheduledCall(
        id: id,
        title: title,
        body: body,
        fireAt: fireAt,
        payload: payload,
        actionable: actionable,
      ),
    );
  }
}
```

**New scheduler tests** — `test/application/notification_scheduler_test.dart`,
new `group('actionable scheduling')`:

```dart
group('actionable scheduling', () {
  test('a plan with a soleOccurrenceId schedules actionable with payload', () async {
    await scheduler.scheduleDigest(
      DigestPlan(
        fireAt: plan.fireAt,
        dueTodayCount: 1,
        overdueCount: 0,
        soleOccurrenceId: 'occ-1',
      ),
    );
    final call = plugin.scheduledCalls.single;
    expect(call.actionable, isTrue);
    expect(call.payload, 'occ-1');
  });

  test('a plan without a soleOccurrenceId schedules non-actionable, no payload', () async {
    await scheduler.scheduleDigest(plan); // dueTodayCount: 3, no sole id
    final call = plugin.scheduledCalls.single;
    expect(call.actionable, isFalse);
    expect(call.payload, isNull);
  });

  test('ensureInitialized passes the localized Done title', () async {
    await scheduler.ensureInitialized();
    expect(plugin.lastDoneActionTitle, 'Done');
  });

  test('German locale localizes the Done action title', () async {
    final germanScheduler = NotificationScheduler(
      plugin: plugin,
      localeResolver: () => const Locale('de'),
    );
    await germanScheduler.ensureInitialized();
    expect(plugin.lastDoneActionTitle, 'Erledigt');
  });
});
```

Run — fails to compile/fails assertions. Implement:

**`lib/application/notification_scheduler.dart`:**

```dart
Future<void> ensureInitialized() async {
  if (_initialized) return;
  final l10n = lookupAppLocalizations(localeResolver());
  await plugin.initialize(doneActionTitle: l10n.notificationActionDone);
  _initialized = true;
}

Future<void> scheduleDigest(DigestPlan plan) async {
  await ensureInitialized();
  final l10n = lookupAppLocalizations(localeResolver());
  await plugin.zonedSchedule(
    id: digestNotificationId,
    title: l10n.appTitle,
    body: _digestBody(l10n, plan),
    fireAt: plan.fireAt,
    payload: plan.soleOccurrenceId,
    actionable: plan.soleOccurrenceId != null,
  );
}
```

**`FlutterLocalNotificationsAdapter`** — real plugin wiring. Import the new
handler file (Task 6) for the callback reference and the category/action
constants:

```dart
import 'package:chore_app/application/notification_action_handler.dart';

const String digestActionsCategoryId = 'digestActions';
const String digestDoneActionId = 'done';

class FlutterLocalNotificationsAdapter implements DigestNotificationPlugin {
  FlutterLocalNotificationsAdapter() : _plugin = FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  String _doneActionTitle = 'Done';

  @override
  Future<void> initialize({required String doneActionTitle}) async {
    _doneActionTitle = doneActionTitle;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          digestActionsCategoryId,
          actions: [
            DarwinNotificationAction.plain(digestDoneActionId, doneActionTitle),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveBackgroundNotificationResponse: notificationActionCallbackDispatcher,
    );
  }

  // ... requestPermission / isPermissionGranted unchanged ...

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    String? payload,
    bool actionable = false,
  }) async {
    final scheduledDate = tz.TZDateTime.from(fireAt, tz.UTC);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          digestChannelId,
          'Daily summary',
          channelDescription: 'The once-a-day chores digest notification.',
          actions: actionable
              ? [
                  AndroidNotificationAction(
                    digestDoneActionId,
                    _doneActionTitle,
                    showsUserInterface: false,
                  ),
                ]
              : null,
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: actionable ? digestActionsCategoryId : null,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
```

(Drop the `const` on `NotificationDetails`/`AndroidNotificationDetails`/
`DarwinNotificationDetails` since fields are now conditional — the compiler
will flag this if missed.)

Run all scheduler tests — pass. Commit: "Attach a localized Done action to single-occurrence digests".

---

## Task 5: `NotificationActionProcessor` — the testable completion logic

TDD: test first, against a real in-memory `AppDatabase` (per Global
Constraints — no mocking).

**Files:**
- Create `test/application/notification_action_processor_test.dart`
- Create `lib/application/notification_action_processor.dart`
- Edit `lib/data/repositories/household_repository.dart` (one-shot `getMembers`)
- Edit `test/data/repositories/household_repository_test.dart`

**5a. One-shot `getMembers`** (needed because there's no Riverpod/stream
consumer in the background isolate — see Global Constraints on why this
plan adds a `Future` getter instead of `.watch().first`). Add right after
`watchMembers`, refactoring the shared filter out first:

```dart
Query<Members, Member> _activeMembersQuery(String householdId) {
  return db.select(db.members)
    ..where((tbl) => tbl.householdId.equals(householdId) & tbl.deletedAt.isNull())
    ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]);
}

/// One-shot version of [watchMembers], same ordering/filtering — for
/// callers with no stream consumer (e.g.
/// `NotificationActionProcessor`, which runs in a background isolate with
/// no Riverpod container to keep a subscription alive).
Future<List<Member>> getMembers(String householdId) {
  return _activeMembersQuery(householdId).get();
}

Stream<List<Member>> watchMembers(String householdId) {
  return _activeMembersQuery(householdId).watch();
}
```

(Check the real return type of `db.select(db.members)..where(...)` in this
codebase's drift version — it's a `SimpleSelectStatement<Members, Member>`,
not `Query`; use whatever type `watchMembers`'s current local variable
already infers, or just inline the two near-identical query builders
without a shared private method if the generated type is awkward to name —
either is fine, the point is no duplicated where/orderBy, not the exact
extraction shape.)

Test — `household_repository_test.dart`, alongside existing `watchMembers`
tests:

```dart
test('getMembers returns the same active-members set as watchMembers, ordered by creation', () async {
  final household = await repository.createLocalHousehold('Me');
  // seed a second member the same way existing watchMembers tests do
  // (mirror that test's setup exactly — inspect it for the helper used)
  final members = await repository.getMembers(household.id);
  expect(members, hasLength(/* whatever the mirrored setup creates */));
});

test('getMembers excludes soft-deleted members', () async {
  // mirror the existing watchMembers soft-delete test's setup
});
```

**5b. `NotificationActionProcessor`:**

```dart
/// Resolves and applies a "Done" notification action outside any Riverpod
/// container (spec `docs/specs/notifications.md` N2): the reusable,
/// fully-unit-testable core that
/// `lib/application/notification_action_handler.dart`'s background-isolate
/// entrypoint calls after opening its own [AppDatabase] connection.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:clock/clock.dart';

/// Applies a digest "Done" action for occurrence [occurrenceId] against
/// [database].
///
/// Attribution mirrors `actingMemberProvider`
/// (`lib/app/providers.dart`) exactly: the device's stored
/// `actingMemberId` if it names a current member of the household, else
/// the household's first admin, else its first member, else (only if the
/// household somehow has no members at all — shouldn't happen post-onboarding)
/// falls back to the occurrence's own assignee.
///
/// Swallows a stale payload silently (the occurrence isn't pending anymore
/// — already completed from the app, reassigned, or its chore deleted,
/// between the digest firing and the user tapping it): this is a
/// best-effort background action with no UI to report an error to, so
/// "someone already handled it" is a success, not a failure. Any other
/// unexpected exception is deliberately NOT swallowed — the entrypoint
/// still closes the connection either way.
Future<void> applyDoneAction({
  required AppDatabase database,
  required String occurrenceId,
  Clock clock = const Clock(),
}) async {
  final chores = ChoreRepository(database);
  final households = HouseholdRepository(database);
  final settings = SettingsRepository(database);

  final household = await households.getHousehold();
  if (household == null) {
    return;
  }

  final occurrence = await chores.getOccurrence(occurrenceId);
  if (occurrence == null || occurrence.status != OccurrenceStatus.pending) {
    return;
  }

  final completedBy = await _resolveActingMemberId(
    households: households,
    settings: settings,
    householdId: household.id,
    fallback: occurrence.assignedMemberId,
  );

  final service = ChoreService(database: database, chores: chores, clock: clock);
  try {
    await service.completeOccurrence(occurrenceId, completedBy: completedBy);
  } on StateError {
    // Raced with something else closing it between the check above and
    // now (e.g. the app completed it in the same instant) — already
    // handled, nothing more to do.
  }
}

Future<String?> _resolveActingMemberId({
  required HouseholdRepository households,
  required SettingsRepository settings,
  required String householdId,
  required String? fallback,
}) async {
  final deviceSettings = await settings.ensureSettings();
  final members = await households.getMembers(householdId);
  if (members.isEmpty) {
    return fallback;
  }
  final storedId = deviceSettings.actingMemberId;
  if (storedId != null) {
    for (final member in members) {
      if (member.id == storedId) {
        return member.id;
      }
    }
  }
  for (final member in members) {
    if (member.role == MemberRole.admin) {
      return member.id;
    }
  }
  return members.first.id;
}
```

This references `ChoreRepository.getOccurrence` — check whether it already
exists (`chore_repository.dart` has `pendingOccurrenceOf`/chore-scoped
lookups per `ChoreService._findOccurrence`'s doc comment, which says
"[ChoreRepository] only exposes chore-scoped occurrence lookups"). It does
NOT exist yet as a direct-by-id lookup on the repository — `ChoreService`
has a private `_findOccurrence` doing the same raw query. Add a small
public one on `ChoreRepository` instead of duplicating the raw query a
third time:

```dart
/// Looks up an occurrence directly by id, regardless of which chore it
/// belongs to. Used by [ChoreService]'s own lifecycle methods and by
/// `NotificationActionProcessor` (no household/chore context available
/// yet at that point — it needs to look the occurrence up before it can
/// even find its chore).
Future<ChoreOccurrence?> getOccurrence(String occurrenceId) {
  return (db.select(db.choreOccurrences)..where((tbl) => tbl.id.equals(occurrenceId)))
      .getSingleOrNull();
}
```

Then simplify `ChoreService._findOccurrence` to call it (small dedup, not
strictly required by this ticket but avoids a third copy of the same raw
query — do it if touching this file anyway; skip if trying to keep the
diff minimal, either is acceptable).

**Test file** — `test/application/notification_action_processor_test.dart`,
in-memory `AppDatabase`, real repositories/services, fixed clock:

```dart
void main() {
  late AppDatabase database;
  late HouseholdRepository households;
  late ChoreRepository chores;
  late ChoreService choreService;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    households = HouseholdRepository(database);
    chores = ChoreRepository(database);
    choreService = ChoreService(
      database: database,
      chores: chores,
      clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
    );
  });

  tearDown(() => database.close());

  test('completes the occurrence, attributing to the stored acting member', () async {
    final household = await households.createLocalHousehold('Anna');
    final anna = (await households.getMembers(household.id)).single;
    // add a second member and set them as acting
    final bob = await /* however other tests add a member -- mirror member_service or chore_repository test helper */;
    await SettingsRepository(database).setActingMember(bob.id);

    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Water plants',
      startDate: PlainDate(2026, 7, 24),
      assignmentMode: AssignmentMode.anyone,
    );
    final pending = await chores.pendingOccurrenceOf(chore.id);

    await applyDoneAction(
      database: database,
      occurrenceId: pending!.id,
      clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
    );

    final closed = await chores.getOccurrence(pending.id);
    expect(closed!.status, OccurrenceStatus.done);
    expect(closed.completedBy, bob.id);
  });

  test('falls back to the first admin when no acting member is stored', () async {
    // household created via createLocalHousehold has exactly one admin
    final household = await households.createLocalHousehold('Anna');
    final anna = (await households.getMembers(household.id)).single;
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Water plants',
      startDate: PlainDate(2026, 7, 24),
      assignmentMode: AssignmentMode.anyone,
    );
    final pending = await chores.pendingOccurrenceOf(chore.id);

    await applyDoneAction(database: database, occurrenceId: pending!.id);

    final closed = await chores.getOccurrence(pending.id);
    expect(closed!.completedBy, anna.id);
  });

  test('is a silent no-op when the occurrence is already closed', () async {
    final household = await households.createLocalHousehold('Anna');
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Water plants',
      startDate: PlainDate(2026, 7, 24),
      assignmentMode: AssignmentMode.anyone,
    );
    final pending = await chores.pendingOccurrenceOf(chore.id);
    await choreService.completeOccurrence(pending!.id, completedBy: null);

    // Must not throw.
    await applyDoneAction(database: database, occurrenceId: pending.id);
  });

  test('is a silent no-op for an unknown occurrence id', () async {
    await households.createLocalHousehold('Anna');
    await applyDoneAction(database: database, occurrenceId: 'does-not-exist');
    // No throw is the assertion.
  });

  test('a recurring chore still advances/rotates normally', () async {
    // Create a rotation chore with two assignees, complete via
    // applyDoneAction, assert the new pending occurrence's assignee
    // advanced -- proves this goes through the real ChoreService path,
    // not a hand-rolled shortcut. Mirror chore_service_test.dart's
    // existing rotation-advance assertions/setup.
  });
}
```

(The exact helper for "add a second member" and "seed a rotation chore" —
mirror whatever `test/application/chore_service_test.dart` or
`test/data/repositories/chore_repository_test.dart` already use; don't
invent a new seeding pattern.)

Run — implement until green. Commit: "Add NotificationActionProcessor for the digest Done action".

---

## Task 6: the background isolate entrypoint

Not unit-tested (real isolate/plugin glue — same carve-out as other
OS-facing adapters in this codebase, e.g. `FlutterLocalNotificationsAdapter`
itself has no direct test, only `NotificationScheduler` against the fake).
Keep this file's logic to the unavoidable minimum so nothing of substance
is untested.

**Files:** Create `lib/application/notification_action_handler.dart`.

```dart
/// The background-isolate entrypoint for digest notification actions (spec
/// `docs/specs/notifications.md` N2). Deliberately minimal: all decision
/// logic lives in `notification_action_processor.dart`, which is
/// unit-tested directly; this file is untestable glue (opens/closes a real
/// drift connection, calls the real plugin, pings a real
/// `IsolateNameServer` port) and should stay that way.
library;

import 'dart:isolate';
import 'dart:ui';

import 'package:chore_app/application/notification_action_processor.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The well-known port name the main isolate registers at bootstrap (see
/// `NotificationActionSignalController`, `lib/app/providers.dart`) and this
/// handler pings after a successful action, so an already-running app
/// refreshes immediately instead of waiting for its next resume.
const String notificationActionPortName = 'chore_app.notification_action';

/// Handles a background notification-action response. Registered as
/// `onDidReceiveBackgroundNotificationResponse` in
/// `FlutterLocalNotificationsAdapter.initialize`. Must stay a top-level (or
/// static) function annotated `@pragma('vm:entry-point')` — the plugin
/// looks this callback up by its compile-time handle from a fresh isolate
/// that has never run any of this app's other code.
@pragma('vm:entry-point')
Future<void> notificationActionCallbackDispatcher(
  NotificationResponse response,
) async {
  if (response.actionId != 'done') {
    return;
  }
  final occurrenceId = response.payload;
  if (occurrenceId == null) {
    return;
  }

  DartPluginRegistrant.ensureInitialized();

  final database = AppDatabase(openConnection());
  try {
    await applyDoneAction(database: database, occurrenceId: occurrenceId);
  } finally {
    await database.close();
  }

  final notificationId = response.id ?? digestNotificationId;
  await FlutterLocalNotificationsPlugin().cancel(id: notificationId);

  IsolateNameServer.lookupPortByName(notificationActionPortName)?.send(null);
}
```

`digestNotificationId` is already exported from `notification_scheduler.dart`
— import it. `DartPluginRegistrant.ensureInitialized()` mirrors the
standard pattern other Flutter background-isolate plugins (`workmanager`,
`geolocator`) use to make sure THIS isolate's own plugin bindings are set
up before touching any plugin (belt-and-braces alongside the
`AppDelegate.swift`/manifest wiring in Tasks 8/9 — the latter registers the
*Flutter engine's* plugins, this registers *this isolate's* Dart-side
bindings).

Commit: "Add the background notification-action entrypoint".

---

## Task 7: `NotificationActionSignalController` — the receiving side

TDD: this one CAN be tested — `IsolateNameServer` is a same-process,
same-VM registry, so a test can look up the port the controller registered
and `.send()` to it directly, no real isolate needed.

**Files:**
- Create `test/app/notification_action_signal_test.dart`
- Edit `lib/app/providers.dart`
- Edit `main.dart`

**Test** — mirror `digest_reschedule_test.dart`'s structure:

```dart
import 'dart:isolate';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/notification_action_handler.dart';
import 'package:chore_app/data/db/app_database.dart';
// ... other imports mirroring digest_reschedule_test.dart ...

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets(
    'a ping invalidates the occurrence streams and triggers a digest recompute',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 7))),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      );
      addTearDown(container.dispose);
      await container.read(householdRepositoryProvider).createLocalHousehold('Me');

      container.read(digestRescheduleControllerProvider);
      container.read(notificationActionSignalControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);
      plugin.scheduledCalls.clear();

      // Simulate what the background isolate does after completing an
      // occurrence: a fresh write directly against the SAME database (a
      // real cross-connection scenario isn't reproducible in-process, but
      // the controller's job starts at "a ping arrived" regardless of who
      // sent it -- this proves the ping->recompute wiring, matching what
      // Task 3 already proved for the counting itself).
      final today = PlainDate.fromDateTime(container.read(clockProvider).now());
      await container.read(choreServiceProvider).createChore(
        householdId: householdId,
        title: 'Water the plants',
        startDate: today,
        assignmentMode: AssignmentMode.anyone,
      );

      final port = IsolateNameServer.lookupPortByName(notificationActionPortName);
      expect(port, isNotNull, reason: 'controller must register the port at construction');
      port!.send(null);

      // The ping's recompute goes through the same debounced path.
      await tester.pump(digestRescheduleDebounce);
      expect(plugin.scheduledCalls, isNotEmpty);

      await database.close();
    },
  );
}
```

Run — fails (no such provider/port registered yet). Implement:

**`lib/app/providers.dart`** — new controller, same shape as
`DigestRescheduleController`/`CatchUpController`:

```dart
/// Owns the receiving side of the background-isolate "an action fired"
/// signal (spec `docs/specs/notifications.md` N2): registers a well-known
/// `IsolateNameServer` port at construction, and on any ping, invalidates
/// the occurrence-list streams (so a foreground screen refreshes even
/// though the write came through a SEPARATE `AppDatabase` connection —
/// see `lib/application/notification_action_handler.dart`'s doc comment
/// for why that's necessary) and re-runs the same recompute/push calls
/// `main.dart`'s app-resume observer already makes.
///
/// Same "never read from the widget tree" discipline as
/// [DigestRescheduleController]/[CatchUpController]/[SyncEngineController] —
/// see their shared doc comments. Constructed once, from `main.dart`,
/// before `runApp`.
class NotificationActionSignalController {
  /// Registers the port and starts listening immediately.
  NotificationActionSignalController(this._ref) {
    IsolateNameServer.removePortNameMapping(notificationActionPortName);
    IsolateNameServer.registerPortWithName(
      _receivePort.sendPort,
      notificationActionPortName,
    );
    _subscription = _receivePort.listen((_) => _onPing());
  }

  final Ref _ref;
  final ReceivePort _receivePort = ReceivePort();
  late final StreamSubscription<dynamic> _subscription;

  /// Unregisters the port and stops listening. Called via `ref.onDispose`.
  void dispose() {
    _subscription.cancel();
    _receivePort.close();
    IsolateNameServer.removePortNameMapping(notificationActionPortName);
  }

  void _onPing() {
    _ref
      ..invalidate(pendingOccurrencesProvider)
      ..invalidate(closedTodayOccurrencesProvider);
    _ref.read(digestRescheduleControllerProvider).triggerRecompute();
    // `triggerOnResume()` returns `void` and already wraps its own
    // fire-and-forget push internally (see its doc comment) — no
    // `unawaited` needed at this call site either, mirroring how
    // `main.dart`'s app-resume observer calls the exact same method.
    _ref.read(syncEngineControllerProvider).triggerOnResume();
  }
}

final notificationActionSignalControllerProvider =
    Provider<NotificationActionSignalController>((ref) {
  final controller = NotificationActionSignalController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
```

Needs `import 'dart:isolate';` and the handler file's port-name constant.

**`main.dart`:** construct alongside the other three, before `runApp`:

```dart
final digestController = container.read(digestRescheduleControllerProvider);
final catchUpController = container.read(catchUpControllerProvider);
final syncEngineController = container.read(syncEngineControllerProvider);
container.read(notificationActionSignalControllerProvider);
```

(No lifecycle-observer wiring needed for this one — unlike the other
three, it has no "on resume" behavior; it only reacts to pings. Just
needs to be constructed once so `ref.onDispose` doesn't fire until the
container itself is torn down.)

Run test — pass. Commit: "Wire the notification-action cross-isolate ping to a UI refresh".

---

## Task 8: Android manifest receiver

**Files:** Edit `android/app/src/main/AndroidManifest.xml`.

```xml
<!-- flutter_local_notifications (spec docs/specs/notifications.md N2):
     required for notification ACTION buttons (the digest's 'Done' action)
     to reach the background isolate handler. No new permission needed --
     this is a component declaration, not a permission. -->
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
```

Place it next to the existing `ScheduledNotificationReceiver`/
`ScheduledNotificationBootReceiver` declarations. Not unit-testable;
verify manually (Task 10).

Commit: "Register the notification-action broadcast receiver on Android".

---

## Task 9: iOS AppDelegate wiring

**Files:** Edit `ios/Runner/AppDelegate.swift`.

```swift
import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Required so the BACKGROUND engine spawned for notification actions
    // (spec docs/specs/notifications.md N2) registers every other plugin
    // (including drift's sqlite3 plugin) into itself -- without this the
    // background isolate's AppDatabase(openConnection()) call fails
    // silently. Verified against flutter_local_notifications' own example
    // AppDelegate.swift. Must run BEFORE the GeneratedPluginRegistrant call
    // below.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

Not unit-testable. Verify manually (Task 10).

Commit: "Wire iOS background-isolate plugin registration for notification actions".

---

## Task 10: manual on-device verification (not automatable)

Not a code task — a checklist to run once per platform before this ships,
mirroring the spec's existing "fire-time verification is NOT E2E-testable"
carve-out:

- [ ] Android emulator/device: create exactly one due-today chore, wait
      for (or force-trigger, e.g. by temporarily setting the digest time to
      a minute away) the digest, confirm the "Done" button appears, tap it
      **with the app fully swiped away**, confirm the chore shows as done
      on next app open.
- [ ] Same, with the app **open in the foreground** when the notification
      shade is pulled down and "Done" tapped — confirm the chores list
      updates within about half a second without the user doing anything
      else (proves the `IsolateNameServer` ping path, not just the
      app-resume path).
- [ ] Same two checks on iOS simulator/device.
- [ ] Two due-today chores: confirm NO action button appears on the
      digest, tapping the notification body still opens the app.
- [ ] Tap "Done" a second time on an already-actioned/removed notification
      (e.g. via a stale notification-shade entry, if reproducible) — confirm
      no crash, no duplicate completion.

Not committed as code; record results in the PR description when this
plan's work is submitted for review.

---

## Task list summary

1. Spec: extend `docs/specs/notifications.md` (N2 section).
2. `DigestPlan.soleOccurrenceId` (pure domain).
3. `DigestRescheduleController` captures it.
4. `NotificationScheduler`/`DigestNotificationPlugin`/adapter: actionable
   scheduling, iOS category, l10n.
5. `NotificationActionProcessor` (+ `HouseholdRepository.getMembers`,
   `ChoreRepository.getOccurrence`) — the unit-tested completion logic.
6. Background isolate entrypoint (untested glue).
7. `NotificationActionSignalController` — cross-isolate ping receiver.
8. Android manifest receiver.
9. iOS AppDelegate wiring.
10. Manual on-device verification checklist.

10 tasks, 2 of which (8, 9) are single-file platform config edits and one
(10) is a manual checklist — 7 tasks carry real TDD cycles.
