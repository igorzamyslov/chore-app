import 'package:chore_app/application/household_archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../../test_utils/pump_app.dart';
import 'fake_archive_file_writer.dart';
import 'fake_share_platform.dart';
import 'settings_test_utils.dart';

/// Persona review B3: the saved copies of earlier households are reachable
/// from Settings -> Data (hidden when there are none), listed newest first
/// with Share and Delete (confirmed), and a full reset removes them.
void main() {
  final today = DateTime(2026, 7, 24, 9);
  const older = '/fake-docs/famdo-archive-2026-08-01-090000.json';
  const newer = '/fake-docs/famdo-archive-2026-09-15-181530.json';

  // One fake, installed once -- see FakeSharePlatform's doc comment.
  final fakeShare = FakeSharePlatform();
  SharePlatform.instance = fakeShare;

  late FakeArchiveFileWriter writer;
  final realWriter = ArchiveFileWriter.instance;

  setUp(() {
    fakeShare.reset();
    writer = FakeArchiveFileWriter();
    ArchiveFileWriter.instance = writer;
  });

  tearDown(() => ArchiveFileWriter.instance = realWriter);

  Finder row() => find.bySemanticsIdentifier('settings.archives');

  testChoreApp(
    'the saved-copies row is hidden when there are no copies',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(find.bySemanticsIdentifier('settings.export'), findsOneWidget);
      expect(row(), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'with copies the row shows the count and opens the list, newest first',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      writer.writtenFiles
        ..[older] = '{}'
        ..[newer] = '{}';
      await openSettingsTab(tester);

      expect(
        find.text('Saved copies of earlier households (2)'),
        findsOneWidget,
      );
      await tester.tap(row());
      await tester.pumpAndSettle();

      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.subtitle! as Text).data)
          .toList();
      expect(titles, [
        'famdo-archive-2026-09-15-181530.json',
        'famdo-archive-2026-08-01-090000.json',
      ]);
      expect(find.textContaining('Saved on'), findsNWidgets(2));

      handle.dispose();
    },
  );

  testChoreApp(
    'Share hands that file to the share sheet',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      writer.writtenFiles[newer] = '{}';
      await openSettingsTab(tester);
      await tester.tap(row());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.archives.share'));
      await tester.pumpAndSettle();

      expect(fakeShare.lastParams!.files!.single.path, newer);
      expect(fakeShare.lastParams!.fileNameOverrides, [
        'famdo-archive-2026-09-15-181530.json',
      ]);

      handle.dispose();
    },
  );

  testChoreApp(
    'Delete asks first: cancel keeps the file, confirm removes it and the '
    'screen closes with the last copy',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      writer.writtenFiles[newer] = '{}';
      await openSettingsTab(tester);
      await tester.tap(row());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.archives.delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this saved copy?'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('settings.archives.delete.cancel'),
      );
      await tester.pumpAndSettle();
      expect(writer.writtenFiles.keys, [newer]);

      await tester.tap(find.bySemanticsIdentifier('settings.archives.delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.archives.delete.confirm'),
      );
      await tester.pumpAndSettle();

      expect(writer.writtenFiles, isEmpty);
      // Back on Settings, and the row is gone with the last copy.
      expect(find.bySemanticsIdentifier('settings.export'), findsOneWidget);
      expect(row(), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a full reset deletes every saved copy',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      writer.writtenFiles
        ..[older] = '{}'
        ..[newer] = '{}';
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();

      expect(writer.writtenFiles, isEmpty);

      handle.dispose();
    },
  );
}
