import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for notification ACTIONS to reach the app at all (spec
    // docs/specs/notifications.md N2, backlog F-1): with no
    // UNUserNotificationCenter delegate set, iOS has nowhere to hand the
    // response for the digest's "Done" button. FlutterAppDelegate already
    // conforms to UNUserNotificationCenterDelegate, so this is a wiring line
    // and not a new implementation.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Required so the BACKGROUND engine spawned for notification actions
    // registers every other plugin into ITSELF -- specifically path_provider
    // and sqlite3_flutter_libs, which drift's openConnection() needs. Without
    // this, the background isolate's AppDatabase(openConnection()) call fails,
    // and it fails SILENTLY: there is no UI in that isolate to report to, so
    // the user's "Done" tap simply vanishes. Verified against
    // flutter_local_notifications' own example AppDelegate.swift.
    //
    // Must run BEFORE the GeneratedPluginRegistrant call below: the callback
    // has to be installed before anything can build a background engine.
    //
    // NOT COMPILED BY ANY CI JOB ON A PULL REQUEST. `flutter test` and the
    // Android jobs never touch Swift, and e2e.yml's iOS job is gated on
    // refs/heads/main, so nothing here is exercised before this merges. A
    // syntax error surfaces only in an iOS build; a logic error surfaces only
    // on a real device -- see docs/plans/2026-08-08-notification-actions.md
    // Task 10, whose first three items are the gates for this file.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
