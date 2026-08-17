import 'dart:io';

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drops `syncDirty` (schema v8, spec `docs/specs/sync-backend.md` §8.1)
/// from every one of the 7 synced tables on [seed] -- every test below that
/// simulates a pre-v8 install needs this: [seed] always opens at the
/// *current* (v8) schema first (so every table, `settings` included,
/// already has its full column set), and these 7 tables have existed since
/// schemaVersion 1, so without this drop the later `onUpgrade` would try to
/// `ADD COLUMN sync_dirty` on a column that's already there and throw a
/// duplicate-column error.
Future<void> _dropSyncDirtyColumns(AppDatabase seed) async {
  for (final table in const [
    'households',
    'members',
    'categories',
    'chores',
    'chore_assignees',
    'chore_occurrences',
    'shopping_items',
  ]) {
    await seed.customStatement('ALTER TABLE $table DROP COLUMN sync_dirty');
  }
}

/// Drops `deleted_at` (schema v9, spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1) from `members` on [seed] --
/// mirrors `_dropSyncDirtyColumns`'s reasoning for the same collateral-drop
/// pattern, one column narrower: only `members` gains a column at v9 (the
/// other 6 synced tables are unaffected), but [seed] still always opens at
/// the *current* (now v9) schema first, so every test below that simulates
/// a pre-v9 install needs this too, or the later `onUpgrade` would try to
/// `ADD COLUMN deleted_at` on a column that's already there.
Future<void> _dropMemberDeletedAtColumn(AppDatabase seed) async {
  await seed.customStatement('ALTER TABLE members DROP COLUMN deleted_at');
}

/// Drops `membership_revoked` (schema v10, spec
/// `docs/specs/household-lifecycle.md` §3.5) from `settings` on [seed] --
/// mirrors `_dropMemberDeletedAtColumn`'s reasoning for the same
/// collateral-drop pattern: [seed] always opens at the *current* (now v12)
/// schema first, so every test below that simulates a pre-v10 install
/// needs this, or the later `onUpgrade` would try to `ADD COLUMN
/// membership_revoked` on a column that's already there.
Future<void> _dropMembershipRevokedColumn(AppDatabase seed) async {
  await seed.customStatement(
    'ALTER TABLE settings DROP COLUMN membership_revoked',
  );
}

/// Drops the `(status, closed_on)` index (schema v11, spec
/// `docs/specs/stats.md` §2.3) from `chore_occurrences` on [seed] -- the
/// same collateral-drop pattern as the column helpers above, one rung down
/// the schema-object hierarchy, and needed by every test below whose seed
/// rewinds `user_version` BELOW 11 -- all of them except the `11 -> 12`
/// test, whose seed must KEEP the index (at `from == 11` the `from < 11`
/// branch never runs, so a real v11 install still has it).
///
/// The reason it is needed at all: `onUpgrade`'s `from < 11` branch
/// issues a plain `CREATE INDEX` (drift's [Migrator.createIndex] has no
/// `IF NOT EXISTS` form), which is exactly right in production -- no
/// install at any shipped version 1..10 can have this index, so a
/// collision would be a genuine bug worth throwing on. But [seed] always
/// opens at the *current* (v12) schema first, so `onCreate` has already
/// created the index, and rewinding `user_version` alone does not remove
/// it. Without this drop, a test rewound below 11 would hit "index ...
/// already exists" -- an artifact of the harness, not of the migration.
Future<void> _dropStatusClosedOnIndex(AppDatabase seed) async {
  await seed.customStatement(
    'DROP INDEX IF EXISTS chore_occurrences_status_closed_on_idx',
  );
}

/// Drops `pending_join_code` (schema v12, spec
/// `docs/specs/onboarding-v2.md` §1) from `settings` on [seed] -- mirrors
/// `_dropMembershipRevokedColumn`'s reasoning for the same collateral-drop
/// pattern: [seed] always opens at the *current* (now v12) schema first, so
/// every test below that simulates a pre-v12 install needs this, or the
/// later `onUpgrade` would try to `ADD COLUMN pending_join_code` on a
/// column that's already there.
Future<void> _dropPendingJoinCodeColumn(AppDatabase seed) async {
  await seed.customStatement(
    'ALTER TABLE settings DROP COLUMN pending_join_code',
  );
}

