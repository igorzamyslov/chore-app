/// The application's local drift/SQLite database.
library;

import 'package:chore_app/data/db/converters.dart';
import 'package:chore_app/data/db/tables.dart';
// The generated `app_database.g.dart` part file below references
// `PlainDateConverter`/`RecurrenceConverter` and the `PlainDate`/`Recurrence`
// types they convert directly, so this library needs them in scope even
// though this hand-written file doesn't name them itself.
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

export 'package:chore_app/data/db/tables.dart';

part 'app_database.g.dart';

/// The application's local SQLite database.
///
/// This class takes a plain [QueryExecutor] via its constructor so tests can
/// construct it directly with an in-memory executor:
///
/// ```dart
/// AppDatabase(NativeDatabase.memory());
/// ```
///
/// The real app should instead use [openConnection], which opens a
/// persistent, platform-appropriate database file via drift_flutter:
///
/// ```dart
/// AppDatabase(openConnection());
/// ```
@DriftDatabase(
  tables: [
    Households,
    Members,
    Categories,
    Chores,
    ChoreAssignees,
    ChoreOccurrences,
    ShoppingItems,
    Settings,
    ReminderSnoozes,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Creates a database that sends its queries to [executor].
  //
  // A super parameter isn't used here because the generated superclass
  // names its positional parameter `e`, which would trip
  // `matching_super_parameters`.
  // ignore: use_super_parameters
  AppDatabase(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      // v1 -> v2 (spec `docs/specs/notifications.md`): adds the `settings`
      // table. [migrator.createTable] always builds the table from its
      // *current* (here, v12) column set, so a fresh v1 -> v12 jump already
      // gets every later column for free — the branches below only need
      // to backfill whichever columns an install that already has an
      // older-shaped `settings` table is still missing (a "create then
      // immediately re-add the same column" pair would otherwise throw a
      // duplicate-column error).
      if (from < 2) {
        await migrator.createTable(settings);
      } else {
        if (from < 3) {
          // v2 -> v3 (spec `docs/specs/members-management.md`): adds the
          // nullable `settings.actingMemberId` column, defaulting to
          // `NULL` (the automatic acting-member fallback).
          await migrator.addColumn(settings, settings.actingMemberId);
        }
        if (from < 4) {
          // v3 -> v4 (spec `docs/next-session-plan.md` #5): adds the
          // nullable `settings.locale` column, defaulting to `NULL`
          // (follow the OS locale).
          await migrator.addColumn(settings, settings.locale);
        }
        if (from < 5) {
          // v4 -> v5 (spec `docs/specs/polish-round-1.md` G2/G3): the two
          // shown-once flags for the first-run name prompt and the digest
          // pre-permission explainer, both defaulting to `NULL` (never
          // shown).
          await migrator.addColumn(
            settings,
            settings.onboardingNamePromptShownAt,
          );
          await migrator.addColumn(settings, settings.digestPrepromptShownAt);
        }
        if (from < 6) {
          // v5 -> v6 (spec `docs/specs/sync-backend.md` §7.1): the two
          // linked-state columns, both defaulting to `NULL` (unlinked) --
          // no data rewrite.
          await migrator.addColumn(settings, settings.syncHouseholdId);
          await migrator.addColumn(settings, settings.syncLinkedAt);
        }
        if (from < 7) {
          // v6 -> v7 (spec `docs/feedback/2026-08-01-field-feedback.md`
          // G2): the nullable `settings.themeMode` column, defaulting to
          // `NULL` (follow the OS theme) -- no data rewrite.
          await migrator.addColumn(settings, settings.themeMode);
        }
        if (from < 8) {
          // v7 -> v8 (spec `docs/specs/sync-backend.md` §8.1): the
          // nullable `settings.syncLastPulledAt` pull-cursor column,
          // defaulting to `NULL` (no pull yet) -- no data rewrite.
          await migrator.addColumn(settings, settings.syncLastPulledAt);
        }
        if (from < 10) {
          // v9 -> v10 (spec `docs/specs/household-lifecycle.md` §3.5): the
          // `settings.membershipRevoked` flag, defaulting to `false` (not
          // revoked) -- no data rewrite. Lives here, inside the `else`
          // branch, rather than as an unconditional backfill below: unlike
          // `households`/`members`/etc (which existed since schemaVersion
          // 1), `settings` itself didn't exist before v2, so a v1 -> v12
          // jump already gets this column for free via [createTable]
          // above, and adding it again here would throw a
          // duplicate-column error.
          await migrator.addColumn(settings, settings.membershipRevoked);
        }
        if (from < 12) {
          // v11 -> v12 (spec `docs/specs/onboarding-v2.md` §1): the
          // nullable `settings.pendingJoinCode` prefill column, defaulting
          // to `NULL` (no join in progress) -- no data rewrite. Lives here,
          // inside the `else` branch, for exactly the reason spelled out
          // for `membershipRevoked` directly above: `settings` did not
          // exist before v2, so a v1 -> v12 jump builds the table at full
          // current width via [createTable], and a second unconditional
          // `addColumn` for the same column would throw a duplicate-column
          // error.
          await migrator.addColumn(settings, settings.pendingJoinCode);
        }
        if (from < 13) {
          // v12 -> v13 (spec `docs/specs/notifications-n2.md` §8.1): quiet
          // hours (3 columns) and the evening re-reminder (2 columns), all
          // with defaults, no data rewrite. Both features default OFF, so
          // this upgrade changes the behaviour of exactly zero installs
          // until someone opens Settings.
          //
          // Lives here, inside the `else` branch, for exactly the reason
          // spelled out for `membershipRevoked` and `pendingJoinCode`
          // above: `settings` did not exist before v2, so a v1 -> v13 jump
          // builds the table at full current width via [createTable], and a
          // second unconditional `addColumn` for the same column would
          // throw a duplicate-column error. §8.1 states that this
          // placement is not a free choice.
          await migrator.addColumn(settings, settings.quietHoursEnabled);
          await migrator.addColumn(settings, settings.quietStartMinutes);
          await migrator.addColumn(settings, settings.quietEndMinutes);
          await migrator.addColumn(settings, settings.eveningReminderEnabled);
          await migrator.addColumn(settings, settings.eveningReminderMinutes);
        }
      }
      if (from < 8) {
        // v7 -> v8 (spec `docs/specs/sync-backend.md` §8.1): every synced
        // table -- households, members, categories, chores,
        // chore_assignees, chore_occurrences, shopping_items (NOT
        // `settings`, which is device-scoped and never synced, spec §0) --
        // gains `syncDirty`, defaulting to `false`. These 7 tables have
        // all existed since schemaVersion 1, so (unlike `settings`'s own
        // columns above, which `createTable` already covers for a v1 -> v8
        // jump) this backfill runs unconditionally whenever `from < 8`,
        // regardless of which branch above ran.
        await migrator.addColumn(households, households.syncDirty);
        await migrator.addColumn(members, members.syncDirty);
        await migrator.addColumn(categories, categories.syncDirty);
        await migrator.addColumn(chores, chores.syncDirty);
        await migrator.addColumn(choreAssignees, choreAssignees.syncDirty);
        await migrator.addColumn(
          choreOccurrences,
          choreOccurrences.syncDirty,
        );
        await migrator.addColumn(shoppingItems, shoppingItems.syncDirty);
      }
      if (from < 9) {
        // v8 -> v9 (spec `docs/feedback/2026-08-01-ux-audit.md` A1): adds
        // the nullable `members.deletedAt` soft-delete column, defaulting
        // to `NULL` (active) -- no data rewrite. `members` has existed
        // since schemaVersion 1, so this backfill runs unconditionally
        // whenever `from < 9`, mirroring the `syncDirty` backfill above.
        await migrator.addColumn(members, members.deletedAt);
      }
      if (from < 11) {
        // v10 -> v11 (spec `docs/specs/stats.md` §2.3): adds the
        // `(status, closed_on)` index on `chore_occurrences`, which serves
        // the chore-history window aggregate. Index-only: no column is
        // added and no row is rewritten.
        //
        // Flat and unconditional, NOT inside the `settings` `else` branch
        // above — that branch exists solely because `settings` itself
        // didn't exist before v2, so `createTable` there already builds it
        // at full width and a second `addColumn` would duplicate-add.
        // Nothing analogous applies to an index on `chore_occurrences`,
        // which has existed since schemaVersion 1: this is the same
        // unconditional shape the `syncDirty` (v8) and `members.deletedAt`
        // (v9) backfills above use.
        //
        // A plain `CREATE INDEX` (drift's [Migrator.createIndex] offers no
        // `IF NOT EXISTS` form) is correct rather than merely tolerable: no
        // install at any shipped version 1..10 can already carry this
        // index, since it is introduced here. A collision would therefore
        // mean the upgrade path itself is wrong, and throwing is the right
        // way to find that out.
        await migrator.createIndex(choreOccurrencesStatusClosedOnIdx);
      }
      if (from < 13) {
        // v12 -> v13 (spec `docs/specs/notifications-n2.md` §8.2/§8.3): the
        // nullable `chores.reminderMinutes` column, defaulting to `NULL`
        // (no individual reminder), and the device-scoped, unsynced
        // `reminder_snoozes` table -- no data rewrite for either.
        //
        // Flat and UNCONDITIONAL, NOT inside the `settings` `else` branch
        // above, and the distinction is the whole trap that branch exists
        // to document. `chores` has existed since schemaVersion 1, so
        // `createTable` never covers this column on any path and an
        // `else`-placed backfill would skip it entirely for a v1 install.
        // Same shape as the `syncDirty` (v8) and `members.deletedAt` (v9)
        // backfills above.
        await migrator.addColumn(chores, chores.reminderMinutes);
        // The table is introduced HERE, so no install at any shipped
        // version 1..12 can already carry it, and a plain `createTable`
        // (drift offers no `IF NOT EXISTS` form) throwing would mean the
        // upgrade path itself is wrong -- which is worth finding out. Same
        // reasoning as the `from < 11` index above.
        await migrator.createTable(reminderSnoozes);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// The drift database's base name. `drift_flutter` turns this into a file
/// called `$databaseName.sqlite` inside `getApplicationDocumentsDirectory()`.
///
/// A named constant rather than a literal because
/// `ios/Runner/AppDelegate.swift` **mirrors these file names** to exclude them
/// from iCloud/iTunes backup (backlog A-3b), and no CI job on a pull request
/// compiles or runs that Swift — so a rename here that forgot the Swift side
/// would silently un-exclude the database, with nothing red anywhere. The
/// mirror is pinned by `test/data/db/ios_backup_exclusion_test.dart`.
const String databaseName = 'chore_app';

/// Opens the on-device, platform-appropriate database file.
///
/// Kept separate from [AppDatabase]'s constructor (which only depends on
/// plain drift and takes a [QueryExecutor]) so tests can construct
/// `AppDatabase(NativeDatabase.memory())` without pulling in Flutter.
///
/// **Called from two isolates** — `appDatabaseProvider` on the main isolate and
/// `notification_action_handler.dart`'s background isolate (F-1). Nothing that
/// needs a platform channel may be added here: the background engine's ability
/// to resolve `path_provider` at all is the one thing in this codebase that was
/// proven on a physical device, and every channel added to this path is another
/// way to lose that. Launch-time-only work belongs in `main.dart` or in the
/// platform runner (see A-3b's backup exclusion, which is pure Swift for
/// exactly this reason).
QueryExecutor openConnection() => driftDatabase(name: databaseName);
