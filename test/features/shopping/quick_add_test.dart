import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'quick add: type + submit adds a tile under Uncategorized, clears '
    'input, keeps focus',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      final inputField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.add.input'),
        matching: find.byType(TextField),
      );

      await tester.enterText(inputField, 'Milk');
      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      // The aisle header renders the category name uppercased (spec
      // `docs/specs/theme-v2.md` §4.3).
      expect(find.text('UNCATEGORIZED'), findsOneWidget);
      expect(tester.widget<TextField>(inputField).controller?.text, isEmpty);
      expect(tester.testTextInput.isVisible, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'quick add: a comma-separated list becomes one item per entry, with an '
    '"N items added" snackbar (F7)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      final inputField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.add.input'),
        matching: find.byType(TextField),
      );

      // The field is single-line on purpose (a hardware Enter must submit,
      // not insert a newline -- see shopping_quick_add_row.dart), so the
      // split users actually reach is the comma one.
      await tester.enterText(inputField, 'Oat milk, Sourdough, Eggs,, milk ');
      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();

      expect(find.text('Oat milk'), findsOneWidget);
      expect(find.text('Sourdough'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);
      expect(find.text('milk'), findsOneWidget);
      // "milk" is a distinct name from "Oat milk": 4 added.
      expect(find.text('4 items added'), findsOneWidget);
      expect(tester.widget<TextField>(inputField).controller?.text, isEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'quick add: duplicates inside a list are handled per item',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      final inputField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.add.input'),
        matching: find.byType(TextField),
      );

      await tester.enterText(inputField, 'Milk, Bread, MILK, Eggs');
      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('MILK'), findsNothing);
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);
      expect(find.text('3 items added'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'quick add: a list of one new item adds no count snackbar',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      final inputField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.add.input'),
        matching: find.byType(TextField),
      );

      await tester.enterText(inputField, 'Milk,');
      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.textContaining('items added'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'quick add: a typed count becomes the quantity note (F6)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      final inputField = find.descendant(
        of: find.bySemanticsIdentifier('shopping.add.input'),
        matching: find.byType(TextField),
      );

      await tester.enterText(inputField, '2x Milch, Eier x12, Brot');
      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();

      final rows = await database.select(database.shoppingItems).get();
      final byName = {for (final row in rows) row.name: row.quantityNote};
      expect(byName, {'Milch': '2', 'Eier': '12', 'Brot': null});

      // Duplicates are judged on the name alone: "3 milch" is Milch.
      await tester.enterText(inputField, '3 milch');
      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();
      expect(find.text('Already on the list'), findsOneWidget);
      expect(await database.select(database.shoppingItems).get(), hasLength(3));

      handle.dispose();
    },
  );

  testChoreApp(
    'quick add: empty submit adds nothing',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.text('UNCATEGORIZED'), findsNothing);

      handle.dispose();
    },
  );
}
