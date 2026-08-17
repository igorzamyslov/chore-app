/// Widget coverage for swipe-to-delete on a shopping item row (backlog
/// D-2 / conventions audit C2): a single-direction (`endToStart`, i.e.
/// swipe-left) `Dismissible` that reuses the exact delete-with-undo path
/// the edit sheet's Delete button already ships (spec
/// `docs/specs/polish-round-1.md` C3) — see `shopping_delete.dart`.
///
/// The 'swiping right does nothing' case below cannot be proved by a
/// red-before-green run alone (with no `Dismissible` at all, a right drag is
/// trivially a no-op). It was proved instead by inverting the shipped
/// `direction:` to `startToEnd` and observing this file go red on CI — see
/// the report for that branch head.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'swiping an unchecked item left removes it and shows the same undo '
    'snackbar as the edit sheet delete',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'UNDO after a swipe restores the item by clearing deleted_at',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);

      final restored = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(restored.deletedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping right (startToEnd) does nothing — delete is left-swipe only',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Removed'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping a checked item in the expanded cart section deletes it the '
    'same way as an unchecked item',
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
      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.text('Removed'), findsOneWidget);

      handle.dispose();
    },
  );
}
