import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

Future<ShoppingItem> _row(AppDatabase database, String id) => (database.select(
  database.shoppingItems,
)..where((tbl) => tbl.id.equals(id))).getSingle();

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'Clear checked keeps its Undo snackbar up for 8 s (F4), not 4',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(milk.id, checked: true);

      await openShoppingTab(tester);
      await tester.tap(find.bySemanticsIdentifier('shopping.clear'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cleared 1 item'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Cleared 1 item'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Cleared 1 item'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'Put all back shows a counted snackbar for 8 s, and Undo re-checks '
    'exactly the items that tap returned (F4)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');
      final eggs = await repo.addItem(householdId, name: 'Eggs');
      final bread = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(milk.id, checked: true);
      await repo.setChecked(eggs.id, checked: true);

      await openShoppingTab(tester);
      await tester.tap(find.bySemanticsIdentifier('shopping.uncheckAll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Put 2 items back'), findsOneWidget);
      expect((await _row(database, milk.id)).checkedAt, isNull);
      expect((await _row(database, eggs.id)).checkedAt, isNull);

      // Still there well past the 4 s default.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Put 2 items back'), findsOneWidget);

      // Bread is ticked afterwards; Undo must not drag it along.
      await repo.setChecked(bread.id, checked: true);
      await repo.setChecked(bread.id, checked: false);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect((await _row(database, milk.id)).checkedAt, isNotNull);
      expect((await _row(database, eggs.id)).checkedAt, isNotNull);
      expect((await _row(database, bread.id)).checkedAt, isNull);
      expect(find.text('In the cart (2)'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'Put all back with a single item uses the singular copy',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      final milk = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(milk.id, checked: true);

      await openShoppingTab(tester);
      await tester.tap(find.bySemanticsIdentifier('shopping.uncheckAll'));
      await tester.pumpAndSettle();

      expect(find.text('Put 1 item back'), findsOneWidget);

      handle.dispose();
    },
  );
}
