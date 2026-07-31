import 'dart:convert';

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../../test_utils/pump_app.dart';
import 'fake_share_platform.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's 'Export data' row (spec
/// `docs/specs/polish-round-1.md` B1). The JSON *shape* of the export is
/// already thoroughly covered by `test/application/data_export_test.dart`
/// (which exercises the pure `buildExportDocument` directly); these tests
/// only cover the wiring: tapping the row shares the right bytes under the
/// right file name, and a failure shows the generic error snackbar. The
/// share sheet itself is stubbed via [FakeSharePlatform] (spec: "share
/// sheet itself may be stubbed at the share_plus boundary").
void main() {
  final today = DateTime(2026, 7, 24, 9);
  // A single fake, installed once (see FakeSharePlatform's doc comment for
  // why re-creating it per test wouldn't actually swap out the instance
  // `export_row.dart` shares through). Its recorded state is cleared
  // between tests instead.
  final fakeShare = FakeSharePlatform();
  SharePlatform.instance = fakeShare;

  setUp(fakeShare.reset);

  testChoreApp(
    'tapping the row shares the seeded data under a '
    'famdo-export-<date>.json name',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      await choreService.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate.fromDateTime(today),
        assignmentMode: AssignmentMode.anyone,
      );

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.export'));
      await tester.pumpAndSettle();

      final params = fakeShare.lastParams;
      expect(params, isNotNull);
      // The name is carried via fileNameOverrides, not XFile.name: the
      // shared file is built in-memory via XFile.fromData, whose own
      // `name` argument is ignored on every platform except web.
      expect(params!.fileNameOverrides, ['famdo-export-2026-07-24.json']);
      final file = params.files!.single;
      expect(file.mimeType, 'application/json');

      final bytes = await file.readAsBytes();
      final document = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(document['format'], 1);
      final tables = document['tables']! as Map<String, dynamic>;
      final chores = tables['chores']! as List<dynamic>;
      expect(
        chores.any(
          (row) => (row as Map<String, dynamic>)['title'] == 'Vacuum',
        ),
        isTrue,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a failure while exporting shows the generic error snackbar',
    today: today,
    (tester, database) async {
      fakeShare.errorToThrow = Exception('share sheet unavailable');
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.export'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't export your data. Please try again."),
        findsOneWidget,
      );
      expect(fakeShare.lastParams, isNull);

      handle.dispose();
    },
  );
}
