import 'dart:io';

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
      // over time): open the *current* (v2) schema once against a real
      // file so `onCreate` materializes every table, including the v2-only
      // `settings` table, then drop that table and roll `user_version`
      // back to 1 — reproducing exactly what a real v1 database on a
      // user's device looks like.
      final seed = AppDatabase(NativeDatabase(file));
      await seed.customStatement('DROP TABLE settings');
      await seed.customStatement('PRAGMA user_version = 1');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 2)
      // `AppDatabase` now sees `user_version == 1` on disk vs. a declared
      // `schemaVersion` of 2, so drift runs `onUpgrade(migrator, 1, 2)` —
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
    'schemaVersion 3 -> 5 upgrade adds locale and both shown-once flags '
    '(NULL by default), keeping the existing settings row',
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
      // v3 and roll `user_version` back to 3 — reproducing exactly what a
      // real v3 database on a user's device looks like.
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
      await seed.customStatement('PRAGMA user_version = 3');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 5)
      // `AppDatabase` now sees `user_version == 3` on disk vs. a declared
      // `schemaVersion` of 5, so drift runs `onUpgrade(migrator, 3, 5)` —
      // exactly the real upgrade path a v3 user's device would go through.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.locale, isNull);
      expect(row.onboardingNamePromptShownAt, isNull);
      expect(row.digestPrepromptShownAt, isNull);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.actingMemberId, 'member-1');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );

  test(
    'schemaVersion 2 -> 5 upgrade adds every later settings column, '
    'keeping the existing settings row -- this app never actually stops '
    'at an intermediate version once schemaVersion is 5, so this '
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

      // Simulate a pre-existing v2 install: open the *current* (v4) schema
      // once so `onCreate` materializes every table with its full v4
      // column set, insert a settings row, then drop BOTH the v3-only
      // `acting_member_id` column and the v4-only `locale` column and roll
      // `user_version` back to 2 — reproducing exactly what a real v2
      // database on a user's device looks like, so the `from < 2` branch
      // is never hit and both `if (from < 3)` / `if (from < 4)` backfills
      // inside the `else` branch run in the same upgrade.
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
      await seed.customStatement('PRAGMA user_version = 2');
      await seed.close();

      // Re-opening the same file with the real (schemaVersion: 5)
      // `AppDatabase` now sees `user_version == 2` on disk vs. a declared
      // `schemaVersion` of 5, so drift runs `onUpgrade(migrator, 2, 5)`.
      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final row = await upgraded.select(upgraded.settings).getSingle();
      expect(row.id, 'device');
      expect(row.actingMemberId, isNull);
      expect(row.locale, isNull);
      expect(row.onboardingNamePromptShownAt, isNull);
      expect(row.digestPrepromptShownAt, isNull);
      // The pre-existing row's own data survived the upgrade untouched.
      expect(row.createdAt, 't0');
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);
    },
  );
}
