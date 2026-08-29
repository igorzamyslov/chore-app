# Plan: A-3b — keep the local database out of iCloud/iTunes backups on iOS

*Written 2026-08-28, immediately before execution, against the tree as it then
stood. Backlog row **A-3b**. The iOS counterpart to A-3 (`allowBackup="false"`,
decision D-B1), which was deliberately Android-only.*

---

## 1. What is actually true today (verified, not assumed)

Every claim in this section was checked against source in this worktree or
against the resolved package versions in `pubspec.lock`.

1. **The database file.** `lib/data/db/app_database.dart:203` is the whole of
   the open path: `QueryExecutor openConnection() => driftDatabase(name:
   'chore_app');`. `drift_flutter-0.3.1/lib/src/native.dart` resolves that to
   `p.join(await getApplicationDocumentsDirectory(), 'chore_app.sqlite')` — no
   iOS/Android branch, no `DriftNativeOptions` passed anywhere in `lib/`. On
   iOS `getApplicationDocumentsDirectory()` is `NSDocumentDirectory`, which
   iCloud and iTunes/Finder back up by default.

2. **`openConnection()` has TWO callers, and one of them is the F-1 background
   isolate.** `lib/app/providers.dart:83` (main isolate, `appDatabaseProvider`)
   and `lib/application/notification_action_handler.dart:121` (`_run`, the
   background isolate spawned by `flutter_local_notifications`). That second
   caller is the constraint that shapes this whole plan — see §3.

3. **There is no `-wal` and no `-shm` file. The backlog row is wrong about
   this.** `drift_flutter` calls `NativeDatabase.createBackgroundConnection(file,
   setup: native?.setup)` with `native == null`, so `setup` is null; drift's own
   `native.dart` documents that it leaves sqlite3 in "the default journaling
   mode" and that enabling WAL is the caller's job (`pragma journal_mode = WAL`
   in `setup`). Nothing in `lib/` issues that pragma — `beforeOpen` in
   `app_database.dart` sets only `PRAGMA foreign_keys = ON`, and a repo-wide
   grep for `journal_mode`/`wal` in `lib/` and `test/` finds nothing. So the
   sidecar that actually appears is the **rollback journal**
   `chore_app.sqlite-journal`, created at the start of each write transaction
   and unlinked on commit.

   This changes the shape of one of the two hazards the row names. In WAL mode
   the `-wal` file holds *committed* data that is not yet in the main file, so
   excluding only the main file gives a genuinely torn restore. In rollback-
   journal mode every committed byte is always in the main file and the journal
   is the *recovery* record, so "torn restore" is not reachable the way the row
   describes it. The residual case is a restored `-journal` with no main file
   next to it. We exclude all four names anyway (§4): it costs nothing, it
   removes the residual case, and it means the exclusion stays correct if
   anyone ever turns WAL on.

4. **`NSURLIsExcludedFromBackupKey` is not an Info.plist key.** The row's
   "Files" column names `ios/Runner/Info.plist`. There is no Info.plist key
   that excludes a file from backup; it is a per-URL resource *attribute*, set
   at runtime with `URL.setResourceValues(_:)` / `URLResourceValues
   .isExcludedFromBackup`, and it persists on the file once set. The row's own
   Notes column already says "at runtime"; the Files column contradicts it. The
   Files column is wrong and this plan corrects the row.

5. **Nothing compiles Swift on a pull request.** `.github/workflows/ci.yml`'s
   `checks` job is format + `analyze --fatal-infos` + `flutter test`; the only
   `flutter build ios` in the repo is `e2e.yml`'s `ios` job, line 89:
   `if: github.ref == 'refs/heads/main'`. Recorded in
   `docs/handover-2026-08-18-wave-4.md` §3 and as backlog A-6.
   **Consequence: a green `checks` on this branch proves nothing whatsoever
   about the Swift below.**

