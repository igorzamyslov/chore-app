import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'edit sheet: prefill, rename, quantity set+cleared round-trip, category '
    'move, empty-name error + recovery, delete',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categories = CategoryRepository(database);
      final produce = await categories.createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Produce',
        icon: 'nutrition',
        color: 0xFF6D9F71,
      );
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.edit.name'),
        matching: find.byType(TextField),
      );
      final quantityField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.edit.quantity'),
        matching: find.byType(TextField),
      );

      // Open, prefilled from the existing item.
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.edit.name'),
          matching: find.text('Milk'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.edit.quantity'),
          matching: find.text('Milk'),
        ),
        findsNothing,
      );

      // Rename, set a quantity, move to a category, save.
      await tester.enterText(nameField, 'Oat milk');
      await tester.enterText(quantityField, '2 bottles');
      await tester.tap(
        find.bySemanticsIdentifier('shopping.edit.category.${produce.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);
      expect(find.text('Oat milk'), findsOneWidget);
      expect(find.text('2 bottles'), findsOneWidget);
      // The aisle header renders the category name uppercased (spec
      // `docs/specs/theme-v2.md` §4.3).
      expect(find.text('PRODUCE'), findsOneWidget);

      // Re-open: quantity is prefilled; clear it back to null.
      await tester.tap(find.text('Oat milk'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.edit.quantity'),
          matching: find.text('2 bottles'),
        ),
        findsOneWidget,
      );
      await tester.enterText(quantityField, '');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.text('2 bottles'), findsNothing);
      expect(find.text('Oat milk'), findsOneWidget);

      // Empty-name error, then recovery.
      await tester.tap(find.text('Oat milk'));
      await tester.pumpAndSettle();
      await tester.enterText(nameField, '');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.text('Name is required'), findsOneWidget);
      // The sheet stayed open, and no data was lost or committed.
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsOneWidget);

      await tester.enterText(nameField, 'Oat milk again');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);
      expect(find.text('Oat milk again'), findsOneWidget);

      // Delete: immediate, no confirmation.
      await tester.tap(find.text('Oat milk again'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();

      expect(find.text('Oat milk again'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);

      handle.dispose();
    },
  );
}
