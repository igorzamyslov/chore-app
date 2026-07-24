import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'check moves the item to the checked section (header count updates); '
    'uncheck moves it back under its category header',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'item-1');
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
      await tester.pumpAndSettle();

      // Checking moved it to the checked section, without opening the edit
      // sheet (the checkbox tap must not fall through to the tile's onTap).
      expect(find.text('In the cart (1)'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);
      expect(find.text('Uncategorized'), findsNothing);
      // Everything unchecked is gone, so the empty message shows above the
      // (still-visible) checked section.
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);

      // Expand the collapsed-by-default section to reach the checked tile.
      await tester.tap(find.text('In the cart (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsNothing);

      handle.dispose();
    },
  );
}
