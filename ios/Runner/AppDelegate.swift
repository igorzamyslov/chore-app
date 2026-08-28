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
    // BEFORE super, which is what starts the Dart entrypoint and therefore the
    // first thing that can ask drift to create the database file. See the
    // method's own comment for why that ordering matters.
    excludeLocalDatabaseFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Keeps the on-device SQLite database out of iCloud and iTunes/Finder
  /// backups (backlog A-3b; the iOS counterpart of Android's
  /// `allowBackup="false"`, decision D-B1, which excludes the whole app
  /// sandbox). Plan: docs/plans/2026-08-28-a3b-ios-backup-exclusion.md.
  ///
  /// WHY THIS IS SWIFT AND NOT DART. `openConnection()`
  /// (lib/data/db/app_database.dart) is called from TWO isolates -- the main
  /// one and the F-1 notification-action background isolate -- and that
  /// isolate's ability to resolve path_provider inside a background
  /// FlutterEngine is the one thing in this codebase that was proven on a
  /// physical device. A Dart implementation would need a new MethodChannel:
  /// a new channel dependency one careless refactor away from that path, whose
  /// registration Swift would be no more verifiable than this is. This
  /// function touches only Foundation -- no MethodChannel, no plugin
  /// registry -- so it cannot affect either engine, and Android is untouched
  /// with no `Platform.isIOS` guard to get wrong.
  ///
  /// WHY THE DIRECTORY *AND* THE FILES. `isExcludedFromBackup` on a directory
  /// covers its contents, including files created after the attribute is set,
  /// which is what covers a fresh install: at this point in launch the
  /// database does not exist yet, so the per-file loop below skips it. The
  /// per-file writes then pin the file itself on every later launch, so the
  /// guarantee for the file that actually matters does not rest on
  /// directory-subtree semantics. Both are idempotent and re-applied every
  /// launch, which is also how a sidecar left behind by an unclean shutdown
  /// gets covered.
  ///
  /// This app puts nothing else in `Documents/`; the "Export data" row hands
  /// its file to the share sheet. If that ever changes, note that a
  /// user-facing document placed there would silently get no backup.
  ///
  /// FAILURE POSTURE: every fallible call is `try?` or a `guard`, and there is
  /// no force-try. A backup attribute is never worth a launch crash, so a
  /// failure here leaves the app starting normally with a backed-up database.
  ///
  /// NOT COMPILED BY ANY CI JOB ON A PULL REQUEST -- the same caveat as
  /// `didInitializeImplicitFlutterEngine` below. The only automated guard is
  /// test/data/db/ios_backup_exclusion_test.dart, which checks that the file
  /// names below still match Dart's `databaseName`, and nothing more.
  private func excludeLocalDatabaseFromBackup() {
    let fileManager = FileManager.default
    // path_provider's getApplicationDocumentsDirectory(), which drift_flutter
    // uses as the database directory, is this same NSDocumentDirectory.
    guard
      let documents = try? fileManager.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
    else { return }

    var directory = documents
    var directoryValues = URLResourceValues()
    directoryValues.isExcludedFromBackup = true
    try? directory.setResourceValues(directoryValues)

    // Spelled out in full rather than assembled from a base name plus
    // suffixes, so the mirror test can find each one as a literal. Only
    // `-journal` is reachable today: drift leaves sqlite3 in its default
    // rollback-journal mode, so there is no `-wal` and no `-shm`. Naming them
    // costs nothing (a file that does not exist is skipped) and keeps this
    // correct if write-ahead logging is ever switched on.
    let databaseFileNames = [
      "chore_app.sqlite",
      "chore_app.sqlite-journal",
      "chore_app.sqlite-wal",
      "chore_app.sqlite-shm",
    ]
    for name in databaseFileNames {
      var file = documents.appendingPathComponent(name)
      guard fileManager.fileExists(atPath: file.path) else { continue }
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? file.setResourceValues(values)
    }
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
