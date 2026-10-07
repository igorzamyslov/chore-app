import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder quickAddInput() => find.descendant(
    of: find.bySemanticsIdentifier('shopping.add.input'),
    matching: find.byType(TextField),
  );

  Finder chip(String text) => find.descendant(
    of: find.byType(ActionChip),
    matching: find.text(text),
  );

  testChoreApp(
    'long-pressing a suggestion chip offers "Forget this suggestion"; '
    'choosing it hides the chip for good without adding the item (F11)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      for (final name in ['Mlik', 'Bread']) {
        final item = await repo.addItem(householdId, name: name);
        await repo.setChecked(item.id, checked: true);
      }
      await repo.clearChecked(householdId);

      await openShoppingTab(tester);
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(chip('Mlik'), findsOneWidget);
      expect(chip('Bread'), findsOneWidget);

      await tester.longPress(chip('Mlik'));
      await tester.pumpAndSettle();
      expect(find.text('Forget this suggestion'), findsOneWidget);

      await tester.tap(find.text('Forget this suggestion'));
      await tester.pumpAndSettle();

      expect(chip('Mlik'), findsNothing);
      expect(chip('Bread'), findsOneWidget);
      // Forgetting must not add the item to the list.
      expect(
        await repo.findActiveByNormalizedName(householdId, 'mlik'),
        isNull,
      );
      expect(await repo.forgottenSuggestionNames(), {'mlik'});

      // Gone from type-ahead as well.
      await tester.enterText(quickAddInput(), 'Ml');
      await tester.pumpAndSettle();
      expect(chip('Mlik'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a plain tap on a chip still adds the item (long-press did not break it)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final item = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(item.id, checked: true);
      await repo.clearChecked(householdId);

      await openShoppingTab(tester);
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      await tester.tap(chip('Bread'));
      await tester.pumpAndSettle();

      expect(find.text('Bread'), findsOneWidget);
      expect(
        await repo.findActiveByNormalizedName(householdId, 'bread'),
        isNotNull,
      );

      handle.dispose();
    },
  );
}