/// Every `settings` column added by a migration AFTER the table itself
/// arrived at v2 -- which is exactly the set a pre-v12 seed below has to
/// drop and the upgrade under test has to put back.
const _settingsColumnsAddedAfterV2 = [
  'acting_member_id', // v3
  'locale', // v4
  'onboarding_name_prompt_shown_at', // v5
  'digest_preprompt_shown_at', // v5
  'sync_household_id', // v6
  'sync_linked_at', // v6
  'theme_mode', // v7
  'sync_last_pulled_at', // v8
  'membership_revoked', // v10
  'pending_join_code', // v12
];

/// The names of the columns [table] actually has on disk, straight from
/// `PRAGMA table_info`.
///
/// This is the EXISTENCE half of every column-addition assertion below, and
/// it is not decoration: a bare `expect(row.someNullableColumn, isNull)` is
/// VACUOUS. Drift maps an ABSENT nullable column to `null` on read, so such
/// an assertion passes identically whether the migration added the column or
/// did nothing whatsoever. That is not a theory -- deleting the `from < 7`
/// branch left all four tests asserting `themeMode` green, including the one
/// whose title is "adds themeMode".
///
/// Non-nullable columns do self-guard (drift throws rather than inventing a
/// value -- deleting the `households.syncDirty` backfill turned the
/// `7 -> 12` test red on the spot), but the assertions below cover both
/// kinds anyway, so nobody reading them has to remember which column is
/// which.
///
/// A SET of names, asserted with `containsAll`, rather than the per-column
/// `hasLength(1)` count that the `9 -> 12` and `11 -> 12` tests use inline:
/// `containsAll` says exactly what each test is about ("this upgrade
/// produced these columns") and needs no edit when a later migration adds
/// one more. The two shapes are equal in strength -- SQLite rejects a
/// duplicate `ADD COLUMN` at migration time, so a name can never appear
/// twice on disk -- so those two are left exactly as they are, since the
/// prose around them documents the else-branch placement reasoning.
Future<Set<String>> _columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect("PRAGMA table_info('$table')").get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  test(
    'schemaVersion 1 -> 2 upgrade creates the settings table with defaults',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v1 install without hand-copying v1's
      // CREATE TABLE SQL (which would drift out of sync with tables.dart
      // over time): open the *current* (v12) schema once against a real
      // file so `onCreate` materializes every table, including the v2-only
      // `settings` table, then drop that table (plus `syncDirty` from
      // every OTHER table -- see `_dropSyncDirtyColumns`, added at v8 --
      // and `members.deletedAt`, added at v9 -- see
      // `_dropMemberDeletedAtColumn`) and roll `user_version` back to 1 —
      // reproducing exactly what a real v1 database on a user's device
      // looks like. Dropping the whole `settings` table also covers
      // `membership_revoked` (added at v10) and `pending_join_code` (added
      // at v12) -- there's no separate collateral drop needed for either
      // here, unlike the versioned-upgrade tests below.
      final seed = AppDatabase(NativeDatabase(file));
      await seed.customStatement('DROP TABLE settings');
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await seed.customStatement('PRAGMA user_version = 1');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 1` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 1, 12)` —
      // exactly the real upgrade path a v1 user's device would go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      // The table exists, and a bare insert (letting the schema defaults
      // apply for digestEnabled/digestMinutes) gets the spec's defaults.
      await upgraded
          .into(upgraded.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
      expect(row.syncLastPulledAt, isNull);
      expect(row.membershipRevoked, isFalse);
      // Existence, not just default value -- the two assertions above
      // cannot fail on their own (see `_columnNames`). This is the
      // v1 -> v12 path, where `createTable` is solely responsible for
      // every column after v2: if it ever stopped building the table at
      // full current width, the `else` branch's backfills would NOT
      // cover for it, because this path never enters that branch.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(settingsColumns, containsAll(_settingsColumnsAddedAfterV2));

      // Pre-existing v1 data survived the upgrade untouched.
      final households = await upgraded.select(upgraded.households).get();
      expect(households, isEmpty);
    },
  );

  test(
    'a fresh (never-opened) database is created at the current '
    'schemaVersion (12) directly, settings table included with every '
    'column -- membershipRevoked and pendingJoinCode among them',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // No upgrade path is exercised here (`onCreate`'s default
      // `Migrator.createAll()` already creates every table at the full
      // CURRENT column set, `settings` included) — this just guards
      // against a regression where a fresh install would need `onUpgrade`
      // to get a column -- `membershipRevoked` (added at v10) and
      // `pendingJoinCode` (added at v12) included.
      final rows = await db.select(db.settings).get();
      expect(rows, isEmpty);

      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      final row = await db.select(db.settings).getSingle();
      expect(row.membershipRevoked, isFalse);
      expect(row.pendingJoinCode, isNull);
      // Existence, not just default value -- `expect(row.pendingJoinCode,
      // isNull)` above cannot fail on its own (see `_columnNames`), which
      // would hollow out this test's entire purpose: it exists to prove a
      // fresh install needs no `onUpgrade` to get its columns.
      final columns = await _columnNames(db, 'settings');
      expect(columns, containsAll(_settingsColumnsAddedAfterV2));
    },
  );

  test(
    'schemaVersion 3 -> 12 upgrade adds locale, both shown-once flags, the '
    'sync-linked columns, themeMode, syncLastPulledAt, and '
    'membershipRevoked (NULL/false by default), keeping the existing '
    'settings row',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v4_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v3 install without hand-copying v3's CREATE
      // TABLE SQL: open the *current* schema once against a real file so
      // `onCreate` materializes every table with its full current column
      // set, insert a settings row with a non-NULL actingMemberId (so the
      // upgrade's "existing row survives" guarantee is actually exercised
      // for both pre-existing columns), then drop every column newer than
      // v3 (plus `syncDirty` from every other table -- see
      // `_dropSyncDirtyColumns`, added at v8) and roll `user_version` back
      // to 3 — reproducing exactly what a real v3 database on a user's
      // device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
            ),
          );
      await seed.customStatement('ALTER TABLE settings DROP COLUMN locale');
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN onboarding_name_prompt_shown_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN digest_preprompt_shown_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_household_id',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_linked_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN theme_mode',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 3');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 3` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 3, 12)` —
      // exactly the real upgrade path a v3 user's device would go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.locale, isNull);
      expect(row.onboardingNamePromptShownAt, isNull);
      expect(row.digestPrepromptShownAt, isNull);
      expect(row.syncHouseholdId, isNull);
      expect(row.syncLinkedAt, isNull);
      expect(row.themeMode, isNull);
      expect(row.syncLastPulledAt, isNull);
      expect(row.membershipRevoked, isFalse);
      // Existence, not just default value -- the assertions above
      // cannot fail on their own (see `_columnNames`). Every `settings`
      // column this test's own seed dropped must be back.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(
        settingsColumns,
        containsAll([
          'locale',
          'onboarding_name_prompt_shown_at',
          'digest_preprompt_shown_at',
          'sync_household_id',
          'sync_linked_at',
          'theme_mode',
          'sync_last_pulled_at',
          'membership_revoked',
          'pending_join_code',
        ]),
      );
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 2 -> 12 upgrade adds every later settings column, '
    'keeping the existing settings row -- this app never actually stops '
    'at an intermediate version once schemaVersion is 12, so this '
    'supersedes earlier per-step tests',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v2_to_v4_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v2 install: open the *current* (v12) schema
      // once so `onCreate` materializes every table with its full v12
      // column set, insert a settings row, then drop every column newer
      // than v2 (plus `syncDirty` from every other table -- see
      // `_dropSyncDirtyColumns`, added at v8 -- `members.deletedAt`, added
      // at v9 -- see `_dropMemberDeletedAtColumn` -- and
      // `membershipRevoked`, added at v10 -- see
      // `_dropMembershipRevokedColumn`) and roll `user_version` back to 2 —
      // reproducing exactly what a real v2 database on a user's device
      // looks like, so the `from < 2` branch is never hit and every `if
      // (from < N)` backfill inside the `else` branch runs in the same
      // upgrade.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN acting_member_id',
      );
      await seed.customStatement('ALTER TABLE settings DROP COLUMN locale');
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN onboarding_name_prompt_shown_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN digest_preprompt_shown_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_household_id',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_linked_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN theme_mode',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 2');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 2` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 2, 12)`.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.actingMemberId, isNull);
      expect(row.locale, isNull);
      expect(row.onboardingNamePromptShownAt, isNull);
      expect(row.digestPrepromptShownAt, isNull);
      expect(row.syncHouseholdId, isNull);
      expect(row.syncLinkedAt, isNull);
      expect(row.themeMode, isNull);
      expect(row.syncLastPulledAt, isNull);
      expect(row.membershipRevoked, isFalse);
      // Existence, not just default value -- the assertions above cannot
      // fail on their own (see `_columnNames`). A v2 seed drops every
      // post-v2 column, so this upgrade owes all of them.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(settingsColumns, containsAll(_settingsColumnsAddedAfterV2));
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 5 -> 12 upgrade adds syncHouseholdId, syncLinkedAt, '
    'themeMode, syncLastPulledAt, and membershipRevoked (NULL/false by '
    'default, no data rewrite), keeping the existing settings row',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v6_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v5 install: open the *current* (v12) schema
      // once so `onCreate` materializes every table with its full v12
      // column set, insert a settings row with a non-NULL actingMemberId
      // (so the upgrade's "existing row survives" guarantee is actually
      // exercised), then drop every column newer than v5 (plus `syncDirty`
      // from every other table -- see `_dropSyncDirtyColumns`, added at
      // v8 -- `members.deletedAt`, added at v9 -- see
      // `_dropMemberDeletedAtColumn` -- and `membershipRevoked`, added at
      // v10 -- see `_dropMembershipRevokedColumn`) and roll `user_version`
      // back to 5 -- reproducing exactly what a real v5 database on a
      // user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
            ),
          );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_household_id',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_linked_at',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN theme_mode',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 5');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 5` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 5, 12)`
      // -- exactly the real upgrade path a v5 user's device would go
      // through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.syncHouseholdId, isNull);
      expect(row.syncLinkedAt, isNull);
      expect(row.themeMode, isNull);
      expect(row.syncLastPulledAt, isNull);
      expect(row.membershipRevoked, isFalse);
      // Existence, not just default value -- the assertions above
      // cannot fail on their own (see `_columnNames`). Every `settings`
      // column this test's own seed dropped must be back.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(
        settingsColumns,
        containsAll([
          'sync_household_id',
          'sync_linked_at',
          'theme_mode',
          'sync_last_pulled_at',
          'membership_revoked',
          'pending_join_code',
        ]),
      );
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 6 -> 12 upgrade adds themeMode, syncLastPulledAt, and '
    'membershipRevoked (NULL/false by default, no data rewrite), keeping '
    'the existing settings row',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v7_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v6 install: open the *current* (v12) schema
      // once so `onCreate` materializes every table with its full v12
      // column set, insert a settings row with a non-NULL actingMemberId
      // and a non-NULL syncHouseholdId (so the upgrade's "existing row
      // survives" guarantee is actually exercised for both pre-existing
      // columns), then drop the v7/v8-only columns (plus `syncDirty` from
      // every other table -- see `_dropSyncDirtyColumns`, added at v8 --
      // `members.deletedAt`, added at v9 -- see
      // `_dropMemberDeletedAtColumn` -- and `membershipRevoked`, added at
      // v10 -- see `_dropMembershipRevokedColumn`) and roll `user_version`
      // back to 6 -- reproducing exactly what a real v6 database on a
      // user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
              syncHouseholdId: const Value('household-1'),
            ),
          );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN theme_mode',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 6');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 6` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 6, 12)`
      // -- exactly the real upgrade path a v6 user's device would go
      // through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.themeMode, isNull);
      expect(row.syncLastPulledAt, isNull);
      expect(row.membershipRevoked, isFalse);
      // Existence, not just default value -- the assertions above
      // cannot fail on their own (see `_columnNames`). Every `settings`
      // column this test's own seed dropped must be back.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(
        settingsColumns,
        containsAll([
          'theme_mode',
          'sync_last_pulled_at',
          'membership_revoked',
          'pending_join_code',
        ]),
      );
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.syncHouseholdId, 'household-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 7 -> 12 upgrade adds syncDirty (default false) to every '
    'synced table and syncLastPulledAt/membershipRevoked (NULL/false) to '
    'settings, keeping existing rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v8_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v7 install: open the *current* (v12) schema
      // once so `onCreate` materializes every table with its full v12
      // column set, insert one row into every synced table (so the
      // upgrade's "existing rows survive, syncDirty defaults to false"
      // guarantee is actually exercised everywhere, not just on
      // `settings`), then drop `syncDirty` from all 7 of those tables,
      // `members.deletedAt` (added at v9 -- see
      // `_dropMemberDeletedAtColumn`), and `syncLastPulledAt` and
      // `membershipRevoked` (added at v10 -- see
      // `_dropMembershipRevokedColumn`) from `settings`, and roll
      // `user_version` back to 7 -- reproducing exactly what a real v7
      // database on a user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.households)
          .insert(
            HouseholdsCompanion.insert(
              id: 'h1',
              name: 'Household',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.members)
          .insert(
            MembersCompanion.insert(
              id: 'm1',
              householdId: 'h1',
              name: 'Me',
              color: 1,
              role: MemberRole.admin,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'c1',
              householdId: 'h1',
              kind: CategoryKind.chore,
              name: 'Cleaning',
              icon: 'cleaning_services',
              color: 1,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.chores)
          .insert(
            ChoresCompanion.insert(
              id: 'ch1',
              householdId: 'h1',
              title: 'Dishes',
              startDate: PlainDate(2026, 1, 1),
              assignmentMode: AssignmentMode.anyone,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.choreAssignees)
          .insert(
            ChoreAssigneesCompanion.insert(
              choreId: 'ch1',
              memberId: 'm1',
              position: 0,
            ),
          );
      await seed
          .into(seed.choreOccurrences)
          .insert(
            ChoreOccurrencesCompanion.insert(
              id: 'o1',
              choreId: 'ch1',
              dueDate: PlainDate(2026, 1, 1),
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: 's1',
              householdId: 'h1',
              name: 'Milk',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await _dropSyncDirtyColumns(seed);
      await _dropMemberDeletedAtColumn(seed);
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 7');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 7` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 7, 12)`
      // -- exactly the real upgrade path a v7 user's device would go
      // through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final household = await upgraded.select(upgraded.households).getSingle();
      expect(household.id, 'h1');
      expect(household.name, 'Household');
      expect(household.syncDirty, isFalse);

      final member = await upgraded.select(upgraded.members).getSingle();
      expect(member.id, 'm1');
      expect(member.name, 'Me');
      expect(member.syncDirty, isFalse);
      expect(member.deletedAt, isNull);
      // `deletedAt` is nullable, so the assertion directly above cannot
      // fail on its own (see `_columnNames`) -- unlike the `syncDirty` ones
      // around it. `members` has existed since v1, so the table-age
      // reasoning differs from `settings`, but the READ vacuity is
      // identical: it is a property of nullability, not of the table.
      final memberColumns = await _columnNames(upgraded, 'members');
      expect(memberColumns, containsAll(['sync_dirty', 'deleted_at']));

      final category = await upgraded.select(upgraded.categories).getSingle();
      expect(category.id, 'c1');
      expect(category.name, 'Cleaning');
      expect(category.syncDirty, isFalse);

      final chore = await upgraded.select(upgraded.chores).getSingle();
      expect(chore.id, 'ch1');
      expect(chore.title, 'Dishes');
      expect(chore.syncDirty, isFalse);

      final assignee = await upgraded
          .select(upgraded.choreAssignees)
          .getSingle();
      expect(assignee.choreId, 'ch1');
      expect(assignee.memberId, 'm1');
      expect(assignee.syncDirty, isFalse);

      final occurrence = await upgraded
          .select(upgraded.choreOccurrences)
          .getSingle();
      expect(occurrence.id, 'o1');
      expect(occurrence.syncDirty, isFalse);

      final item = await upgraded.select(upgraded.shoppingItems).getSingle();
      expect(item.id, 's1');
      expect(item.name, 'Milk');
      expect(item.syncDirty, isFalse);

      final settingsRow = await upgraded.select(upgraded.settings).getSingle();
      expect(settingsRow.syncLastPulledAt, isNull);
      expect(settingsRow.membershipRevoked, isFalse);
      // Existence, not just default value -- the assertions above
      // cannot fail on their own (see `_columnNames`). Every `settings`
      // column this test's own seed dropped must be back.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(
        settingsColumns,
        containsAll([
          'sync_last_pulled_at',
          'membership_revoked',
          'pending_join_code',
        ]),
      );
      // Pre-existing settings data survived the upgrade untouched.
      expect(settingsRow.createdAt, 't0');
      expect(settingsRow.digestEnabled, isTrue);
    },
  );

  test(
    'schemaVersion 8 -> 12 upgrade adds members.deletedAt and '
    'settings.membershipRevoked (NULL/false by default, no data rewrite), '
    'keeping the existing member row',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v9_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v8 install: open the *current* (v12) schema
      // once so `onCreate` materializes every table with its full v12
      // column set -- `settings` included, even though this test never
      // inserts a row into it, so its `membership_revoked` column (added
      // at v10) must be dropped too, or the upgrade below throws a
      // duplicate-column error -- insert a household + member row (so the
      // upgrade's "existing row survives, deletedAt defaults to NULL"
      // guarantee is actually exercised), then drop `members.deletedAt`
      // (every other v9-affected column already exists at v8 -- see
      // `_dropMemberDeletedAtColumn`) and `settings.membership_revoked`
      // (see `_dropMembershipRevokedColumn`), and roll `user_version` back
      // to 8 -- reproducing exactly what a real v8 database on a user's
      // device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.households)
          .insert(
            HouseholdsCompanion.insert(
              id: 'h1',
              name: 'Household',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await seed
          .into(seed.members)
          .insert(
            MembersCompanion.insert(
              id: 'm1',
              householdId: 'h1',
              name: 'Me',
              color: 1,
              role: MemberRole.admin,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await _dropMemberDeletedAtColumn(seed);
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 8');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 8` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 8, 12)`
      // -- exactly the real upgrade path a v8 user's device would go
      // through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final member = await upgraded.select(upgraded.members).getSingle();
      expect(member.id, 'm1');
      // Pre-existing member data survived the upgrade untouched.
      expect(member.name, 'Me');
      expect(member.householdId, 'h1');
      expect(member.role, MemberRole.admin);
      expect(member.createdAt, 't0');
      // The new column defaults to NULL (active) -- no data rewrite.
      expect(member.deletedAt, isNull);
      // ... which, `deletedAt` being nullable, is an assertion that cannot
      // fail on its own (see `_columnNames`). This is the one that can.
      final memberColumns = await _columnNames(upgraded, 'members');
      expect(memberColumns, contains('deleted_at'));

      final settingsRow = await upgraded.select(upgraded.settings).get();
      expect(settingsRow, isEmpty);
      // No settings ROW here, but the two settings COLUMNS this upgrade
      // adds must exist all the same -- this test's seed dropped them, and
      // nothing above would notice if the upgrade skipped them.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(
        settingsColumns,
        containsAll(['membership_revoked', 'pending_join_code']),
      );
    },
  );

  test(
    'schemaVersion 9 -> 12 upgrade adds settings.membershipRevoked '
    '(false by default, no data rewrite), keeping the existing settings '
    'row -- this is the ONLY upgrade path any real (shipped, v9) install '
    'will actually execute',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v10_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v9 install -- the schema every shipped
      // build (0.4.1+7) is actually running: open the *current* (v12)
      // schema once so `onCreate` materializes every table with its full
      // v12 column set, insert a settings row with non-NULL
      // actingMemberId/syncHouseholdId (so the upgrade's "existing row
      // survives" guarantee is actually exercised), then drop only
      // `settings.membership_revoked` (every OTHER column already exists
      // at v9 -- see `_dropMembershipRevokedColumn`) and roll
      // `user_version` back to 9 -- reproducing exactly what a real v9
      // database on a user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
              syncHouseholdId: const Value('household-1'),
            ),
          );
      await _dropMembershipRevokedColumn(seed);
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 9');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 9` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 9, 12)`
      // -- exactly the real upgrade path every shipped user's device will
      // go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.membershipRevoked, isFalse);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.syncHouseholdId, 'household-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);

      // Exactly one `membership_revoked` column on `settings` -- guards
      // against the flat/unconditional `addColumn` placement this upgrade
      // must NOT use (see `AppDatabase.migration`'s doc comment on why it
      // lives inside the `else` branch): that placement would have this
      // test pass anyway (the column still ends up added once on a 9 -> 12
      // upgrade) while silently duplicate-adding it on a 1 -> 12 jump, so
      // this assertion alone would not catch that regression -- it exists
      // to pin the shape of THIS upgrade path specifically.
      final columns = await upgraded
          .customSelect("PRAGMA table_info('settings')")
          .get();
      final membershipRevokedColumns = columns.where(
        (row) => row.read<String>('name') == 'membership_revoked',
      );
      expect(membershipRevokedColumns, hasLength(1));
    },
  );

  test(
    'schemaVersion 10 -> 12 upgrade creates the (status, closed_on) index on '
    'chore_occurrences',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v11_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v10 install: open the *current* (v12)
      // schema once so `onCreate` materializes every table, then drop only
      // the index this migration adds (see
      // `_dropStatusClosedOnIndex` -- the same collateral-drop reasoning
      // the column helpers above use, one rung down the schema-object
      // hierarchy) and roll `user_version` back to 10.
      final seed = AppDatabase(NativeDatabase(file));
      await _dropStatusClosedOnIndex(seed);
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 10');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` sees `user_version == 10` vs. a declared 12, so
      // drift runs `onUpgrade(migrator, 10, 12)`.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final rows = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'chore_occurrences_status_closed_on_idx'",
          )
          .get();
      expect(rows, hasLength(1));

      // This seed also rewinds past v12, so the same upgrade owes it
      // `pending_join_code` -- and nothing else in this test would notice
      // if it never arrived.
      final settingsColumns = await _columnNames(upgraded, 'settings');
      expect(settingsColumns, contains('pending_join_code'));
    },
  );

  test(
    'schemaVersion 11 -> 12 upgrade adds settings.pendingJoinCode (NULL by '
    'default, no data rewrite), keeping the existing settings row -- this is '
    'the ONLY upgrade path any real (shipped, v11) install will actually '
    'execute',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_v12_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Simulate a pre-existing v11 install: open the *current* (v12)
      // schema once so `onCreate` materializes every table with its full
      // v12 column set, insert a settings row with non-NULL
      // actingMemberId/syncHouseholdId (so the upgrade's "existing row
      // survives" guarantee is actually exercised), then drop only
      // `settings.pending_join_code` (every OTHER column already exists at
      // v11 -- see `_dropPendingJoinCodeColumn`) and roll `user_version`
      // back to 11 -- reproducing exactly what a real v11 database on a
      // user's device looks like. Deliberately no `_dropStatusClosedOnIndex`
      // here, unlike every rewinding test above: at `from == 11` the
      // `from < 11` branch never runs, so the index `onCreate` already
      // built must STAY, or this test would stop reproducing a real v11
      // install.
      final seed = AppDatabase(NativeDatabase(file));
      await seed
          .into(seed.settings)
          .insert(
            SettingsCompanion.insert(
              id: 'device',
              createdAt: 't0',
              updatedAt: 't0',
              actingMemberId: const Value('member-1'),
              syncHouseholdId: const Value('household-1'),
            ),
          );
      await _dropPendingJoinCodeColumn(seed);
      await seed.customStatement('PRAGMA user_version = 11');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 12)
      // `AppDatabase` now sees `user_version == 11` on disk vs. a declared
      // `schemaVersion` of 12, so drift runs `onUpgrade(migrator, 11, 12)`
      // -- exactly the real upgrade path every shipped user's device will
      // go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      // The new column defaults to NULL (no join in progress).
      expect(row.pendingJoinCode, isNull);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.syncHouseholdId, 'household-1');
      expect(row.membershipRevoked, isFalse);
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);

      // Exactly one `pending_join_code` column on `settings`. This, NOT
      // the `isNull` assertion above, is what proves the migration ran:
      // drift maps an ABSENT nullable column to `null` on read, so
      // `expect(row.pendingJoinCode, isNull)` passes just as happily when
      // nothing added the column at all (verified by deleting the
      // migration branch: only this assertion went red). Any future
      // nullable-column migration test needs the same guard.
      //
      // What it does NOT catch is the flat/unconditional `addColumn`
      // placement -- that still adds the column exactly once on a 11 -> 12
      // upgrade, and duplicate-adds only on a 1 -> 12 jump, where the
      // `1 -> 2` test above is the one that fails.
      final columns = await upgraded
          .customSelect("PRAGMA table_info('settings')")
          .get();
      final pendingJoinCodeColumns = columns.where(
        (row) => row.read<String>('name') == 'pending_join_code',
      );
      expect(pendingJoinCodeColumns, hasLength(1));
    },
  );
}
