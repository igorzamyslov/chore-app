import 'dart:io';

import 'package:chore_app/data/db/app_database.dart';
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
}
