import 'dart:convert';
import 'dart:io';

import 'package:chore_app/application/household_archive.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../features/settings/fake_path_provider_platform.dart';

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
    test(
      'formats as famdo-archive-<yyyy-MM-dd-HHmmss>.json from the clock',
      () {
        final name = archiveFileName(
          Clock.fixed(DateTime(2026, 8, 1, 9, 5, 7)),
        );
        expect(name, 'famdo-archive-2026-08-01-090507.json');
      },
    );

    test('uses the clock, never DateTime.now()', () {
      final name = archiveFileName(Clock.fixed(DateTime(2019, 1, 5)));
      expect(name, 'famdo-archive-2019-01-05-000000.json');
    });

    test('two archives on the same day get different names (B3)', () {
      final morning = archiveFileName(Clock.fixed(DateTime(2026, 8, 1, 9)));
      final evening = archiveFileName(Clock.fixed(DateTime(2026, 8, 1, 21)));
      expect(morning, isNot(evening));
    });
  });

  group('writeHouseholdArchive', () {
    test(
      'writes the export document as JSON to a famdo-archive-<stamp>.json '
      'file inside the given directory, and returns that File',
      () async {
        final clock = Clock.fixed(DateTime.utc(2026, 8, 1, 12));

        final file = await writeHouseholdArchive(
          database: db,
          clock: clock,
          directory: tempDir,
        );

        expect(
          file.path,
          '${tempDir.path}/famdo-archive-2026-08-01-120000.json',
        );
        expect(file.existsSync(), isTrue);

        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(decoded['format'], 1);
        final tables = decoded['tables']! as Map<String, dynamic>;
        final households = tables['households']! as List<dynamic>;
        expect(
          households.any(
            (row) => (row as Map<String, dynamic>)['id'] == 'h1',
          ),
          isTrue,
        );
      },
    );
  });

  group('listing and deleting saved copies', () {
    setUp(() {
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    });

    test('lists archive files newest first, ignoring other files', () async {
      File(
        '${tempDir.path}/famdo-archive-2026-08-01-090000.json',
      ).writeAsStringSync('{}');
      File(
        '${tempDir.path}/famdo-archive-2026-09-15-181530.json',
      ).writeAsStringSync('{}');
      File(
        '${tempDir.path}/famdo-archive-2026-07-24.json',
      ).writeAsStringSync('{}');
      File('${tempDir.path}/chore_app.sqlite').writeAsStringSync('x');

      final archives = await listHouseholdArchives();

      expect(archives.map((a) => a.fileName), [
        'famdo-archive-2026-09-15-181530.json',
        'famdo-archive-2026-08-01-090000.json',
        'famdo-archive-2026-07-24.json',
      ]);
      expect(archives.first.savedAt, DateTime(2026, 9, 15, 18, 15, 30));
      expect(archives.last.savedAt, DateTime(2026, 7, 24));
    });

    test('deleteHouseholdArchive removes just that file', () async {
      File(
        '${tempDir.path}/famdo-archive-2026-08-01-090000.json',
      ).writeAsStringSync('{}');
      File(
        '${tempDir.path}/famdo-archive-2026-09-15-181530.json',
      ).writeAsStringSync('{}');

      final archives = await listHouseholdArchives();
      await deleteHouseholdArchive(archives.first);

      expect(
        (await listHouseholdArchives()).map((a) => a.fileName),
        ['famdo-archive-2026-08-01-090000.json'],
      );
    });

    test('deleteAllHouseholdArchives leaves unrelated files alone', () async {
      File(
        '${tempDir.path}/famdo-archive-2026-08-01-090000.json',
      ).writeAsStringSync('{}');
      File('${tempDir.path}/chore_app.sqlite').writeAsStringSync('x');

      await deleteAllHouseholdArchives();

      expect(await listHouseholdArchives(), isEmpty);
      expect(File('${tempDir.path}/chore_app.sqlite').existsSync(), isTrue);
    });

    test('householdArchivePath joins the documents directory', () async {
      expect(
        await householdArchivePath('famdo-archive-x.json'),
        '${tempDir.path}/famdo-archive-x.json',
      );
    });
  });
}
