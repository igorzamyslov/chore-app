import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'clear checked: button hidden at N=0; confirm removes checked items '
    'only; cancel keeps them',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');
      await repo.addItem(householdId, name: 'Bread');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.clear'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${milk.id}.check'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.clear'), findsOneWidget);

      // Cancel: the checked item stays.
      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('shopping.clear.confirm'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('shopping.clear.cancel'));
      await tester.pumpAndSettle();
      expect(find.text('In the cart (1)'), findsOneWidget);

      // Confirm: the checked item is removed; the unchecked item stays.
      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.clear.confirm'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.bySemanticsIdentifier('shopping.clear'), findsNothing);
      expect(find.text('Bread'), findsOneWidget);

      handle.dispose();
    },
  );
}
