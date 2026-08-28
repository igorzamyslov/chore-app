import 'dart:io';

import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backlog **A-3b** — the iOS counterpart of Android's `allowBackup="false"`
/// (decision D-B1). `drift_flutter` puts the database in
/// `getApplicationDocumentsDirectory()`, which iCloud and iTunes back up by
/// default, and the fix is a per-URL runtime attribute
/// (`NSURLIsExcludedFromBackupKey`) set in `ios/Runner/AppDelegate.swift`.
///
/// ## What these tests prove, and what they emphatically do not
///
/// They are a **cross-language mirror check on file names**. No CI job on a
/// pull request compiles Swift — `ci.yml`'s `checks` job is format + analyze +
/// `flutter test`, and the only `flutter build ios` in the repo is `e2e.yml`'s
/// `ios` job, gated on `refs/heads/main` (backlog A-6). So nothing here — and
/// nothing anywhere else in this repo — can establish that the Swift compiles,
/// runs, or sets a single attribute. That is verified by hand, per
/// `docs/plans/2026-08-28-a3b-ios-backup-exclusion.md` §5.
///
/// What they DO catch is the one failure mode that would otherwise be
/// completely silent: the Swift hardcodes the database's file names, so
/// renaming [databaseName] without editing `AppDelegate.swift` would
/// un-exclude the database with nothing red anywhere.
void main() {
  group('iOS backup exclusion (A-3b)', () {
    late String appDelegate;

    setUp(() {
      final file = File('ios/Runner/AppDelegate.swift');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'ios/Runner/AppDelegate.swift not found — these tests read it as '
            'text and assume `flutter test` runs from the package root.',
      );
      appDelegate = file.readAsStringSync();
    });

    test('AppDelegate.swift names the database file and every sidecar', () {
      // The main file plus the three sidecar names sqlite3 can put next to it.
      // Only `-journal` is reachable today: drift leaves sqlite3 in its
      // default rollback-journal mode (`drift/native.dart` documents that
      // enabling WAL is the caller's job, via `DriftNativeOptions.setup`,
      // which `openConnection()` does not pass), so there is no `-wal` and no
      // `-shm`. They are named anyway — the attribute write is skipped for a
      // file that does not exist, so covering them costs nothing and keeps the
      // exclusion correct if anyone ever turns WAL on.
      for (final name in const ['', '-journal', '-wal', '-shm']) {
        expect(
          appDelegate,
          contains('"$databaseName.sqlite$name"'),
          reason:
              'AppDelegate.swift must exclude $databaseName.sqlite$name from '
              'backup by name. If the database was renamed, rename it there '
              'too — nothing else in CI will tell you.',
        );
      }
    });

    // A standing regression guard rather than a behaviour this file drove out:
    // it was already green before the exclusion existed. A force-try in
    // `didFinishLaunchingWithOptions` would turn a failed attribute write into
    // a launch crash, and a backup attribute is never worth that.
    test('AppDelegate.swift contains no force-try', () {
      expect(appDelegate, isNot(contains('try!')));
    });
  });
}
