import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/settings_test_utils.dart';
import 'shopping_test_utils.dart';

/// Finds the [ChoiceChip] wrapped by the semantic id
/// `'shopping.edit.category.$id'`.
ChoiceChip _categoryChip(WidgetTester tester, String id) {
  return tester.widget<ChoiceChip>(
    find.descendant(
      of: find.bySemanticsIdentifier('shopping.edit.category.$id'),
      matching: find.byType(ChoiceChip),
    ),
  );
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'category picker: edit-categories button opens manage-categories on '
    'the shopping kind; a category added there shows up back in the '
    'picker',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();

      // The affordance sits alongside the edit sheet's chips.
      expect(
        find.bySemanticsIdentifier('category_picker.manage'),
        findsOneWidget,
      );

      // The affordance trails the (horizontally-scrollable) chip row, so
      // scroll it into view before tapping.
      await tester.ensureVisible(
        find.bySemanticsIdentifier('category_picker.manage'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('category_picker.manage'));
      await tester.pumpAndSettle();

      // Opens on the shopping section: shopping category names show,
      // chore's don't — proving the picker's own kind (not the
      // Settings-entry default of chore) is what got passed through.
      expect(find.text('Produce'), findsOneWidget);
      expect(find.text('Cleaning'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();
      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Snacks');
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();
      expect(find.text('Snacks'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back in the edit sheet: the new category shows up in the picker
      // and is selectable like any other.
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.shopping,
      );
      final snacks = categories.firstWhere((c) => c.name == 'Snacks');
      final snacksChip = find.bySemanticsIdentifier(
        'shopping.edit.category.${snacks.id}',
      );
      await tester.ensureVisible(snacksChip);
      await tester.pumpAndSettle();
      await tester.tap(snacksChip);
      await tester.pumpAndSettle();
      expect(_categoryChip(tester, snacks.id).selected, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'category picker falls back to None when the selected category is '
    'deleted while the manage-categories screen is open',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.shopping,
      );
      final produce = categories.firstWhere((c) => c.name == 'Produce');
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('shopping.edit.category.${produce.id}'),
      );
      await tester.pumpAndSettle();
      expect(_categoryChip(tester, produce.id).selected, isTrue);

      // Away to manage-categories: delete the category currently selected
      // in the (still-mounted, just covered) edit sheet behind it.
      // The affordance trails the (horizontally-scrollable) chip row, so
      // scroll it into view before tapping.
      await tester.ensureVisible(
        find.bySemanticsIdentifier('category_picker.manage'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('category_picker.manage'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${produce.id}'),
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

      await tester.pageBack();
      await tester.pumpAndSettle();

      // The deleted category's chip is gone; 'None' is selected instead of
      // being left pointing at a category that no longer shows anywhere.
      expect(
        find.bySemanticsIdentifier('shopping.edit.category.${produce.id}'),
        findsNothing,
      );
      expect(_categoryChip(tester, 'none').selected, isTrue);

      // Saving now persists with no category — the fallback isn't just
      // cosmetic.
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      final saved = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.name.equals('Milk'))).getSingle();
      expect(saved.categoryId, isNull);

      handle.dispose();
    },
  );
}
