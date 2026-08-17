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

  testChoreApp('quick add: empty submit adds nothing', today: today, (
    tester,
    database,
  ) async {
    final handle = tester.ensureSemantics();
    await openShoppingTab(tester);

    await tester.tap(find.bySemanticsIdentifier('shopping.add.submit'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
    expect(find.text('UNCATEGORIZED'), findsNothing);

    handle.dispose();
  });
}
