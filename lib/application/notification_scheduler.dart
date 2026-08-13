/// Turns a [DigestPlan] into an actual scheduled OS notification, on top of
/// `flutter_local_notifications` (spec `docs/specs/notifications.md`
/// architecture #2/#3).
library;

import 'dart:ui' as ui;

import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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

/// The Android notification channel the digest notification is posted on.
const String digestChannelId = 'digest';

/// The narrow seam between [NotificationScheduler] and the real OS-level
/// plugin.
///
/// Production code uses [FlutterLocalNotificationsAdapter]; tests
/// substitute a fake implementing this interface directly, so
/// [NotificationScheduler]'s own translation logic (fixed notification id,
/// permission-request timing, localized title/body) runs for real in tests
/// without ever touching a real notification channel.
abstract class DigestNotificationPlugin {
  /// Initializes the underlying plugin. Called once per process (guarded by
  /// [NotificationScheduler]'s own idempotency) before any other method.
  Future<void> initialize();

  /// Requests the OS notification permission (alert/badge/sound on iOS;
  /// `POST_NOTIFICATIONS` on Android 13+).
  ///
  /// Safe to call more than once: the OS only ever prompts the user once,
  /// silently returning the existing grant/deny status on later calls.
  Future<void> requestPermission();

  /// Whether the OS currently reports notifications as permitted.
  Future<bool> isPermissionGranted();

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
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
  });

  /// Cancels the notification scheduled with [id], if any.
  Future<void> cancel(int id);
}

/// The production [DigestNotificationPlugin], backed by
/// `flutter_local_notifications`.
class FlutterLocalNotificationsAdapter implements DigestNotificationPlugin {
  /// Creates an adapter around a fresh plugin instance.
  FlutterLocalNotificationsAdapter()
    : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // `request*Permission: false`: the iOS authorization prompt is
    // deliberately deferred to [requestPermission], which
    // [NotificationScheduler] only calls on the first real schedule
    // attempt (spec: "on first enable", not app launch). Passing `true`
    // here would make the plugin request it immediately on `initialize`,
    // i.e. at bootstrap.
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );
  }

  @override
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<bool> isPermissionGranted() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final status = await ios.checkPermissions();
      return status?.isEnabled ?? false;
    }
    // Other platforms (desktop/web): no permission gate to check.
    return true;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
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
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          digestChannelId,
          'Daily summary',
          channelDescription: 'The once-a-day chores digest notification.',
        ),
        iOS: DarwinNotificationDetails(),
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
}

/// Translates [DigestPlan]s into scheduled OS notifications on top of a
/// [DigestNotificationPlugin] (spec `docs/specs/notifications.md`
/// architecture #2): this is the narrow 3-method interface every other
/// layer of the app depends on. Swapping [plugin] for a fake makes
/// everything above the real OS plugin — including this class's own
/// business rules below — deterministically testable.
class NotificationScheduler {
  /// Creates a scheduler backed by [plugin].
  ///
  /// [localeResolver] is injectable so tests can pin the notification
  /// copy's language; it defaults to the device's current locale.
  NotificationScheduler({
    required this.plugin,
    this.localeResolver = _defaultLocale,
  });

  /// The underlying OS-level plugin (or fake).
  final DigestNotificationPlugin plugin;

  /// Resolves the locale used to format the notification's title/body.
  final ui.Locale Function() localeResolver;

  bool _initialized = false;

  /// Initializes the underlying plugin. Idempotent: only the first call
  /// does anything. Safe to call on every bootstrap/resume.
  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await plugin.initialize();
    _initialized = true;
  }

  /// (Re)schedules the digest notification per [plan]: fixed id
  /// [digestNotificationIdBase], localized title (the app name) and body
  /// (the due/overdue counts).
  ///
  /// Deliberately never requests the OS notification permission itself
  /// (spec `docs/specs/polish-round-1.md` A3): that dialog is intrusive
  /// enough that it must only ever fire from an explicit user tap (the
  /// digest pre-prompt banner's 'Turn on', or the Settings digest
  /// permission hint's recovery path) — never as a side effect of a
  /// schedule attempt that could be triggered automatically (e.g. at
  /// bootstrap, with the digest enabled by default). Callers that DO want
  /// the permission requested call [DigestNotificationPlugin.
  /// requestPermission] directly, before or after this method, as
  /// appropriate.
  Future<void> scheduleDigest(DigestPlan plan) async {
    await ensureInitialized();
    final l10n = lookupAppLocalizations(localeResolver());
    await plugin.zonedSchedule(
      id: digestNotificationIdBase,
      title: l10n.appTitle,
      body: _digestBody(l10n, plan),
      fireAt: plan.fireAt,
    );
  }

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

  String _digestBody(AppLocalizations l10n, DigestPlan plan) {
    if (plan.dueTodayCount > 0 && plan.overdueCount > 0) {
      return l10n.notificationDigestBoth(
        plan.dueTodayCount,
        plan.overdueCount,
      );
    }
    if (plan.overdueCount > 0) {
      return l10n.notificationDigestOverdueOnly(plan.overdueCount);
    }
    return l10n.notificationDigestDueOnly(plan.dueTodayCount);
  }
}

ui.Locale _defaultLocale() => ui.PlatformDispatcher.instance.locale;
