import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'delete: cancel keeps it, confirm detaches referencing chores (they '
    'show as uncategorized)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = categories.firstWhere((c) => c.name == 'Cleaning');

      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await choreService.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate.fromDateTime(today),
        assignmentMode: AssignmentMode.anyone,
        categoryId: cleaning.id,
      );

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.text('Vacuum'), findsOneWidget);
      expect(find.text('Cleaning'), findsOneWidget);

      await openManageCategories(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();

      // Cancel: the category (and its sheet) is untouched.
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.cancel'),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();
      expect(find.text('Cleaning'), findsOneWidget);

      // Confirm: soft-deletes and detaches.
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.confirm'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsNothing,
      );
      expect(find.text('Cleaning'), findsNothing);

      final choreRow = await (database.select(
        database.chores,
      )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
      expect(choreRow.categoryId, isNull);

      // The manage-categories screen is a pushed route, covering the
      // bottom tab bar; back out of it before switching tabs again.
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.text('Vacuum'), findsOneWidget);
      expect(find.text('Cleaning'), findsNothing);

      handle.dispose();
    },
  );
}
