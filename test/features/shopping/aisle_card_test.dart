import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// Widget coverage for theme v2's shopping restyle (spec
/// `docs/specs/theme-v2.md` §4.3): one card per category run (not one card
/// per item) with hairline-separated rows and no hairline after the last
/// row, and the checked-row treatment (filled ring + strikethrough).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'aisles: one card per category run, hairline-separated rows, no '
    'hairline after the last row in a card',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final categories = CategoryRepository(database);
      final produce = await categories.createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Produce',
        icon: 'nutrition',
        color: 0xFF6D9F71,
      );
      final dairy = await categories.createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Dairy',
        icon: 'egg',
        color: 0xFF8C7BC9,
        sortOrder: 1,
      );

      final items = ShoppingRepository(database);
      // Uncategorized: 1 item (0 hairlines within its card).
      await items.addItem(householdId, name: 'Bread');
      // Produce: 2 items (1 hairline within its card).
      await items.addItem(householdId, name: 'Apples', categoryId: produce.id);
      await items.addItem(
        householdId,
        name: 'Zucchini',
        categoryId: produce.id,
      );
      // Dairy: 1 item (0 hairlines within its card).
      await items.addItem(householdId, name: 'Milk', categoryId: dairy.id);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      // Exactly one card per category run (3 groups: Uncategorized, Produce,
      // Dairy) -- never one card per item (which would be 4 cards for 4
      // items).
      final cardsInList = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Card),
      );
      expect(cardsInList, findsNWidgets(3));

      // Hairlines only ever separate rows WITHIN a card: total dividers
      // inside cards = sum(groupSize - 1) = 0 + 1 + 0 = 1 -- proving no
      // hairline follows the last row of any group's card. (The category
      // headers' own rule-line dividers live outside any Card, so they
      // don't pollute this count.)
      final dividersInsideCards = find.descendant(
        of: find.byType(Card),
        matching: find.byType(Divider),
      );
      expect(dividersInsideCards, findsNWidgets(1));
    },
  );

  testChoreApp(
    'checked-row treatment: a checked item shows a filled ring with a '
    'check glyph and strikethrough, muted text; an unchecked item shows '
    'neither',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final milk = await repo.addItem(householdId, name: 'Milk');
      await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(milk.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      // Expand the cart to reach the checked row.
      await tester.tap(find.text('In the cart (1)'));
      await tester.pumpAndSettle();

      final milkText = tester.widget<Text>(find.text('Milk'));
      expect(milkText.style?.decoration, TextDecoration.lineThrough);
      expect(
        milkText.style?.color,
        Theme.of(
          tester.element(find.text('Milk')),
        ).colorScheme.onSurfaceVariant,
      );

      final breadText = tester.widget<Text>(find.text('Bread'));
      expect(breadText.style?.decoration, isNot(TextDecoration.lineThrough));

      // Exactly one filled check glyph (the checked ring's Icons.check) is
      // rendered -- for Milk only, never for the still-unchecked Bread.
      expect(find.byIcon(Icons.check), findsOneWidget);

      handle.dispose();
    },
  );
}
