import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// Widget coverage for the quick-add field's type-ahead suggestions (see
/// `docs/specs/ux-round-2.md` B2). Duplicate-prevention on submit/tap (B3)
/// has its own suite in `duplicate_prevention_test.dart`.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder quickAddInput() => find.descendant(
    of: find.bySemanticsIdentifier('shopping.add.input'),
    matching: find.byType(TextField),
  );

  testChoreApp(
    'suggestions: typing >=1 char shows ranked matches (frequency beats '
    'recency) with name + most recent category; clearing the field hides '
    'them',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final dairy = await CategoryRepository(database).createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Dairy',
        icon: 'egg',
        color: 0xFF8C7BC9,
      );

      var clockTime = DateTime.utc(2026, 7);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'seed-${nextId++}',
        nowUtc: () => clockTime,
      );

      // "milk" was added twice (frequency 2, with "Dairy" set on the older
      // row) — it must outrank "Mint", added once but more recently.
      await repo.addItem(householdId, name: 'Milk', categoryId: dairy.id);
      clockTime = clockTime.add(const Duration(minutes: 1));
      await repo.addItem(householdId, name: 'milk');
      clockTime = clockTime.add(const Duration(minutes: 1));
      await repo.addItem(householdId, name: 'Mint');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      await tester.enterText(quickAddInput(), 'mi');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('milk'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Dairy'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.1'),
          matching: find.text('Mint'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.2'),
        findsNothing,
      );

      // Clearing the field hides the suggestions again.
      await tester.enterText(quickAddInput(), '');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'suggestions include items cleared from the list (soft-deleted), and '
    'tapping one adds it immediately with its most recent category',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final dairy = await CategoryRepository(database).createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Dairy',
        icon: 'egg',
        color: 0xFF8C7BC9,
      );
      final repo = ShoppingRepository(database, newId: () => 'milk-1');
      final milk = await repo.addItem(
        householdId,
        name: 'Milk',
        categoryId: dairy.id,
      );
      await repo.setChecked(milk.id, checked: true);
      await repo.clearChecked(householdId);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);

      await tester.enterText(quickAddInput(), 'Mi');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Milk'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('shopping.suggestion.0'));
      await tester.pumpAndSettle();

      // Added immediately with the inherited category; suggestions gone,
      // input cleared, focus kept for the next entry.
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Dairy'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(quickAddInput()).controller?.text,
        isEmpty,
      );
      expect(tester.testTextInput.isVisible, isTrue);

      handle.dispose();
    },
  );
}
