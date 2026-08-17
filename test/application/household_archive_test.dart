import 'dart:convert';
import 'dart:io';

import 'package:chore_app/application/household_archive.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('famdo-archive-test-');
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            id: 'h1',
            name: 'My household',
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('archiveFileName', () {
    test('formats as famdo-archive-<yyyy-mm-dd>.json from the clock', () {
      final name = archiveFileName(Clock.fixed(DateTime(2026, 8, 1, 9)));
      expect(name, 'famdo-archive-2026-08-01.json');
    });

    test('uses the clock, never DateTime.now()', () {
      final name = archiveFileName(Clock.fixed(DateTime(2019, 1, 5)));
      expect(name, 'famdo-archive-2019-01-05.json');
    });
  });

  group('writeHouseholdArchive', () {
    test('writes the export document as JSON to a famdo-archive-<date>.json '
        'file inside the given directory, and returns that File', () async {
      final clock = Clock.fixed(DateTime.utc(2026, 8, 1, 12));

      final file = await writeHouseholdArchive(
        database: db,
        clock: clock,
        directory: tempDir,
      );

      expect(file.path, '${tempDir.path}/famdo-archive-2026-08-01.json');
      expect(file.existsSync(), isTrue);

      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['format'], 1);
      final tables = decoded['tables']! as Map<String, dynamic>;
      final households = tables['households']! as List<dynamic>;
      expect(
        households.any((row) => (row as Map<String, dynamic>)['id'] == 'h1'),
        isTrue,
      );
    });
  });
}
