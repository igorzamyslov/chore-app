import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'clear checked: button hidden at N=0; tapping it clears checked items '
    'immediately, with no confirmation dialog (spec ux-round-2.md B4)',
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

      // Tapping clears immediately: no confirm/cancel step of any kind.
      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.clear.confirm'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.bySemanticsIdentifier('shopping.clear'), findsNothing);
      expect(find.text('Bread'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'clear checked (T1.4) shows an undo snackbar naming how many were '
    'cleared, and UNDO restores exactly those items',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');
      final eggs = await repo.addItem(householdId, name: 'Eggs');
      await repo.addItem(householdId, name: 'Bread');

      await openShoppingTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${milk.id}.check'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${eggs.id}.check'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pumpAndSettle();

      expect(find.text('Cleared 2 items'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Milk'), findsNothing);
      expect(find.text('Eggs'), findsNothing);
      // Never checked, never cleared -- untouched throughout.
      expect(find.text('Bread'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Restored still checked (a plain deleted_at clear, per
      // ShoppingRepository.restoreItems), so both are back under 'In the
      // cart' -- collapsed by default on this fresh reappearance (spec G1,
      // matching cart_section_test.dart), so expand it to reach the tiles.
      expect(find.text('In the cart (2)'), findsOneWidget);
      await tester.tap(find.text('In the cart (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);

      final restoredMilk = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(milk.id))).getSingle();
      expect(restoredMilk.deletedAt, isNull);
      expect(restoredMilk.checkedAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'UNDO after a second Clear restores only the items THAT clear cleared '
    "-- not an earlier, already-forgotten Clear's items too",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final first = await repo.addItem(householdId, name: 'Flour');

      await openShoppingTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${first.id}.check'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pumpAndSettle();
      // 'Flour' is cleared and its undo snackbar is showing, but nobody
      // taps Undo -- exactly the "everything ever cleared" trap a naive
      // "restore every checked+deleted row" implementation would fall
      // into once a second Clear happens.

      final second = await repo.addItem(householdId, name: 'Sugar');
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${second.id}.check'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pumpAndSettle();

      expect(find.text('Cleared 1 item'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Only 'Sugar' (this Clear's item) comes back -- the count alone
      // already proves 'Flour' didn't tag along, since a wrongly-restored
      // 'Flour' would make this 2.
      expect(find.text('In the cart (1)'), findsOneWidget);
      await tester.tap(find.text('In the cart (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Sugar'), findsOneWidget);
      expect(find.text('Flour'), findsNothing);

      final flourRow = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(first.id))).getSingle();
      expect(flourRow.deletedAt, isNotNull);

      handle.dispose();
    },
  );
}
