import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/ui_state_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

/// Last-tab restore (spec `docs/specs/last-tab-restore.md`): the shell
/// reopens on the tab the user was last on, and records every tab change.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  Future<void> seedLastTab(AppDatabase database, String tab) async {
    await database
        .into(database.uiState)
        .insert(UiStateCompanion.insert(id: 'device', lastTab: Value(tab)));
  }

  Future<String?> storedLastTab(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    // Boxed in a list: `runAsync` returns `T?`, which would otherwise be
    // indistinguishable from a stored `null`.
    final boxed = await tester.runAsync(
      () async => [(await UiStateRepository(database).readUiState())?.lastTab],
    );
    return boxed!.single;
  }

  testChoreApp(
    'a stored shopping tab is what the first frame after bootstrap shows',
    today: today,
    seed: (database) => seedLastTab(database, 'shopping'),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('shopping.add.input'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.add'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'an unrecognized stored value opens on Chores rather than throwing',
    today: today,
    seed: (database) => seedLastTab(database, 'bogus'),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'switching tabs persists the new tab name',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      expect(await storedLastTab(tester, database), 'shopping');

      handle.dispose();
    },
  );

  testChoreApp(
    're-tapping the already-active tab writes nothing',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();

      expect(await storedLastTab(tester, database), isNull);

      handle.dispose();
    },
  );
}
