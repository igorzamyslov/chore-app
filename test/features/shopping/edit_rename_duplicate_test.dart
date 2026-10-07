import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

Future<ShoppingItem> _row(AppDatabase database, String id) => (database.select(
  database.shoppingItems,
)..where((tbl) => tbl.id.equals(id))).getSingle();

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder nameField() => find.descendant(
    of: find.bySemanticsIdentifier('shopping.edit.name'),
    matching: find.byType(TextField),
  );

  testChoreApp(
    "renaming an item to another active item's name shows an inline "
    '"Already on the list" error and does not save (F7)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Müsli');
      final bread = await repo.addItem(householdId, name: 'Bread');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Bread');

      // Case and diacritics are folded, like the quick-add check.
      await tester.enterText(nameField(), '  MUSLI ');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.text('Already on the list'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsOneWidget);
      expect((await _row(database, bread.id)).name, 'Bread');

      // A different name saves normally and clears the error.
      await tester.enterText(nameField(), 'Rye bread');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);
      expect((await _row(database, bread.id)).name, 'Rye bread');

      handle.dispose();
    },
  );

  testChoreApp(
    "changing only the casing of an item's own name is not a duplicate",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final milk = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'milk');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'milk');

      await tester.enterText(nameField(), 'Milk');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.save'));
      await tester.pumpAndSettle();

      expect(find.text('Already on the list'), findsNothing);
      expect((await _row(database, milk.id)).name, 'Milk');

      handle.dispose();
    },
  );
}
