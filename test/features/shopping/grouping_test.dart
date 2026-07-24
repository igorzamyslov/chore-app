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
    'grouping: 2 categories + uncategorized render 3 headers in sort order, '
    'names sorted within each',
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
      await items.addItem(
        householdId,
        name: 'Zucchini',
        categoryId: produce.id,
      );
      await items.addItem(householdId, name: 'Apples', categoryId: produce.id);
      await items.addItem(householdId, name: 'Milk', categoryId: dairy.id);
      await items.addItem(householdId, name: 'Bread');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      const expectedOrder = [
        'Uncategorized',
        'Bread',
        'Produce',
        'Apples',
        'Zucchini',
        'Dairy',
        'Milk',
      ];

      final renderedTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .where(expectedOrder.contains)
          .toList();

      expect(renderedTexts, expectedOrder);

      final headerIcons = tester
          .widgetList<Icon>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Icon),
            ),
          )
          .map((icon) => icon.icon)
          .toList();

      expect(headerIcons, [Icons.label_outlined, Icons.eco, Icons.egg]);
    },
  );
}