6. **The Supabase session is NOT in the database.**
   `supabase_flutter-2.16.0/lib/src/supabase.dart:128` installs
   `SharedPreferencesLocalStorage` unless `authOptions.localStorage` is set,
   and `lib/main.dart` does not set it. So the refresh token lives in
   `NSUserDefaults` (`Library/Preferences/<bundle-id>.plist`), which is backed
   up and cannot meaningfully be excluded per-file. See §6 for why this does
   not weaken the fix.

---

## 2. Decision

**Do it, entirely in `ios/Runner/AppDelegate.swift`, at app launch, with zero
change to the Dart open path.** Set `isExcludedFromBackup` on the app's
`Documents` directory *and* on the four database file names, best-effort, on
every launch.

Rejected alternatives, with reasons:

- **A Dart `MethodChannel` into new Swift, called after the database opens.**
  This is the only shape that could set the attribute on a sidecar in the
  same session it is created, and the only shape with a Dart seam worth unit
  testing. Rejected: it requires registering a channel in `AppDelegate` (new,
  scene-era Flutter embedder API), and *that Swift is exactly the code no CI
  job compiles*. Trading a small correctness gain for a large increase in
  unverifiable, plumbing-shaped Swift is the wrong side of the trade in a repo
  where §1.5 holds. It would also put a platform-channel-shaped API one careless
  refactor away from the background isolate.

- **Relocating the database out of `Documents/`** via
  `DriftNativeOptions(databaseDirectory:)`. Rejected, firmly. iOS has no
  durable directory that is exempt from backup — `Library/Caches` is exempt but
  the OS may purge it, which is disqualifying for the primary datastore — so
  relocation does not even solve the problem; the sanctioned fix is the
  attribute either way. And **v0.7.1 is released and installed on at least one
  real device**, so moving the file is a data migration whose failure mode is
  losing a real user's household. No.

- **Excluding only `chore_app.sqlite`.** Rejected: leaves the journal name
  uncovered for no saving (§1.3).

- **Doing nothing this wave.** Considered seriously, because iOS has no
  distribution channel today (the release artefact is a signed APK) so present
  user exposure is zero, and because the fix is unverifiable in CI. Rejected
  because the change is ~25 lines of Foundation-only Swift with no Dart-side
  risk, the reasoning is loaded now, and A-3's decision D-B1 is already
  recorded — leaving the iOS half open means the *next* person has to redo
  §1 to find out that the row's own Files column is wrong.

### Why this cannot affect the F-1 background isolate

The single hard constraint. The exclusion is **not** in `openConnection()`,
which `notification_action_handler.dart:121` calls; the Dart change in this
plan is a constant extraction with no runtime effect. On the Swift side the code
runs in `application(_:didFinishLaunchingWithOptions:)` and touches only
`FileManager` and `URLResourceValues` — no `FlutterMethodChannel`, no
`FlutterPluginRegistry`, no plugin registration. It does not touch
`didInitializeImplicitFlutterEngine` or the
`FlutterLocalNotificationsPlugin.setPluginRegistrantCallback` wiring, which is
the fragile chain F-1 GATE 1 proved on a physical device. Even when iOS launches
the app in the background to deliver a notification action, the worst this code
can do is fail an attribute write, which `try?` swallows.

### Failure posture and ordering

- **Never crashes, never blocks launch.** Every fallible call is `try?` or a
  `guard`. No `try!`, no `!` force-unwrap. If the whole thing fails the app
  starts normally with a backed-up database — a backup attribute is not worth a
  launch crash.
- **Idempotent.** Setting the attribute on a file that already has it is a
  no-op; setting it on a file that does not exist is skipped by an explicit
  `fileExists` check. Re-applied on every launch by design.
- **Runs before `super.application(...)`**, i.e. before the Dart entrypoint can
  ask drift for a connection. On a *fresh* install the database file does not
  exist yet, so the per-file loop skips it — which is why the **directory** is
  excluded too: `isExcludedFromBackup` on a directory covers its contents,
  including files created later, so the first-launch window is covered by the
  directory attribute and every later launch additionally pins the file itself.
  This ordering is also why the directory call comes first.
- **Android is untouched.** No Dart code runs, no channel exists, nothing to
  guard with `Platform.isIOS`. This is the main reason the Swift-only shape is
  attractive: the regression it *cannot* cause is one only Android CI could
  catch.

