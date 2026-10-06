import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

Future<ShoppingItem> _row(AppDatabase database, String id) => (database.select(
  database.shoppingItems,
)..where((tbl) => tbl.id.equals(id))).getSingle();

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder field(String id) => find.descendant(
    of: find.bySemanticsIdentifier(id),
    matching: find.byType(TextField),
  );

  /// Dismisses the open bottom sheet by tapping the barrier above it.
  Future<void> dismissByBarrier(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'dismissing the edit sheet (tap outside) with a changed name and '
    'quantity saves them (F14)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final milk = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Milk');
      await tester.enterText(field('shopping.edit.name'), '  Oat milk ');
      await tester.enterText(field('shopping.edit.quantity'), '2 cartons');

      await dismissByBarrier(tester);

      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);
      final row = await _row(database, milk.id);
      expect(row.name, 'Oat milk');
      expect(row.quantityNote, '2 cartons');
      expect(row.syncDirty, isTrue);
      expect(find.text('Oat milk'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing the sheet by dragging it down saves too',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final milk = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Milk');
      await tester.enterText(field('shopping.edit.quantity'), '3');

      await tester.fling(
        find.bySemanticsIdentifier('shopping.edit.name'),
        const Offset(0, 600),
        2000,
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);
      expect((await _row(database, milk.id)).quantityNote, '3');

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing an untouched sheet writes nothing',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final milk = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await (database.update(database.shoppingItems)
            ..where((tbl) => tbl.id.equals(milk.id)))
          .write(const ShoppingItemsCompanion(syncDirty: Value(false)));
      final before = await _row(database, milk.id);

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Milk');
      await dismissByBarrier(tester);

      final after = await _row(database, milk.id);
      expect(after.updatedAt, before.updatedAt);
      expect(after.syncDirty, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing with an emptied name does not save (nothing is renamed to '
    'nothing)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final milk = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Milk');
      await tester.enterText(field('shopping.edit.name'), '   ');
      await tester.enterText(field('shopping.edit.quantity'), '5');
      await dismissByBarrier(tester);

      final row = await _row(database, milk.id);
      expect(row.name, 'Milk');
      expect(row.quantityNote, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismissing with a name that duplicates another item does not save',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Bread');
      final milk = await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Milk');
      await tester.enterText(field('shopping.edit.name'), 'bread');
      await dismissByBarrier(tester);

      expect((await _row(database, milk.id)).name, 'Milk');

      handle.dispose();
    },
  );

  testChoreApp(
    'Save and Delete still behave: Delete does not resurrect edits on the '
    'way out',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final milk = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await openItemMenu(tester, 'Milk');
      await tester.enterText(field('shopping.edit.name'), 'Changed');
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();

      final row = await _row(database, milk.id);
      expect(row.deletedAt, isNotNull);
      expect(row.name, 'Milk', reason: 'a delete discards pending edits');

      handle.dispose();
    },
  );
}
