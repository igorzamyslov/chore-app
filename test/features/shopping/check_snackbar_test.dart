import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

Future<bool> _isChecked(AppDatabase database, String id) async {
  final row = await (database.select(
    database.shoppingItems,
  )..where((tbl) => tbl.id.equals(id))).getSingle();
  return row.checkedAt != null;
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'ticking an item shows an "In the cart" snackbar with Undo (F3); Undo '
    'unchecks the item',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      expect(find.text('In the cart'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${milk.id}.check'),
      );
      await settleTickBeat(tester);

      expect(find.text('In the cart'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(await _isChecked(database, milk.id), isTrue);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(await _isChecked(database, milk.id), isFalse);
      expect(find.text('Milk'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'unticking from the cart shows no "In the cart" snackbar',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(milk.id, checked: true);

      await openShoppingTab(tester);
      await expandCartSection(tester, 'In the cart (1)');
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${milk.id}.check'),
      );
      await settleTickBeat(tester);

      expect(find.text('In the cart'), findsNothing);
      expect(await _isChecked(database, milk.id), isFalse);

      handle.dispose();
    },
  );
}
