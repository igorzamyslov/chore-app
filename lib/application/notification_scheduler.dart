/// Turns a [DigestPlan] into an actual scheduled OS notification, on top of
/// `flutter_local_notifications` (spec `docs/specs/notifications.md`
/// architecture #2/#3).
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:chore_app/application/digest_action_payload.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// The lowest notification id the daily digest owns; horizon slot `k`
/// (0 = the next slot) uses `digestNotificationIdBase + k` (spec
/// `docs/specs/notifications.md` architecture #2).
const int digestNotificationIdBase = 1001;

/// Every notification id the digest horizon owns, in slot order: one id
/// per horizon SLOT, not per calendar day.
///
/// Those were the same thing while the horizon was a flat run of
/// consecutive days. They no longer are: the horizon's trailing segment
/// samples one day in every `digestHorizonTailStepDays` (spec
/// `docs/specs/notifications.md` N1), so slot `k`'s calendar date is not
/// `k` days out once `k` passes the daily segment.
///
/// Fixed and exhaustive on purpose: every reschedule rewrites ALL of these
/// (scheduling some, cancelling the rest), so a slot that stops having
/// anything to say can never keep a stale notification armed.
final List<int> digestNotificationIds = List<int>.unmodifiable([
  for (var k = 0; k < digestHorizonSlots; k++) digestNotificationIdBase + k,
]);

/// The Android notification channel the digest notification is posted on.
///
/// `_v2`, rather than the original `'digest'`: Android caches a channel's
/// name and description at CREATION time and never updates them for an
/// existing id -- there is no rename operation. Passing newly localized
/// copy to the same id would therefore change nothing on any device that
/// already has the channel, which is every device the digest has ever fired
/// on. Minting a NEW id is what makes the localized copy (backlog E-1)
/// actually reach those installs, with no migration-state bookkeeping: the
/// id has never existed there, so the plugin creates it fresh with today's
/// localized name on the very next schedule.
///
/// Cost of the re-mint, accepted deliberately: a user who had customized
/// the old channel's importance or sound in system Settings loses that
/// customization once. That is the cheaper of the two prices for a
/// cosmetic, pre-wide-install fix -- the alternative is a permanently
/// English channel name in every non-English install.
///
/// ## What a LANGUAGE SWITCH does to this name -- decided, not overlooked
///
/// The same caching means the channel's name is frozen at whatever locale
/// was active the first time this app created it. A user who later switches
/// language in Settings keeps the OLD language's channel name in system
/// Settings -> Notifications, permanently, because there is no rename.
///
/// **That is ACCEPTED, and deliberately not "fixed".** The alternative --
/// minting a per-language id, or re-minting on every language change --
/// would leave one dead channel row behind for every language the user ever
/// tried, and would silently discard their own importance/sound
/// customization each time (channel identity is what carries it). A stale
/// name on one row inside system Settings is a smaller harm than a growing
/// list of near-identical rows plus repeatedly-reset preferences.
///
/// What the user actually reads is unaffected: the notification's own title
/// and body are re-resolved from [NotificationScheduler.localeResolver] on
/// EVERY reschedule (see [resolveDigestLocale]), so a language switch takes
/// effect on the next apply. Only the system-Settings label lags.
///
/// If that label ever does need to change, the mechanism is the one this
/// constant already documents: bump the id AND delete its predecessor. Do
/// not attempt a rename; there isn't one.
///
/// See [legacyDigestChannelId] for the cleanup half of this.
const String digestChannelId = 'digest_v2';

/// The pre-l10n channel id, superseded by [digestChannelId].
///
/// Kept only so [NotificationScheduler.ensureInitialized] can delete it: a
/// re-mint without a delete would leave every upgrading user with TWO
/// digest entries in system Settings -> Notifications, one of them dead and
/// English-named, and no way to tell which is which.
const String legacyDigestChannelId = 'digest';

