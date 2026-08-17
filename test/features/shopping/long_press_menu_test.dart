/// Widget coverage for the shopping item long-press action sheet (backlog
/// D-3 / conventions audit C5) -- a one-row `{Delete}` menu, the
/// tap-reachable equivalent of swipe-to-delete (D-2) for anyone who can't
/// perform a calibrated horizontal drag. See "OD-2" in
/// `docs/plans/2026-08-08-shopping-gestures.md` for why the menu has
/// exactly one row.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'long-pressing an item opens a menu with a Delete row; tapping it '
    'deletes with the same undo snackbar as the edit sheet',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.menu.delete'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('shopping.menu.delete'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'the long-press menu never opens the edit sheet — it is a delete menu, '
    'not a duplicate of the tap target',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.name'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing the menu without picking an action leaves the item alone',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      // Tap outside the sheet to dismiss it without choosing a row.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.menu.delete'),
        findsNothing,
      );
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Removed'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'long-pressing a checked item in the expanded cart section also opens '
    'the delete menu',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repository = ShoppingRepository(database);
      final item = await repository.addItem(householdId, name: 'Milk');
      await repository.setChecked(item.id, checked: true);
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await expandCartSection(tester, 'In the cart (1)');
      await tester.longPress(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.menu.delete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
