import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'both themes render the shopping screen without exceptions', // smoke test
    today: today,
    (tester, database) async {
      await openShoppingTab(tester);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Shopping'),
        ),
        findsOneWidget,
      );
    },
  );

  testChoreApp(
    'text scale 2.0 renders the list and edit sheet without overflow '
    'exceptions',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      await repo.addItem(
        householdId,
        name: 'A shopping item with a reasonably long descriptive name',
        quantityNote: 'Also a fairly long quantity note here',
      );

      await openShoppingTab(tester);

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('A shopping item with a reasonably long descriptive name'),
        findsOneWidget,
      );

      final handle = tester.ensureSemantics();
      await tester.tap(
        find.text('A shopping item with a reasonably long descriptive name'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsOneWidget);

      handle.dispose();
    },
  );
}