/// The iOS `UNNotificationCategory` identifier carrying the digest's "Done"
/// action (spec `docs/specs/notifications.md` N2).
///
/// iOS actions are registered once per category at `initialize()` time and
/// referenced per-notification via
/// [DarwinNotificationDetails.categoryIdentifier]; Android has no equivalent
/// and attaches its actions per-notification instead.
const String digestActionsCategoryId = 'digestActions';

/// The `actionId` of the digest's "Done" action.
///
/// **Namespaced deliberately.** `actionId` is the routing discriminator in a
/// callback that is PROCESS-GLOBAL: the background handler receives responses
/// for every notification this app will ever schedule, including the 40 ids
/// reserved for the unbuilt per-chore reminders (backlog G-6 / F16). A bare
/// `'done'` here is precisely the name G-6 would plausibly reuse for its own
/// per-chore Done button, and the two would then be indistinguishable. G-6
/// mints its own id; it does not reuse this one.
const String digestDoneActionId = 'digest.done';

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
  ///
  /// [doneActionTitle] is the localized label for the digest's "Done" action
  /// (spec `docs/specs/notifications.md` N2). It is used ONLY for the iOS
  /// notification category [digestActionsCategoryId], because
  /// `UNNotificationCategory` fixes its action titles at registration and
  /// offers no per-notification override. Android's action title is passed
  /// per notification in [zonedSchedule] instead, so it always follows the
  /// current locale.
  Future<void> initialize({required String doneActionTitle});

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
  ///
  /// [channelName] and [channelDescription] are the localized copy for the
  /// Android channel [digestChannelId], and they take effect only the FIRST
  /// time this app ever creates that channel on the device -- see that
  /// constant's doc comment for why a later call cannot rename it. They are
  /// passed per-call rather than once at init because only the caller knows
  /// the current locale, and the locale can change between launches.
  ///
  /// [payload] is the JSON action payload (see
  /// `lib/application/digest_action_payload.dart`) delivered back to the app
  /// when the user interacts with this notification. [actionable] attaches the
  /// localized "Done" action — Android per-notification, iOS by pointing the
  /// notification at the [digestActionsCategoryId] category registered in
  /// [initialize].
  ///
  /// Today the digest passes them together: [payload] is non-null exactly
  /// when [actionable] is true. They are still two parameters rather than one
  /// nullable payload because they are two distinct platform concepts — a
  /// payload also comes back on a plain body tap, with no action involved —
  /// and no invariant tying them is asserted here.
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelName,
    required String channelDescription,
    String? payload,
    bool actionable = false,
  });

  /// Cancels the notification scheduled with [id], if any.
  Future<void> cancel(int id);

  /// Deletes the [legacyDigestChannelId] Android channel, if it still exists
  /// on this device.
  ///
  /// A no-op on platforms with no channel concept (iOS/desktop), and safe to
  /// call repeatedly: deleting an already-deleted or never-created channel
  /// does nothing.
  Future<void> deleteLegacyDigestChannel();
}

/// The production [DigestNotificationPlugin], backed by
/// `flutter_local_notifications`.
class FlutterLocalNotificationsAdapter implements DigestNotificationPlugin {
  /// Creates an adapter around a fresh plugin instance.
  ///
  /// [onBackgroundResponse] is the top-level `@pragma('vm:entry-point')`
  /// handler the OS invokes, in a fresh background isolate, when the user taps
  /// a notification ACTION — in production
  /// `handleNotificationAction` from
  /// `lib/application/notification_action_handler.dart`.
  ///
  /// **Required rather than defaulted, deliberately, for two reasons.** It
  /// keeps this file free of any data-layer import: the handler opens its own
  /// `AppDatabase`, so a default value here would make every importer of the
  /// scheduler (including widget tests) depend transitively on drift, and
  /// would create an import cycle between the two libraries. And because it is
  /// required, the compiler names every construction site that would otherwise
  /// have shipped a "Done" button that silently does nothing — a failure mode
  /// indistinguishable from a working app until a user taps it.
  FlutterLocalNotificationsAdapter({required this.onBackgroundResponse})
    : _plugin = FlutterLocalNotificationsPlugin();

