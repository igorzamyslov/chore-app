/// Widget coverage for the shopping row's long-press, after the 2026-09-19
/// field report reversed backlog D-2/D-3.
///
/// Long-press now opens the item's REAL menu — the edit sheet
/// (`shopping_edit_sheet.dart`): rename, quantity, category and Delete.
/// The one-row `{Delete}` sheet D-3 shipped is gone, along with its
/// `shopping.menu.delete` id: with the row's tap reassigned to ticking,
/// long-press is no longer free to spend on a single action, and every
/// action the old sheet offered is a strict subset of the edit sheet's.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'long-pressing an item opens the edit sheet — rename, quantity, '
    'category and Delete, not a one-row delete menu',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.name'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.edit.quantity'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('shopping.edit.category'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('shopping.edit.delete'),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsOneWidget);
      // The retired one-row menu must be gone, not merely unreachable.
      expect(find.bySemanticsIdentifier('shopping.menu.delete'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'Delete inside the long-press menu removes the item with the one shared '
    'undo snackbar',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a long-press does NOT also tick the item — the two gestures stay '
    'separate',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(row.checkedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing the long-press menu without a choice leaves the item alone',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      // Tap outside the sheet to dismiss it without choosing anything.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.name'), findsNothing);
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Removed'), findsNothing);

      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(row.checkedAt, isNull);
      expect(row.deletedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'long-pressing a checked item in the expanded cart section opens the '
    'same edit sheet',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repository = ShoppingRepository(database);
      final item = await repository.addItem(householdId, name: 'Milk');
      await repository.setChecked(item.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await expandCartSection(tester, 'In the cart (1)');

      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.name'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.edit.delete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
