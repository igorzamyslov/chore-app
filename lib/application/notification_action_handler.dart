/// The background-isolate entrypoint for digest notification actions (spec
/// `docs/specs/notifications.md` N2, backlog F-1).
///
/// Deliberately thin glue and nothing else: every decision lives in
/// `lib/application/notification_action_processor.dart`, which is unit-tested
/// against a real in-memory database. This file is not directly tested — the
/// same carve-out this codebase already applies to
/// `FlutterLocalNotificationsAdapter`, which is covered only through
/// `NotificationScheduler` against a fake — so anything with a judgement in it
/// belongs next door, not here.
///
/// ## UNVERIFIED GROUND — read before changing anything below
///
/// Two facts this file depends on cannot be established from `flutter test`,
/// and `e2e.yml` cannot reach them either (it drives a Maestro flow on an
/// Android emulator, which can neither wait for a scheduled digest nor tap a
/// notification action, and runs fully offline). They are verified by hand,
/// once per platform, per `docs/plans/2026-08-08-notification-actions.md`
/// Task 10:
///
/// 1. **That `openConnection()` works at all in this isolate.** It is
///    `driftDatabase(name: 'chore_app')`, which resolves its directory through
///    `path_provider` — a PLATFORM CHANNEL, needing an initialised binding and
///    a registered plugin in THIS engine. The plugin's own
///    `callback_dispatcher.dart` does call
///    `WidgetsFlutterBinding.ensureInitialized()` before invoking us, and the
///    iOS `setPluginRegistrantCallback` wiring in `AppDelegate.swift` exists
///    precisely so the background engine registers `path_provider` and
///    `sqlite3_flutter_libs`. *If the on-device check shows it fails, the fix
///    is an explicit database file path instead of the channel lookup:
///    [AppDatabase] takes a plain `QueryExecutor`, so that is a change of
///    executor here, not of the class.*
/// 2. **That this isolate survives long enough to finish step 3 below.** The
///    host is a time-boxed `ActionBroadcastReceiver` (Android) or a background
///    `FlutterEngine` (iOS). *If it does not, accept the truncation and
///    document it — the bound is the one
///    `docs/handover-2026-08-14-planning.md` §4 already accepts for a
///    mid-apply process kill: at worst one duplicate morning notification. Do
///    NOT respond by switching to `NotificationScheduler.cancelAll()`, which
///    trades one wrong notification for up to 83 days of silence.*
///
/// A third assumption the plan flagged IS now verified, from the installed
/// package's own Android source rather than on a device — see the routing note
/// at `FlutterLocalNotificationsAdapter.initialize`: a `showsUserInterface:
/// false` action always reaches this callback, even with the app in the
/// foreground. That is why step 2 pings the main isolate instead of leaving the
/// refresh to the app-resume observer.
library;

import 'dart:async';
// `IsolateNameServer` lives in `dart:ui`, not `dart:isolate`.
import 'dart:ui' as ui;

import 'package:chore_app/application/digest_action_payload.dart';
import 'package:chore_app/application/notification_action_processor.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The `IsolateNameServer` port name the main isolate registers at bootstrap
/// (`NotificationActionSignalController`) and this handler pings.
///
/// `IsolateNameServer` is an in-process, OS-independent registry, which is what
/// makes the ping both cheap and testable: a test can look the port up and send
/// to it directly, with no real isolate spawn.
const String notificationActionPortName = 'chore_app.notification_action';