  /// The background notification-action handler; see the constructor.
  final DidReceiveBackgroundNotificationResponseCallback onBackgroundResponse;

  final FlutterLocalNotificationsPlugin _plugin;

  /// The localized "Done" action title, captured at [initialize] and reused
  /// for every Android per-notification action.
  ///
  /// Android's action title IS per notification, so re-resolving it per apply
  /// would honour a mid-session language switch — but every caller resolves
  /// its copy once per apply and this adapter is only ever driven by
  /// [NotificationScheduler], which passes the same locale's strings to
  /// [initialize] and [zonedSchedule] alike. Caching keeps the interface from
  /// carrying the same string twice per call.
  String _doneActionTitle = '';

  @override
  Future<void> initialize({required String doneActionTitle}) async {
    _doneActionTitle = doneActionTitle;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // `request*Permission: false`: the iOS authorization prompt is
    // deliberately deferred to [requestPermission], which
    // [NotificationScheduler] only calls on the first real schedule
    // attempt (spec: "on first enable", not app launch). Passing `true`
    // here would make the plugin request it immediately on `initialize`,
    // i.e. at bootstrap.
    //
    // `notificationCategories` registers the digest's "Done" action for iOS
    // (spec `docs/specs/notifications.md` N2). Unlike Android, iOS fixes a
    // category's action titles at registration time -- `UNNotificationCategory`
    // has no per-notification override -- and `ensureInitialized` runs once
    // per process, so the iOS label is frozen at whichever locale was active
    // on this process's first init. A language switch reaches it on the next
    // full relaunch. Documented, not solved: the same class of lag the
    // Android channel NAME already accepts (see [digestChannelId]), and
    // normal on both platforms.
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          digestActionsCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              digestDoneActionId,
              doneActionTitle,
            ),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(android: androidInit, iOS: iosInit),
      // VERIFIED against flutter_local_notifications 22.1.0's own Android
      // source, because the plan that specified this treated it as an
      // unverified fork: an action built with `showsUserInterface: false`
      // gets a `PendingIntent.getBroadcast` to `ActionBroadcastReceiver`
      // (`FlutterLocalNotificationsPlugin.java`), and that receiver ALWAYS
      // runs the Dart callback dispatcher in a headless engine of its own --
      // it has no reference to the app's main engine and never forwards to
      // it. `didReceiveNotificationResponse` is only ever invoked for the
      // `SELECT_NOTIFICATION`/`SELECT_FOREGROUND_NOTIFICATION_ACTION` intent
      // actions, which are set exclusively on ACTIVITY launch intents. So a
      // `showsUserInterface: false` action tap reaches this background
      // callback even when the app is in the FOREGROUND, and there is no code
      // path by which it could reach the foreground one. That is why the
      // background handler pings the main isolate rather than relying on the
      // app-resume observer -- see `notification_action_handler.dart`.
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
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
    required String channelName,
    required String channelDescription,
    String? payload,
    bool actionable = false,
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
          // Attached per notification, which is what lets the label follow
          // the current locale (spec `docs/specs/notifications.md` N2), and
          // only for slots that name a single occurrence. Action buttons
          // render fine at this channel's existing default importance, so no
          // channel change is needed -- and none may be made: E-1 has just
          // minted `digest_v2` and re-minting would discard the localized
          // name and any importance/sound the user customized.
          actions: actionable
              ? [
                  AndroidNotificationAction(
                    digestDoneActionId,
                    _doneActionTitle,
                    // Already the default, but passed explicitly because it
                    // is the load-bearing decision, not an accident: `false`
                    // is what routes the tap to the background isolate
                    // instead of launching the app. See the verification note
                    // at the `initialize` call above.
                    showsUserInterface: false,
                  ),
                ]
              : null,
        ),
        // `categoryIdentifier` is how iOS finds the actions, which were
        // registered on the category in `initialize` (iOS has no
        // per-notification action list).
        iOS: DarwinNotificationDetails(
          categoryIdentifier: actionable ? digestActionsCategoryId : null,
        ),
      ),
      payload: payload,
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
    // `resolvePlatformSpecificImplementation` returns null off Android, so
    // this is the whole cross-platform story: nowhere else has channels.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.deleteNotificationChannel(channelId: legacyDigestChannelId);
  }
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

  /// Resolves the locale used to format the notification's title, body and
  /// channel copy.
  ///
  /// Production wiring passes [resolveDigestLocale] over the in-app language
  /// override, NOT the bare OS locale -- see that function. It is called
  /// afresh on every apply, so a language switch reaches the next
  /// reschedule; do not hoist its result into a field.
  final ui.Locale Function() localeResolver;

  bool _initialized = false;

  /// The tail of the serialized-apply chain: resolves once whichever
  /// [applyDigestPlans] call is currently running -- from ANY caller --
  /// has finished writing its own [digestHorizonSlots] slots. A new call
  /// waits on this before starting its own loop; see [applyDigestPlans]'s
  /// doc comment.
  ///
  /// Deliberately never allowed to complete with an error: a failed apply
  /// must not permanently jam the queue for every apply that comes after
  /// it. The error itself still reaches the caller that made THAT call,
  /// via the future [applyDigestPlans] returns to them.
  Future<void> _applyTail = Future<void>.value();

  /// Initializes the underlying plugin. Idempotent: only the first call
  /// does anything. Safe to call on every bootstrap/resume.
  ///
  /// Also deletes the [legacyDigestChannelId] channel (backlog E-1), behind
  /// the same [_initialized] flag as the plugin init above it -- once per
  /// process is all it needs, since the delete is a no-op forever after the
  /// channel is actually gone. It runs BEFORE anything can be scheduled on
  /// [digestChannelId], because every schedule and cancel path funnels
  /// through here first, so a user never briefly holds both channels.
  /// Passes the localized "Done" action title down for the iOS notification
  /// category (spec `docs/specs/notifications.md` N2). Resolved through
  /// [localeResolver] like every other string here, so an in-app language
  /// override reaches it -- but only once per process, since this is
  /// idempotent; see [DigestNotificationPlugin.initialize].
  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    final l10n = lookupAppLocalizations(localeResolver());
    await plugin.initialize(doneActionTitle: l10n.notificationActionDone);
    await plugin.deleteLegacyDigestChannel();
    _initialized = true;
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
  /// This call fans out into [digestHorizonSlots] sequential
  /// platform-channel calls (one per horizon SLOT — not per calendar day:
  /// the horizon's trailing segment is sparse), and every `await` yields
  /// the isolate — so two calls in flight at once, from any two callers,
  /// could otherwise interleave their writes to the very same
  /// [digestHorizonSlots] ids (`DigestRescheduleController`
  /// and `DigestPrepromptBanner._enable` both call this independently).
  /// This method therefore chains every call onto [_applyTail], so a call
  /// that arrives while another is still mid-loop waits for it to finish
  /// completely before writing a single slot of its own, no matter which
  /// caller either one is. `DigestRescheduleController`'s own in-flight/
  /// queued bookkeeping (`_inFlightRecompute`/`_recomputeQueued`) is a
  /// separate, narrower guarantee on top of this one: it *coalesces*
  /// redundant triggers from that one call site into a single re-run, it
  /// does not by itself protect the horizon from a second, independent
  /// caller such as the banner.
  ///
  /// Deliberately never requests the OS notification permission itself; see
  /// the class doc and spec `docs/specs/polish-round-1.md` A3.
  ///
  /// [actingMemberId] is the member the whole recompute was scoped to, and is
  /// what a "Done" tap on any of these slots will be attributed to. It is a
  /// parameter here rather than a [DigestPlan] field because it is a property
  /// of the recompute, not of one slot: it would be identical on all
  /// [digestHorizonSlots] entries and would push an application-layer identity
  /// into a pure-domain value. `null` (identity unresolvable — see
  /// `actingMemberProvider`) yields a payload with `by: null`, i.e. an
  /// unattributed completion, which is the honest answer rather than a guess.
  ///
  /// Throws [ArgumentError] if [plans] is not exactly [digestHorizonSlots]
  /// long.
  Future<void> applyDigestPlans(
    List<DigestPlan?> plans, {
    String? actingMemberId,
  }) {
    if (plans.length != digestHorizonSlots) {
      throw ArgumentError.value(
        plans.length,
        'plans.length',
        'Must be exactly digestHorizonSlots ($digestHorizonSlots)',
      );
    }
    final waitForPrevious = _applyTail.catchError((_) {});
    final thisApply = waitForPrevious.then(
      (_) => _applyDigestPlansNow(plans, actingMemberId),
    );
    _applyTail = thisApply.catchError((_) {});
    return thisApply;
  }

  Future<void> _applyDigestPlansNow(
    List<DigestPlan?> plans,
    String? actingMemberId,
  ) async {
    await ensureInitialized();
    final l10n = lookupAppLocalizations(localeResolver());
    for (var k = 0; k < plans.length; k++) {
      final plan = plans[k];
      final id = digestNotificationIdBase + k;
      if (plan == null) {
        await plugin.cancel(id);
      } else {
        // Per slot, deliberately: each slot carries its own counts, so slot 0
        // can be actionable while slot 5 is not (spec
        // `docs/specs/notifications.md` N2).
        final soleOccurrenceId = plan.soleOccurrenceId;
        await plugin.zonedSchedule(
          id: id,
          title: l10n.appTitle,
          body: _digestBody(l10n, plan),
          fireAt: plan.fireAt,
          channelName: l10n.notificationChannelDigestName,
          channelDescription: l10n.notificationChannelDigestDescription,
          payload: soleOccurrenceId == null
              ? null
              : encodeDigestActionPayload(
                  occurrenceId: soleOccurrenceId,
                  actingMemberId: actingMemberId,
                ),
          actionable: soleOccurrenceId != null,
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

/// The locale the digest's copy is rendered in: the in-app language
/// override ([inAppOverride], `localeOverrideProvider`'s value, backed by
/// the persisted `settings.locale` column) when the user has chosen one,
/// otherwise the OS locale.
///
/// This exists because the OS locale ALONE is the wrong source. The UI
/// honours the in-app override, so reading only
/// `PlatformDispatcher.instance.locale` gave a user who picked German on an
/// English-language phone English digest notifications while every screen
/// around them was German. That is the same class of defect as backlog
/// E-1's hardcoded channel copy -- a user-visible notification string not
/// resolved the way the rest of the app resolves its strings -- so it is
/// fixed here rather than filed.
///
/// `null` means "no override stored", which is also what an unrecognized
/// stored value maps to (`localeOverrideProvider`'s read-time self-heal:
/// nothing is written back), so a foreign value degrades to the OS locale
/// instead of throwing.
ui.Locale resolveDigestLocale(ui.Locale? inAppOverride) =>
    inAppOverride ?? _defaultLocale();

/// Maps a `settings.locale` column value to a [ui.Locale], or `null` for "no
/// override stored".
///
/// **Shared on purpose** between `localeOverrideProvider`
/// (`lib/app/providers.dart`, which drives `MaterialApp.locale`) and
/// `readDigestLocale` (`lib/application/notification_action_processor.dart`,
/// the notification-action isolate, which has no Riverpod container to read a
/// provider from). Those two must agree, and duplicating a switch statement in
/// two isolates is exactly how they would stop agreeing.
///
/// An unrecognized value — future-proofing against a value this build does not
/// know — maps to `null` rather than throwing, and nothing is written back:
/// the same read-time self-heal `actingMemberProvider` applies to a stale
/// stored id. A foreign value therefore degrades to the OS locale.
ui.Locale? localeFromStoredSetting(String? stored) {
  switch (stored) {
    case 'en':
      return const ui.Locale('en');
    case 'de':
      return const ui.Locale('de');
    default:
      return null;
  }
}

ui.Locale _defaultLocale() => ui.PlatformDispatcher.instance.locale;
