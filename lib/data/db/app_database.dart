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
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      // v1 -> v2 (spec `docs/specs/notifications.md`): adds the `settings`
      // table. [migrator.createTable] always builds the table from its
      // *current* (here, v8) column set, so a fresh v1 -> v8 jump already
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
          // 1), `settings` itself didn't exist before v2, so a v1 -> v10
          // jump already gets this column for free via [createTable]
          // above, and adding it again here would throw a
          // duplicate-column error.
          await migrator.addColumn(settings, settings.membershipRevoked);
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
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Opens the on-device, platform-appropriate database file.
///
/// Kept separate from [AppDatabase]'s constructor (which only depends on
/// plain drift and takes a [QueryExecutor]) so tests can construct
/// `AppDatabase(NativeDatabase.memory())` without pulling in Flutter.
QueryExecutor openConnection() => driftDatabase(name: 'chore_app');
