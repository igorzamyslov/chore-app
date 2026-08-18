import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'empty states: fresh list; all items checked',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );

      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final item = await repo.addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.empty'), findsNothing);

      await repo.setChecked(item.id, checked: true);
      await tester.pumpAndSettle();

      // All items checked: the unchecked area shows the empty message again,
      // but the checked section stays visible.
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.text('In the cart (1)'), findsOneWidget);

      handle.dispose();
    },
  );
}