/// Handles a notification action tapped by the user, in a background isolate
/// with no Riverpod container, no open [AppDatabase], no `BuildContext` and no
/// Supabase session.
///
/// **Top-level and `@pragma('vm:entry-point')`, both hard requirements.** The
/// plugin looks this up by its compile-time handle from a fresh isolate that
/// has never run any other code in this app, and without the pragma the
/// compiler is free to tree-shake it away. It must not become an instance
/// method or a closure.
///
/// **Synchronous `void`, not `Future<void>`,** because that is the
/// `DidReceiveBackgroundNotificationResponseCallback` typedef — a
/// `Future`-returning function does not type-check against it. So NOTHING
/// awaits the work below, which is exactly why it is ordered by decreasing
/// importance rather than by convenience.
@pragma('vm:entry-point')
void handleNotificationAction(NotificationResponse response) {
  // Deliberately does NOT read `response.id`: ids are slot-relative, so they
  // name neither a chore nor a date, and the background path substitutes -1
  // for them outright. Nor `notificationResponseType`, which that path
  // hardcodes to `selectedNotificationAction` regardless. The actionId and the
  // payload are the only trustworthy fields.
  if (response.actionId != digestDoneActionId) {
    return;
  }
  final payload = decodeDigestActionPayload(response.payload);
  if (payload == null) {
    return;
  }
  // Fire-and-forget: see the `void` note above. Nothing can await this, and
  // nothing should try to make it awaitable.
  unawaited(_run(payload));
}

/// The async body of [handleNotificationAction].
///
/// **The order of the three steps IS the design. Do not reorder it.** The
/// hosting context is time-boxed and nothing awaits this future, so the work
/// must be arranged so that being cut short costs as little as possible:
///
/// 1. **Complete the occurrence.** The user's intent. Must never be lost, so it
///    goes first and its failure must not be caused by anything after it.
/// 2. **Ping the main isolate.** One message, sent BEFORE the long step, so an
///    alive app starts its own authoritative recompute as early as possible. If
///    the app is alive this single step fixes everything downstream, because
///    the main isolate then rewrites the horizon itself.
/// 3. **Rewrite the horizon.** Long (`digestHorizonSlots` platform calls) and
///    only matters when the app is DEAD — in which case nothing else is
///    contending for the time. Truncation here costs only the stale-count fix.
///
/// Step 3 is wrapped so that a throw in it cannot swallow a successful step 1:
/// a completion that landed must stay landed even if the reschedule blows up.
Future<void> _run(DigestActionPayload payload) async {
  final database = AppDatabase(openConnection());
  try {
    await applyDoneAction(
      database: database,
      occurrenceId: payload.occurrenceId,
      actingMemberId: payload.actingMemberId,
    );

    // Best-effort by design. A null lookup means the main isolate is not
    // alive, which is the common case for a notification action and is
    // completely fine -- step 3 is what covers it.
    ui.IsolateNameServer.lookupPortByName(
      notificationActionPortName,
    )?.send(null);

    // The isolate must produce the SAME copy as the main isolate, so the
    // locale comes from the persisted settings row rather than the scheduler's
    // bare OS-locale default -- see `readDigestLocale`.
    final locale = await readDigestLocale(database);
    await rewriteDigestHorizon(
      database: database,
      scheduler: NotificationScheduler(
        plugin: FlutterLocalNotificationsAdapter(
          onBackgroundResponse: handleNotificationAction,
        ),
        localeResolver: () => locale,
      ),
      actingMemberId: payload.actingMemberId,
    );
  } on Object catch (_) {
    // `on Object`, not `on Exception`: an Error escaping here has nowhere to go
    // -- there is no UI in this isolate and no user waiting on a result -- and
    // the alternative is an unhandled async error in a background engine,
    // which on some hosts takes the whole engine down mid-`finally`. Wave 3
    // proved the narrower catch is the wrong one: a `LateInitializationError`
    // from this very plugin is an Error, escaped an `on Exception`, and aborted
    // a double-confirmed wipe.
    //
    // Swallowing is safe HERE specifically because step 1 above is already
    // committed by the time anything after it can throw: the user's intent
    // survives a failed ping or a failed reschedule, and the next app open
    // recomputes the horizon anyway.
  } finally {
    // Held open for exactly this one unit of work and closed immediately.
    // SQLite's own WAL locking handles two connections to one file correctly;
    // what it does not forgive is a second connection left dangling across
    // isolate messages.
    await database.close();
  }
}
