import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    "row text is sized for arm's length: name titleMedium, quantity "
    'bodyMedium (F8)',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk', quantityNote: '2 cartons');

      await openShoppingTab(tester);

      final textTheme = Theme.of(
        tester.element(find.text('Milk')),
      ).textTheme;
      final name = tester.widget<Text>(find.text('Milk'));
      final quantity = tester.widget<Text>(find.text('2 cartons'));

      expect(name.style?.fontSize, textTheme.titleMedium?.fontSize);
      expect(name.style?.fontWeight, textTheme.titleMedium?.fontWeight);
      expect(quantity.style?.fontSize, textTheme.bodyMedium?.fontSize);
      expect(textTheme.titleMedium?.fontSize, 15.5);
      expect(textTheme.bodyMedium?.fontSize, 14);
    },
  );
}
