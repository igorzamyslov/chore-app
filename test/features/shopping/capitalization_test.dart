import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/shopping/shopping_quick_add_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the quick-add and edit-sheet name fields capitalise sentences (F12)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      final quickAdd = tester.widget<TextField>(
        find.descendant(
          of: find.byType(ShoppingQuickAddRow),
          matching: find.byType(TextField),
        ),
      );
      expect(quickAdd.textCapitalization, TextCapitalization.sentences);

      await openItemMenu(tester, 'Milk');
      final editName = tester.widget<TextField>(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.edit.name'),
          matching: find.byType(TextField),
        ),
      );
      expect(editName.textCapitalization, TextCapitalization.sentences);

      handle.dispose();
    },
  );
}
