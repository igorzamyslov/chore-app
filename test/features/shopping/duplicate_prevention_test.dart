import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// Widget coverage for B3 duplicate prevention on quick-add submit (see
/// `docs/specs/ux-round-2.md` B3): all three branches, plus category
/// inheritance on a fresh insert. Suggestion-tap coverage lives in
/// `suggestions_test.dart`.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder quickAddInput() => find.descendant(
    of: find.bySemanticsIdentifier('shopping.add.input'),
    matching: find.byType(TextField),
  );

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(quickAddInput(), text);
    await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'an unchecked active match blocks the insert with an "Already on the '
    'list" snackbar; normalization matches case and whitespace variants',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);

      await submit(tester, '  MILK  ');

      expect(find.text('Already on the list'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(
        tester.widget<TextField>(quickAddInput()).controller?.text,
        isEmpty,
      );
      expect(tester.testTextInput.isVisible, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'a checked active match is restored (unchecked) instead of inserted, '
    'with a "Moved back to the list" snackbar',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'milk-1');
      final milk = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(milk.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      expect(find.text('In the cart (1)'), findsOneWidget);
      // Collapsed by default: the checked tile isn't rendered yet.
      expect(find.text('Milk'), findsNothing);

      await submit(tester, 'milk');

      expect(find.text('Moved back to the list'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.text('Milk'), findsOneWidget);
      expect(
        tester.widget<TextField>(quickAddInput()).controller?.text,
        isEmpty,
      );
      expect(tester.testTextInput.isVisible, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'no match inserts a new item, inheriting the most recent category from '
    'history for a plain-text submit',
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
      await repo.clearChecked(householdId); // no longer active

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);

      await submit(tester, 'Milk');

      expect(find.text('Already on the list'), findsNothing);
      expect(find.text('Moved back to the list'), findsNothing);
      expect(find.text('Milk'), findsOneWidget);
      // The aisle header renders the category name uppercased (spec
      // `docs/specs/theme-v2.md` §4.3).
      expect(find.text('DAIRY'), findsOneWidget);
      expect(
        tester.widget<TextField>(quickAddInput()).controller?.text,
        isEmpty,
      );
      expect(tester.testTextInput.isVisible, isTrue);

      handle.dispose();
    },
  );
}
