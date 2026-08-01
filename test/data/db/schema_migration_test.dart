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
      // over time): open the *current* (v8) schema once against a real
      // file so `onCreate` materializes every table, including the v2-only
      // `settings` table, then drop that table (plus `syncDirty` from
      // every OTHER table -- see `_dropSyncDirtyColumns`, added at v8) and
      // roll `user_version` back to 1 — reproducing exactly what a real v1
      // database on a user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed.customStatement('DROP TABLE settings');
      await _dropSyncDirtyColumns(seed);
      await seed.customStatement('PRAGMA user_version = 1');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 8)
      // `AppDatabase` now sees `user_version == 1` on disk vs. a declared
      // `schemaVersion` of 8, so drift runs `onUpgrade(migrator, 1, 8)` —
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

      // Pre-existing v1 data survived the upgrade untouched.
      final households = await upgraded.select(upgraded.households).get();
      expect(households, isEmpty);
    },
  );

  test('a fresh (never-opened) database is created at schemaVersion 2 '
      'directly, settings table included', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // No upgrade path is exercised here (`onCreate`'s default
    // `Migrator.createAll()` already creates every v2 table, `settings`
    // included) — this just guards against a regression where a fresh
    // install would need `onUpgrade` to get the settings table.
    final rows = await db.select(db.settings).get();
    expect(rows, isEmpty);
  });

  test(
    'schemaVersion 3 -> 8 upgrade adds locale, both shown-once flags, the '
    'sync-linked columns, themeMode, and syncLastPulledAt (NULL by '
    'default), keeping the existing settings row',
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
      await seed.customStatement('PRAGMA user_version = 3');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 8)
      // `AppDatabase` now sees `user_version == 3` on disk vs. a declared
      // `schemaVersion` of 8, so drift runs `onUpgrade(migrator, 3, 8)` —
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
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 2 -> 8 upgrade adds every later settings column, '
    'keeping the existing settings row -- this app never actually stops '
    'at an intermediate version once schemaVersion is 8, so this '
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

      // Simulate a pre-existing v2 install: open the *current* (v8) schema
      // once so `onCreate` materializes every table with its full v8
      // column set, insert a settings row, then drop every column newer
      // than v2 (plus `syncDirty` from every other table -- see
      // `_dropSyncDirtyColumns`, added at v8) and roll `user_version` back
      // to 2 — reproducing exactly what a real v2 database on a user's
      // device looks like, so the `from < 2` branch is never hit and every
      // `if (from < N)` backfill inside the `else` branch runs in the same
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
      await seed.customStatement('PRAGMA user_version = 2');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 8)
      // `AppDatabase` now sees `user_version == 2` on disk vs. a declared
      // `schemaVersion` of 8, so drift runs `onUpgrade(migrator, 2, 8)`.
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
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 5 -> 8 upgrade adds syncHouseholdId, syncLinkedAt, '
    'themeMode, and syncLastPulledAt (NULL by default, no data rewrite), '
    'keeping the existing settings row',
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

      // Simulate a pre-existing v5 install: open the *current* (v8) schema
      // once so `onCreate` materializes every table with its full v8 column
      // set, insert a settings row with a non-NULL actingMemberId (so the
      // upgrade's "existing row survives" guarantee is actually exercised),
      // then drop every column newer than v5 (plus `syncDirty` from every
      // other table -- see `_dropSyncDirtyColumns`, added at v8) and roll
      // `user_version` back to 5 -- reproducing exactly what a real v5
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
      await seed.customStatement('PRAGMA user_version = 5');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 8)
      // `AppDatabase` now sees `user_version == 5` on disk vs. a declared
      // `schemaVersion` of 8, so drift runs `onUpgrade(migrator, 5, 8)` --
      // exactly the real upgrade path a v5 user's device would go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.syncHouseholdId, isNull);
      expect(row.syncLinkedAt, isNull);
      expect(row.themeMode, isNull);
      expect(row.syncLastPulledAt, isNull);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 6 -> 8 upgrade adds themeMode and syncLastPulledAt '
    '(NULL by default, no data rewrite), keeping the existing settings row',
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

      // Simulate a pre-existing v6 install: open the *current* (v8) schema
      // once so `onCreate` materializes every table with its full v8 column
      // set, insert a settings row with a non-NULL actingMemberId and a
      // non-NULL syncHouseholdId (so the upgrade's "existing row survives"
      // guarantee is actually exercised for both pre-existing columns),
      // then drop the v7/v8-only columns (plus `syncDirty` from every other
      // table -- see `_dropSyncDirtyColumns`, added at v8) and roll
      // `user_version` back to 6 -- reproducing exactly what a real v6
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
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN theme_mode',
      );
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await _dropSyncDirtyColumns(seed);
      await seed.customStatement('PRAGMA user_version = 6');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 8)
      // `AppDatabase` now sees `user_version == 6` on disk vs. a declared
      // `schemaVersion` of 8, so drift runs `onUpgrade(migrator, 6, 8)` --
      // exactly the real upgrade path a v6 user's device would go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.themeMode, isNull);
      expect(row.syncLastPulledAt, isNull);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.syncHouseholdId, 'household-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 7 -> 8 upgrade adds syncDirty (default false) to every '
    'synced table and syncLastPulledAt (NULL) to settings, keeping '
    'existing rows',
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

      // Simulate a pre-existing v7 install: open the *current* (v8) schema
      // once so `onCreate` materializes every table with its full v8
      // column set, insert one row into every synced table (so the
      // upgrade's "existing rows survive, syncDirty defaults to false"
      // guarantee is actually exercised everywhere, not just on
      // `settings`), then drop `syncDirty` from all 7 of those tables and
      // `syncLastPulledAt` from `settings`, and roll `user_version` back
      // to 7 -- reproducing exactly what a real v7 database on a user's
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
      await seed.customStatement(
        'ALTER TABLE settings DROP COLUMN sync_last_pulled_at',
      );
      await seed.customStatement('PRAGMA user_version = 7');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 8)
      // `AppDatabase` now sees `user_version == 7` on disk vs. a declared
      // `schemaVersion` of 8, so drift runs `onUpgrade(migrator, 7, 8)` --
      // exactly the real upgrade path a v7 user's device would go through.
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
      // Pre-existing settings data survived the upgrade untouched.
      expect(settingsRow.createdAt, 't0');
      expect(settingsRow.digestEnabled, isTrue);
    },
  );
}