---

## 3. Scope of the exclusion: the directory, not just the file

`Documents/` for this app contains exactly one thing, the drift database
(grep: nothing else in `lib/` writes there; the "Export data" row hands its
file to the share sheet). Excluding the directory is also the closer analogue
of Android's `allowBackup="false"`, which excludes the *entire* app sandbox
rather than three files — so directory-level exclusion is what D-B1's decision
actually means on iOS.

The cost is a trap for a future feature that puts a user-facing document in
`Documents/` and silently gets no backup. That is recorded in a comment at the
call site and in `docs/app-lifecycle.md` G8.

---

## 4. Tasks

**Task 1 (doc).** This plan. Commit alone.

**Task 2 (RED).** Extract `const String databaseName = 'chore_app';` in
`app_database.dart` and use it in `openConnection()` — a compile-time constant
substitution, no behaviour change — with a doc comment naming the
`AppDelegate.swift` coupling. Add
`test/data/db/ios_backup_exclusion_test.dart`, which reads
`ios/Runner/AppDelegate.swift` and asserts it contains the literal
`"$databaseName.sqlite"` and the three sidecar literals
(`-journal`, `-wal`, `-shm`).

Expected RED, at the *test* step: `Expected: contains '"chore_app.sqlite"'`
against the current AppDelegate source.

**What this test does and does not prove.** It is a cross-language *mirror*
check and nothing more: it proves the file names the Swift hardcodes are the
names Dart actually uses, so renaming the drift database can no longer silently
un-exclude it. It proves nothing about whether the Swift compiles, runs, or
sets any attribute. It exists precisely because §1.5 means no job in this repo
can prove any of that. A second assertion in the same file — that
`AppDelegate.swift` contains no `try!` — is a standing regression guard, not a
TDD'd behaviour; it is already green and is labelled as such.

**Task 3 (GREEN).** Implement `excludeLocalDatabaseFromBackup()` in
`AppDelegate.swift` and call it from
`application(_:didFinishLaunchingWithOptions:)` before `super`.

**Task 4 (inversion).** Break one of the four Swift literals, push, confirm the
red lands at the test step, then `git revert` it (append-only history; this
branch must not be force-pushed).

**Task 5 (docs).** Close backlog A-3b at both of its occurrences using the
`CLOSED <date> … Was:` convention A-7 and G-12 use, **correcting the Files
column (§1.4) and the `-wal`/`-shm` premise (§1.3) in the closure text rather
than deleting the original problem statement.** Update
`docs/app-lifecycle.md` G8, whose D-B1 resolution note currently says iOS
exclusion is "tracked separately as A-3b, deliberately out of scope".

---

## 5. What stays unverified after this lands

- **That the Swift compiles.** Verify with the same command `e2e.yml`'s `ios`
  job uses:
  `flutter build ios --simulator --debug --dart-define=E2E_TODAY=2026-07-24 --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=`
- **That the attribute is actually set on a device or simulator.** The check is
  `xattr -l <container>/Documents/chore_app.sqlite` showing
  `com.apple.metadata:com_apple_backup_excludeItem`, on an installed build.
  Nothing automated can reach this.
- **That an iCloud restore then omits the database.** Only a real
  backup/restore cycle on a real device shows this. Not planned.

---

## 6. What A-3b does *not* fix (new backlog row material)

Because the Supabase refresh token is in `NSUserDefaults`, not the database
(§1.6), an iCloud restore onto a second device still restores the *session*.
That is benign on its own and does not reopen the clobber hazard: the household
link, the pull cursor and the dirty flags (`settings.syncHouseholdId`,
`settings.syncLastPulledAt`, per-table `syncDirty`) all live in the database, so
a device that restores the session without the database lands on the welcome
screen as a signed-in user with no household — it has nothing to push and no
cursor to push it against. The clobber vector is the database, and this fix
removes it. The leftover is a disclosure/tidiness point, not a data-integrity
one, and iOS offers no supported way to exclude the preferences plist anyway.
Recorded here rather than opened as a row.
