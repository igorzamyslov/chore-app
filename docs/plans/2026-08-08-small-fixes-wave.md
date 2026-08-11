# Small Fixes Wave (E-1..E-5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land five small, independent fixes from `docs/backlog.md` §E (E-1..E-5) — hardcoded notification-channel strings, a dead-end startup error screen, a missing privacy disclosure sentence, missing `Recurrence` equality, and stale pubspec metadata — each as its own commit.

**Architecture:** No new subsystems. Each task touches 1-3 existing files: `lib/application/notification_scheduler.dart` (+ its fake + tests), `lib/app/app.dart` + `lib/features/settings/reset_flow.dart` (+ `test/widget_test.dart`), two ARB files, `lib/domain/recurrence/recurrence.dart` (+ its test), and `pubspec.yaml`.

**Tech Stack:** Flutter/Dart, Riverpod, drift, `flutter_local_notifications`, gen_l10n (ARB), `flutter_test` widget tests.

## Global Constraints

- Every user-visible string goes through gen_l10n: add to `lib/l10n/app_en.arb` (template, with `@key` description block) AND `lib/l10n/app_de.arb` (du-form, no `@key` block needed — matches this repo's existing ARB convention). Never inline English.
- Every interactive widget gets a stable id via `semantic()`; tests select only by id or text, matching the existing suite's style.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed clock, overriding ONLY `appDatabaseProvider`/`clockProvider` plus documented seams (e.g. `digestNotificationPluginProvider`). Never mock repositories or services.
- TDD: write a failing test, run it, implement, run again, commit. One commit per task below.
- `flutter analyze --fatal-infos --fatal-warnings` and `flutter test` both run as pre-commit hooks (lefthook) — running them is how each task is verified; this plan does not re-list that as a separate step per task, it's implied by "run the tests."
- `pubspec.yaml`'s `generate: true` means `flutter gen-l10n` runs automatically as part of `flutter test`/`flutter analyze`/`flutter build` — no separate manual generation step after editing the ARB files.
- Public members need doc comments (very_good_analysis, `--fatal-infos`).

## Judgment calls made while planning (not blocking, documented per the ticket's request)

- **E-1 channel migration:** Android caches a channel's name/description at creation and never updates them for an existing channel id. Rather than a stateful "have we migrated yet" flag, this plan **mints a new channel id** (`digest` → `digest_v2`) so every user gets the newly localized name/description the moment they update, with zero migration-state bookkeeping (a brand-new id has never been created on their device, so `flutter_local_notifications` creates it fresh). The old `digest` channel is explicitly deleted (best-effort, safe to repeat every launch) so it doesn't linger as a dead, English-named entry in system Settings → Notifications. Trade-off accepted: any user who had customized the old channel's importance/sound in system settings loses that customization once — acceptable for a low-severity, cosmetic finding.
- **E-2 friendly error copy:** the existing `appBootstrapError(error)` string (which interpolates the raw exception) is kept, but demoted to a small, muted detail line — useful for a user to screenshot into a GitHub issue on this open-source, no-crash-reporting app — under a new, non-technical headline that is now the actually-readable message.
- **E-2 retry semantics:** retry invalidates the *specific* provider each error screen is watching (`householdGateProvider` at the welcome-gate level, `bootstrapProvider` at the post-gate level) rather than tearing down `appDatabaseProvider` — this matches the audit's own suggested fix and keeps the retry meaningfully testable (see Task 5). It won't help with a truly corrupted database file, which is exactly why the reset escape hatch exists alongside it.

## Resolved product decisions

### D-E3: exact wording of the in-app privacy disclosure sentence — RESOLVED

`settingsAccountIntro` currently reads "Sign in to sync your household across your devices." — accurate but silent on *what* is sent. Field feedback C1 (`docs/feedback/2026-08-01-field-feedback.md`) calls for "one plain sentence... stating what is stored and where," gated on landing before any public sync announcement (that gate has passed: PRIVACY.md already shipped and describes it in full).

This plan's original recommendation ("...on our server...") was rejected: this is an open-source, F-Droid-distributed, self-hostable app (`PRIVACY.md` says so explicitly), and "our server" both reads as false for a self-hoster and implies an operator relationship the project has deliberately not claimed. It also omitted the single most useful fact for someone deciding whether to sign in at all: that not signing in keeps everything on the device.

**Resolved wording (two sentences — a disclosure, not a privacy policy):**
> "Signing in stores your email and your household's data — chores, shopping list, members — on the sync server, so your devices stay in step. Without an account, everything stays on this device."

This is what Task 3 implements below. Both call sites (`_SignedOutForm` in `account_section.dart` and `_buildEmailStep` in `welcome_join_page.dart`) render `settingsAccountIntro` as a plain, unconstrained `Text(...)` — no `maxLines`, no `overflow`, no fixed-height container — inside a scrolling column in both cases, so the extra sentence has nowhere to be truncated or to force layout it isn't. One shared key remains correct for both surfaces; no split is needed.

---

## Task 1: `Recurrence` equality (E-4)

**Files:**
- Modify: `lib/domain/recurrence/recurrence.dart`
- Test: `test/domain/recurrence/recurrence_test.dart`

**Interfaces:**
- Produces: `Recurrence.operator==` and `Recurrence.hashCode`, value-equality across all seven fields (`interval`, `unit`, `anchor`, `weekdays` as an unordered set, `monthlyMode`, `monthlyOrdinal`, `monthlyWeekday`).

- [ ] **Step 1: Write the failing tests**

Add a new group at the end of `test/domain/recurrence/recurrence_test.dart` (before the final closing brace of `main()`):

```dart
  group('equality', () {
    test('two rules built with identical fields are equal', () {
      final a = Recurrence.everyNDays(3);
      final b = Recurrence.everyNDays(3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('weekdays equality is order-independent', () {
      final a = Recurrence.weekly(weekdays: {1, 3, 5});
      final b = Recurrence.weekly(weekdays: {5, 3, 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing interval makes rules unequal', () {
      expect(Recurrence.everyNDays(3), isNot(Recurrence.everyNDays(4)));
    });

    test('differing anchor makes rules unequal', () {
      expect(
        Recurrence.everyNDays(3, anchor: RecurrenceAnchor.schedule),
        isNot(Recurrence.everyNDays(3, anchor: RecurrenceAnchor.completion)),
      );
    });

    test('differing weekdays makes rules unequal', () {
      expect(
        Recurrence.weekly(weekdays: {1, 3}),
        isNot(Recurrence.weekly(weekdays: {1, 4})),
      );
    });

    test('differing monthly ordinal/weekday makes rules unequal', () {
      expect(
        Recurrence.monthlyOnNthWeekday(1, 6),
        isNot(Recurrence.monthlyOnNthWeekday(2, 6)),
      );
      expect(
        Recurrence.monthlyOnNthWeekday(1, 6),
        isNot(Recurrence.monthlyOnNthWeekday(1, 7)),
      );
    });

    test('is not equal to an unrelated object', () {
      // ignore: unrelated_type_equality_checks
      expect(Recurrence.everyNDays(3) == 'not a recurrence', isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/domain/recurrence/recurrence_test.dart`
Expected: FAIL on every new test in the `equality` group — `Recurrence` currently uses identity equality (default `Object.==`), so `a == b` is false even for field-identical instances.

- [ ] **Step 3: Implement `==`/`hashCode`**

At the very top of `lib/domain/recurrence/recurrence.dart`, before the existing `/// The unit of time...` doc comment, add the same convention `digest_planner.dart`/`plain_date.dart` use (no `package:meta`, no `@immutable`):

```dart
// `Recurrence` has only final fields and no mutating members, so it is
// effectively immutable; we deliberately don't import `package:meta` (lib
// code is dart:core only) to add the `@immutable` annotation the lint below
// wants (same convention as `plain_date.dart` and `digest_planner.dart`).
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

```

At the end of the `Recurrence` class body, right after the closing brace of `toJson()` and before the class's own closing `}`, add:

```dart

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Recurrence &&
        other.interval == interval &&
        other.unit == unit &&
        other.anchor == anchor &&
        other.monthlyMode == monthlyMode &&
        other.monthlyOrdinal == monthlyOrdinal &&
        other.monthlyWeekday == monthlyWeekday &&
        _setEquals(other.weekdays, weekdays);
  }

  @override
  int get hashCode {
    // Sets aren't order-stable, so a plain `Object.hash(weekdays, ...)`
    // would hash `{1, 3}` and `{3, 1}` differently even though they compare
    // equal above. XOR-folding each element's hash is order-independent,
    // matching the equality contract (equal objects must have equal
    // hashes) without importing `package:collection` for `SetEquality`.
    final weekdaysHash = weekdays.fold<int>(0, (acc, day) => acc ^ day.hashCode);
    return Object.hash(
      interval,
      unit,
      anchor,
      monthlyMode,
      monthlyOrdinal,
      monthlyWeekday,
      weekdaysHash,
    );
  }

  static bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.every(b.contains);
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/recurrence/recurrence_test.dart`
Expected: PASS, all tests including the new `equality` group.

Also run the full suite once to confirm nothing that depended on `Recurrence`'s old identity-equality (e.g. anything using it as a `Map`/`Set` key) regressed:

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/recurrence/recurrence.dart test/domain/recurrence/recurrence_test.dart
git commit -m "Add value equality to Recurrence"
```

---

## Task 2: `pubspec.yaml` description (E-5)

**Files:**
- Modify: `pubspec.yaml:2`

**Interfaces:** None — metadata only, nothing else in the plan depends on this.

- [ ] **Step 1: Edit the description**

In `pubspec.yaml`, change line 2 from:

```yaml
description: "A new Flutter project."
```

to:

```yaml
description: "Famdo — family chores and shopping, shared and fair. Local-first, open source, optional sync."
```

(Matches `README.md`'s framing and `fastlane/metadata/android/en-US/short_description.txt`'s "Family chores and shopping, shared and fair.", extended to the one line a `pubspec.yaml` description is meant to be.)

- [ ] **Step 2: Verify**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: PASS (this is metadata; nothing should break, but this confirms the YAML is still well-formed).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "Write a real pubspec description"
```

---

## Task 3: In-app privacy disclosure sentence (E-3)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

No Dart code changes: both `lib/features/settings/account_section.dart`'s `_SignedOutForm` (line 328: `Text(l10n.settingsAccountIntro)`) and `lib/features/onboarding/welcome_join_page.dart`'s `_buildEmailStep` (line 178: `Text(l10n.settingsAccountIntro)`) already render the same shared key — editing its value covers both surfaces in one place.

**Interfaces:** None new — reuses the existing `settingsAccountIntro` getter.

- [ ] **Step 1: Confirm no test asserts the exact old string**

Run: `grep -rn "Sign in to sync your household" test/`
Expected: no matches (the two widget-test files that touch this screen, `test/features/settings/account_section_test.dart` and `test/features/onboarding/welcome_join_test.dart`, select the email field by semantic id `settings.account.email`/`welcome.join.email`, never by this text — confirmed during planning).

- [ ] **Step 2: Update the English template**

In `lib/l10n/app_en.arb`, change (around line 1058):

```json
  "settingsAccountIntro": "Sign in to sync your household across your devices.",
```

to:

```json
  "settingsAccountIntro": "Signing in stores your email and your household's data — chores, shopping list, members — on the sync server, so your devices stay in step. Without an account, everything stays on this device.",
```

(The `@settingsAccountIntro` description block immediately below stays unchanged — it already accurately describes where this renders. Two sentences, not one: see the resolved `D-E3` decision above for why the second sentence — what happens WITHOUT an account — is load-bearing, not filler.)

- [ ] **Step 3: Update the German translation**

In `lib/l10n/app_de.arb`, change (around line 237):

```json
  "settingsAccountIntro": "Melde dich an, um deinen Haushalt geräteübergreifend zu synchronisieren.",
```

to (a natural du-form rendering, not a transliteration — "auf dem gleichen Stand bleiben" is the idiomatic German for two devices "staying in step/in sync", matching how `settingsAccountLinkedSubtitle` and neighboring strings already phrase things):

```json
  "settingsAccountIntro": "Beim Anmelden werden deine E-Mail-Adresse und die Daten deines Haushalts — Aufgaben, Einkaufsliste, Mitglieder — auf dem Sync-Server gespeichert, damit deine Geräte auf dem gleichen Stand bleiben. Ohne Konto bleibt alles auf diesem Gerät.",
```

- [ ] **Step 4: Run the existing widget tests for both surfaces**

Run: `flutter test test/features/settings/account_section_test.dart test/features/onboarding/welcome_join_test.dart`
Expected: PASS unchanged (neither file asserts this string's content).

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb
git commit -m "State what sync stores in the sign-in disclosure line"
```

---

## Task 4: Localize the notification channel name/description (E-1)

**Files:**
- Modify: `lib/application/notification_scheduler.dart`
- Modify: `test/application/fake_digest_notification_plugin.dart`
- Modify: `test/application/notification_scheduler_test.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

**Interfaces:**
- Modifies `DigestNotificationPlugin.zonedSchedule`'s signature: adds `required String channelName` and `required String channelDescription`.
- Adds `DigestNotificationPlugin.deleteLegacyDigestChannel()`.
- Adds top-level `const String legacyDigestChannelId = 'digest'` (existing `digestChannelId` becomes `'digest_v2'`).
- Adds `AppLocalizations.notificationChannelDigestName` / `.notificationChannelDigestDescription` getters (generated from the ARB additions below).

- [ ] **Step 1: Add the ARB strings**

In `lib/l10n/app_en.arb`, immediately after the `@appBootstrapError` block (after line 16, before the blank line / `notificationDigestDueOnly` block), add:

```json

  "notificationChannelDigestName": "Daily summary",
  "@notificationChannelDigestName": {
    "description": "Android notification channel name for the daily digest (shown in system Settings -> Apps -> Notifications). Cached by Android at channel-creation time -- see docs/plans/2026-08-08-small-fixes-wave.md Task 4."
  },
  "notificationChannelDigestDescription": "The once-a-day chores digest notification.",
  "@notificationChannelDigestDescription": {
    "description": "Android notification channel description for the daily digest, shown alongside notificationChannelDigestName in system Settings."
  },
```

In `lib/l10n/app_de.arb`, immediately after the `appBootstrapError` line (line 4), add:

```json
  "notificationChannelDigestName": "Tägliche Zusammenfassung",
  "notificationChannelDigestDescription": "Die einmal täglich versendete Aufgaben-Zusammenfassung.",
```

- [ ] **Step 2: Write the failing scheduler tests**

In `test/application/notification_scheduler_test.dart`, add a new group after the existing `scheduleDigest` group (after its closing `});` around line 112, before `group('cancelDigest', ...)`):

```dart
  group('notification channel', () {
    final plan = DigestPlan(
      fireAt: DateTime(2026, 7, 25, 8),
      dueTodayCount: 3,
      overdueCount: 0,
    );

    test('schedules with the localized channel name and description', () async {
      await scheduler.scheduleDigest(plan);
      expect(plugin.scheduledCalls.single.channelName, 'Daily summary');
      expect(
        plugin.scheduledCalls.single.channelDescription,
        'The once-a-day chores digest notification.',
      );
    });

    test('German locale produces German channel copy', () async {
      final germanScheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await germanScheduler.scheduleDigest(plan);
      expect(
        plugin.scheduledCalls.single.channelName,
        'Tägliche Zusammenfassung',
      );
      expect(
        plugin.scheduledCalls.single.channelDescription,
        'Die einmal täglich versendete Aufgaben-Zusammenfassung.',
      );
    });

    test(
      'ensureInitialized deletes the legacy (pre-l10n) channel exactly '
      'once across repeated calls, so it stops lingering as a dead, '
      'English-named entry in system Settings',
      () async {
        await scheduler.ensureInitialized();
        await scheduler.ensureInitialized();
        await scheduler.ensureInitialized();
        expect(plugin.deleteLegacyDigestChannelCallCount, 1);
      },
    );
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/application/notification_scheduler_test.dart`
Expected: compile error — `ScheduledCall` has no `channelName`/`channelDescription` getters yet, and `FakeDigestNotificationPlugin` has no `deleteLegacyDigestChannelCallCount`/`deleteLegacyDigestChannel`. This is expected at this step (the fake needs updating first — proceed to Step 4, then re-run).

- [ ] **Step 4: Update the fake plugin**

Replace the full contents of `test/application/fake_digest_notification_plugin.dart` with:

```dart
/// A recording fake of [DigestNotificationPlugin] for scheduler and
/// reschedule-on-mutation tests (spec `docs/specs/notifications.md`
/// testing section): no real OS notification channel is ever touched.
library;

import 'package:chore_app/application/notification_scheduler.dart';

/// One recorded call to [FakeDigestNotificationPlugin.zonedSchedule].
class ScheduledCall {
  /// Creates a recorded call.
  const ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.channelName,
    required this.channelDescription,
  });

  /// The notification id passed to `zonedSchedule`.
  final int id;

  /// The notification title passed to `zonedSchedule`.
  final String title;

  /// The notification body passed to `zonedSchedule`.
  final String body;

  /// The fire time passed to `zonedSchedule`.
  final DateTime fireAt;

  /// The (localized) Android notification channel name passed to
  /// `zonedSchedule` (E-1, spec `docs/backlog.md`).
  final String channelName;

  /// The (localized) Android notification channel description passed to
  /// `zonedSchedule` (E-1, spec `docs/backlog.md`).
  final String channelDescription;

  @override
  String toString() =>
      'ScheduledCall(id: $id, title: $title, body: $body, fireAt: $fireAt, '
      'channelName: $channelName, channelDescription: $channelDescription)';
}

/// A fake [DigestNotificationPlugin] that records every call instead of
/// touching a real notification channel.
class FakeDigestNotificationPlugin implements DigestNotificationPlugin {
  /// Whether [isPermissionGranted] should report the permission as
  /// granted; flip this in a test to simulate a denied permission.
  bool permissionGranted = true;

  /// How many times [initialize] was called.
  int initializeCallCount = 0;

  /// How many times [requestPermission] was called.
  int requestPermissionCallCount = 0;

  /// How many times [cancel] was called.
  int cancelCallCount = 0;

  /// How many times [deleteLegacyDigestChannel] was called.
  int deleteLegacyDigestChannelCallCount = 0;

  /// Every [zonedSchedule] call, in order.
  final List<ScheduledCall> scheduledCalls = [];

  @override
  Future<void> initialize() async {
    initializeCallCount++;
  }

  @override
  Future<void> requestPermission() async {
    requestPermissionCallCount++;
  }

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelName,
    required String channelDescription,
  }) async {
    scheduledCalls.add(
      ScheduledCall(
        id: id,
        title: title,
        body: body,
        fireAt: fireAt,
        channelName: channelName,
        channelDescription: channelDescription,
      ),
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelCallCount++;
  }

  @override
  Future<void> deleteLegacyDigestChannel() async {
    deleteLegacyDigestChannelCallCount++;
  }
}
```

- [ ] **Step 5: Run tests to verify they still fail (for the right reason)**

Run: `flutter test test/application/notification_scheduler_test.dart`
Expected: FAIL — now a clean compile against the fake's new shape, but `NotificationScheduler`/`DigestNotificationPlugin` in `lib/` don't declare `channelName`/`channelDescription`/`deleteLegacyDigestChannel` yet, so this fails to compile against `lib/application/notification_scheduler.dart` instead. Proceed to Step 6.

- [ ] **Step 6: Update `lib/application/notification_scheduler.dart`**

Change the two channel-id constants (lines 16-19):

```dart
/// The Android notification channel the digest notification is posted on.
///
/// `_v2` (rather than reusing the original `'digest'` id): Android caches a
/// channel's name/description at CREATION time and never updates them for
/// an existing id, even if a later app version passes a different name to
/// the same id -- there is no "rename" operation. Minting a new id is how
/// every user picks up the newly localized name/description (E-1, spec
/// `docs/backlog.md`) without any migration-state bookkeeping: the id has
/// never existed on their device, so the plugin creates it fresh with
/// today's (localized) name on the very next schedule. See
/// [legacyDigestChannelId] for the cleanup half of this.
const String digestChannelId = 'digest_v2';

/// The pre-l10n channel id, superseded by [digestChannelId]. Kept only so
/// [NotificationScheduler.ensureInitialized] can delete it, so it doesn't
/// linger as a dead, English-named entry in system Settings ->
/// Notifications for users who had it created before this fix shipped.
const String legacyDigestChannelId = 'digest';
```

Update the `DigestNotificationPlugin` interface's `zonedSchedule` method (replace the existing one, lines 44-52 in the original file):

```dart
  /// Schedules a one-shot notification titled [title] with body [body], to
  /// fire at [fireAt] (device-local wall-clock time), replacing any
  /// previously-scheduled notification with the same [id]. [channelName]
  /// and [channelDescription] are used only the first time this app ever
  /// creates the Android channel [digestChannelId] -- see that constant's
  /// doc comment for why a later call can't just rename it.
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelName,
    required String channelDescription,
  });

  /// Deletes the legacy [legacyDigestChannelId] Android channel, if it
  /// still exists on this device. A no-op on platforms without a channel
  /// concept (iOS/desktop) and safe to call repeatedly -- deleting an
  /// already-deleted (or never-created) channel does nothing.
  Future<void> deleteLegacyDigestChannel();
```

Update `FlutterLocalNotificationsAdapter.zonedSchedule` (replace the existing method body, lines 124-168 in the original file):

```dart
  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelName,
    required String channelDescription,
  }) async {
    // `tz.UTC` is a built-in constant that needs no `initializeTimeZones()`
    // database load. `TZDateTime.from` converts by absolute instant
    // (`fireAt.toUtc()`), not by reinterpreting wall-clock fields, so the
    // `Location` passed here doesn't affect *when* this actually fires —
    // only how it would be *displayed*, which nothing downstream of this
    // does. `fireAt` itself already carries the correct UTC offset for its
    // own calendar date (including across a DST transition between now and
    // then), computed by Dart's own local `DateTime`; no device-timezone
    // *name* lookup (e.g. a `flutter_timezone` dependency, which the
    // `timezone` package's own README recommends only because it needs a
    // named `Location` for *recurring* `matchDateTimeComponents` alarms) is
    // needed for the one-shot schedule this app always uses — every digest
    // is cancelled and freshly re-scheduled on its own (spec architecture
    // #2), never left to the OS to repeat.
    final scheduledDate = tz.TZDateTime.from(fireAt, tz.UTC);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      // `Importance`/`Priority` default to `defaultImportance`/
      // `defaultPriority` already (a summary, not an alarm — spec
      // architecture #3), so neither is passed explicitly here.
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          digestChannelId,
          channelName,
          channelDescription: channelDescription,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Deliberate spec decision: inexact scheduling avoids the
      // SCHEDULE_EXACT_ALARM permission dance entirely — a morning digest
      // doesn't need second-precision. Do NOT "upgrade" this to an exact
      // schedule mode.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> deleteLegacyDigestChannel() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.deleteNotificationChannel(legacyDigestChannelId);
  }
```

(This replaces the old `cancel` override too, only to relocate `deleteLegacyDigestChannel` directly below it — `cancel`'s own body is unchanged.)

Update `NotificationScheduler.ensureInitialized` (replace lines 200-206):

```dart
  /// Initializes the underlying plugin. Idempotent: only the first call
  /// does anything. Safe to call on every bootstrap/resume.
  ///
  /// Also deletes the legacy [legacyDigestChannelId] Android channel (E-1)
  /// -- gated behind the same [_initialized] flag as the plugin init call
  /// above it, so this runs at most once per process, which is all it
  /// needs (the delete is a no-op forever after the channel is actually
  /// gone).
  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await plugin.initialize();
    await plugin.deleteLegacyDigestChannel();
    _initialized = true;
  }
```

Update `NotificationScheduler.scheduleDigest` (replace lines 222-231):

```dart
  Future<void> scheduleDigest(DigestPlan plan) async {
    await ensureInitialized();
    final l10n = lookupAppLocalizations(localeResolver());
    await plugin.zonedSchedule(
      id: digestNotificationId,
      title: l10n.appTitle,
      body: _digestBody(l10n, plan),
      fireAt: plan.fireAt,
      channelName: l10n.notificationChannelDigestName,
      channelDescription: l10n.notificationChannelDigestDescription,
    );
  }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/application/notification_scheduler_test.dart`
Expected: PASS, all tests including the new `notification channel` group.

Then run the full suite (this file's `digestChannelId`/`legacyDigestChannelId` constants and the `DigestNotificationPlugin` interface change are only consumed inside this file and its test/fake, but confirm nothing else in `lib/app/providers.dart` broke):

Run: `flutter test`
Expected: PASS.

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: PASS (no unused-parameter or missing-doc-comment warnings on the new interface members).

- [ ] **Step 8: Commit**

```bash
git add lib/application/notification_scheduler.dart \
  test/application/fake_digest_notification_plugin.dart \
  test/application/notification_scheduler_test.dart \
  lib/l10n/app_en.arb lib/l10n/app_de.arb
git commit -m "Localize the digest notification channel name and description"
```

---

## Task 5: Startup error screen — retry and reset escape hatch (E-2)

**Files:**
- Modify: `lib/features/settings/reset_flow.dart` (extract the shared confirm-and-reset flow)
- Modify: `lib/app/app.dart` (`_ErrorScaffold`, `ChoreApp.build`, `_Bootstrapped.build`)
- Modify: `test/widget_test.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

**Interfaces:**
- Produces: top-level `Future<void> confirmAndResetAppData(BuildContext context, WidgetRef ref, {required bool linked})` in `lib/features/settings/reset_flow.dart` — runs the existing double-confirm dialog flow, then `resetAppData`, catching and reporting any failure from the reset itself.
- Consumes (Task 5 depends on nothing from Tasks 1-4; independent).
- New semantic ids: `app.bootstrap_error.retry`, `app.bootstrap_error.reset` (the existing `app.bootstrap_error` id is kept, now on the de-emphasized detail text).

- [ ] **Step 1: Write the failing widget test**

In `test/widget_test.dart`, replace the existing `'bootstrap error renders the error state'` test (lines 48-72) with:

```dart
  testWidgets(
    'bootstrap error renders retry and reset actions (spec '
    'docs/feedback/2026-08-08-prerelease-audit.md P3/S2: a database-open '
    'failure must not brick the app permanently)',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      // Establishes the connection, then severs it, so the very first
      // bootstrap query throws — simulating a startup failure without
      // mocking anything.
      await database.select(database.households).getSingleOrNull();
      await database.close();

      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(
              Clock.fixed(DateTime(2026, 7, 24, 9)),
            ),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('app.bootstrap_error'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('app.bootstrap_error.retry'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('app.bootstrap_error.reset'),
        findsOneWidget,
      );

      // Retry re-invalidates the gate provider: the database is still
      // closed, so the SAME error screen must reappear rather than crash
      // the test with an unhandled exception.
      await tester.tap(find.bySemanticsIdentifier('app.bootstrap_error.retry'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('app.bootstrap_error'), findsOneWidget);

      // The reset escape hatch opens the SAME double-confirm dialog
      // Settings uses (`settings.reset.*` ids); with the database closed,
      // the wipe itself fails, which must surface as an inline message
      // rather than crash the app.
      await tester.tap(find.bySemanticsIdentifier('app.bootstrap_error.reset'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.reset.confirm1'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't reset your data. Please try again."),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL — `app.bootstrap_error.retry` and `app.bootstrap_error.reset` don't exist yet.

- [ ] **Step 3: Add the new ARB strings**

In `lib/l10n/app_en.arb`, immediately after the `@appBootstrapError` block (same insertion point Task 4 used — if Task 4 already ran, add this right after Task 4's `notificationChannelDigestDescription` block instead; either order is fine as long as both end up present), add:

```json
  "appBootstrapErrorTitle": "We couldn't open your data",
  "@appBootstrapErrorTitle": {
    "description": "Headline shown full-screen when the app fails to bootstrap, above the technical appBootstrapError detail line."
  },
```

Near `settingsResetConfirm2Action` (around line 1394), add:

```json
  "settingsResetError": "Couldn't reset your data. Please try again.",
  "@settingsResetError": {
    "description": "Shown (as a snackbar) when the reset-app-data wipe itself throws -- e.g. the database connection that triggered the startup error screen is also what reset needs to write through."
  },
```

In `lib/l10n/app_de.arb`, immediately after `appBootstrapError` (line 4 or wherever Task 4 left it), add:

```json
  "appBootstrapErrorTitle": "Deine Daten konnten nicht geöffnet werden",
```

Near `settingsResetConfirm2Action` (around line 305), add:

```json
  "settingsResetError": "Zurücksetzen ist fehlgeschlagen. Versuch es noch mal.",
```

- [ ] **Step 4: Extract the shared reset flow in `reset_flow.dart`**

Replace the full contents of `lib/features/settings/reset_flow.dart` with:

```dart
/// The Settings tab's destructive 'Reset app data' row and its
/// double-confirm flow (spec `docs/specs/polish-round-1.md` B2), the last
/// row in the Data group, immediately under the export row (spec
/// `docs/specs/theme-v2.md` §4.2; spec
/// `docs/feedback/2026-08-01-field-feedback.md` B4/F7).
///
/// The first dialog's body is state-aware (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A6): a linked device's "there is
/// no cloud backup" claim was FALSE (the household lives on the server;
/// signing in again reconnects it) -- [ResetDataTile] reads
/// [settingsProvider]'s `syncHouseholdId` to pick the right copy.
///
/// [confirmAndResetAppData] is the flow itself, pulled out as a top-level
/// function so it can also be reached from the startup error screen's
/// escape hatch (`lib/app/app.dart`'s `_ErrorScaffold`, spec
/// `docs/feedback/2026-08-08-prerelease-audit.md` P3/S2) when Settings
/// itself is unreachable because bootstrap never got that far.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs the reset-app-data double-confirm flow: shows the first
/// (state-aware) confirm dialog, then the second "last chance" dialog, then
/// wipes the database via [resetAppData] and invalidates [settingsProvider].
/// A cancel at either dialog is a no-op and leaves the database untouched.
///
/// [linked] picks the first dialog's body -- see the class-level doc
/// comment on [ResetDataTile] above for why that matters.
///
/// If [resetAppData] itself throws (e.g. the same broken database
/// connection that put the caller on the startup error screen in the first
/// place also can't be written through), shows [AppLocalizations.
/// settingsResetError] as a snackbar instead of letting the exception
/// propagate -- this is reachable from a screen with no other error
/// handling of its own.
///
/// Deliberately catches `on Object`, not just `on Exception` (a departure
/// from this codebase's usual `on Exception catch` convention, e.g.
/// `account_section.dart`'s sign-out/send handlers): a closed or corrupted
/// drift/sqlite3 connection throws `StateError` (`package:sqlite3`'s
/// `Database` -- see `This database has already been closed`), which is a
/// [Error], not an [Exception]; `on Object` is needed to catch both (Dart
/// has no single type spanning just "Exception or StateError"). The usual
/// reason to avoid catching `Error` (it usually signals a programming bug
/// that should crash loudly, not be swallowed) doesn't apply on this
/// specific path: this function exists ONLY as the last-resort escape
/// hatch reached from the app's own broken-database error screen, where
/// "the connection is bad" is exactly the expected failure mode, not a bug
/// to surface as a crash. `on Object catch` (rather than a bare `catch`)
/// also satisfies the `avoid_catches_without_on_clauses` lint this
/// project's analyzer config enforces at `--fatal-infos`.
Future<void> confirmAndResetAppData(
  BuildContext context,
  WidgetRef ref, {
  required bool linked,
}) async {
  final firstConfirmed = await _showFirstResetDialog(context, linked: linked);
  if (!firstConfirmed || !context.mounted) {
    return;
  }
  final secondConfirmed = await _showSecondResetDialog(context);
  if (!secondConfirmed || !context.mounted) {
    return;
  }

  final database = ref.read(appDatabaseProvider);
  try {
    await resetAppData(database);
  } on Object catch (_) {
    if (context.mounted) {
      showAppSnackbar(
        context,
        message: AppLocalizations.of(context).settingsResetError,
      );
    }
    return;
  }
  ref.invalidate(settingsProvider);
}

Future<bool> _showFirstResetDialog(
  BuildContext context, {
  required bool linked,
}) async {
  final errorColor = Theme.of(context).colorScheme.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.settingsResetConfirm1Title),
        content: Text(
          linked
              ? l10n.settingsResetConfirm1BodyLinked
              : l10n.settingsResetConfirm1Body,
        ),
        actions: [
          semantic(
            'settings.reset.cancel1',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'settings.reset.confirm1',
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: errorColor),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.settingsResetConfirm1Action),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

Future<bool> _showSecondResetDialog(BuildContext context) async {
  final errorColor = Theme.of(context).colorScheme.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.settingsResetConfirm2Title),
        content: Text(l10n.settingsResetConfirm2Body),
        actions: [
          semantic(
            'settings.reset.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'settings.reset.confirm2',
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: errorColor),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.settingsResetConfirm2Action),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// The destructive 'Reset app data' row at the very bottom of Settings,
/// immediately under the export row in the Data section -- the only row in
/// the whole screen drawn in `error`.
///
/// Tapping it runs [confirmAndResetAppData].
class ResetDataTile extends ConsumerWidget {
  /// Creates the reset row.
  const ResetDataTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;
    return semantic(
      'settings.reset',
      child: SettingsRow(
        icon: Icons.delete_forever_outlined,
        label: l10n.settingsResetEntry,
        destructive: true,
        onTap: () => confirmAndResetAppData(context, ref, linked: linked),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the existing reset-flow tests to confirm the refactor is behavior-preserving**

Run: `flutter test test/features/settings/reset_flow_test.dart`
Expected: PASS, unchanged (same semantic ids, same dialog copy, same wipe behavior — only relocated into a top-level function).

- [ ] **Step 6: Update `lib/app/app.dart`**

Add an import at the top, alongside the existing ones:

```dart
import 'package:chore_app/features/settings/reset_flow.dart';
```

Change `ChoreApp.build`'s `home:` (replace the existing `error:` branch):

```dart
      home: gate.when(
        data: (household) =>
            household == null ? const WelcomeScreen() : const _Bootstrapped(),
        loading: () => const _LoadingScaffold(),
        error: (error, stackTrace) => _ErrorScaffold(
          error: error,
          onRetry: () => ref.invalidate(householdGateProvider),
        ),
      ),
```

Change `_Bootstrapped.build` the same way:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);
    return bootstrap.when(
      data: (_) => const AppShell(),
      loading: () => const _LoadingScaffold(),
      error: (error, stackTrace) => _ErrorScaffold(
        error: error,
        onRetry: () => ref.invalidate(bootstrapProvider),
      ),
    );
  }
```

Replace `_ErrorScaffold` entirely with:

```dart
/// Shown if either [householdGateProvider] or [bootstrapProvider] fails
/// (e.g. the local database couldn't be opened): a non-technical headline,
/// the raw exception as a de-emphasized detail line (kept, rather than
/// hidden, so a user can screenshot it into a bug report on this
/// open-source app with no crash reporting of its own), a Retry action, and
/// -- since retry alone can't help with a genuinely broken database file --
/// a Reset app data escape hatch that runs the exact same flow as the
/// Settings row (spec `docs/feedback/2026-08-08-prerelease-audit.md`
/// P3/S2: this used to be a permanent dead end, because Settings itself is
/// unreachable from here).
class _ErrorScaffold extends ConsumerWidget {
  const _ErrorScaffold({required this.error, required this.onRetry});

  final Object error;

  /// Re-attempts whichever provider ([householdGateProvider] or
  /// [bootstrapProvider]) produced [error] -- supplied by the call site
  /// above, since only it knows which one that was.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;
    return Scaffold(
      // A `Builder` is required here (rather than reusing the ambient
      // `context`): `home` is built as part of constructing `MaterialApp`
      // itself, so that `context` sits *above* the `Localizations` widget
      // `MaterialApp` establishes for its subtree — `AppLocalizations.of`
      // needs a `context` from inside that subtree instead.
      body: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          final theme = Theme.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.appBootstrapErrorTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  semantic(
                    'app.bootstrap_error',
                    child: Text(
                      l10n.appBootstrapError(error),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  semantic(
                    'app.bootstrap_error.retry',
                    child: OutlinedButton(
                      onPressed: onRetry,
                      child: Text(l10n.commonRetry),
                    ),
                  ),
                  const SizedBox(height: 8),
                  semantic(
                    'app.bootstrap_error.reset',
                    child: TextButton(
                      onPressed: () =>
                          confirmAndResetAppData(context, ref, linked: linked),
                      child: Text(l10n.settingsResetEntry),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/widget_test.dart`
Expected: PASS.

Run the full suite (this touches `ChoreApp`/`_Bootstrapped`, both used by every widget test via `test/test_utils/pump_app.dart`):

Run: `flutter test`
Expected: PASS.

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/app/app.dart lib/features/settings/reset_flow.dart \
  test/widget_test.dart lib/l10n/app_en.arb lib/l10n/app_de.arb
git commit -m "Give the startup error screen a retry and a reset escape hatch"
```

---

## Self-review notes

- **Coverage:** E-1 → Task 4, E-2 → Task 5, E-3 → Task 3, E-4 → Task 1, E-5 → Task 2. All five backlog items have a task.
- **Task independence:** Tasks 1-5 touch disjoint file sets except for the two ARB files (Tasks 3, 4, and 5 all add keys to `lib/l10n/app_en.arb`/`app_de.arb`, but at different, clearly-marked insertion points) — they can be done in any order or by different people without conflict beyond a possible ARB merge, and each is its own commit as the ticket requires.
- **Type/signature consistency:** `confirmAndResetAppData(BuildContext, WidgetRef, {required bool linked})` (Task 5) and `DigestNotificationPlugin.zonedSchedule`'s new `channelName`/`channelDescription` params (Task 4) are used identically everywhere they're referenced across each task's steps.
- **No placeholders:** every step above shows the actual code to write, not a description of it.
