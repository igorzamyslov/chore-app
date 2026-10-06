import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

Future<Category> _produce(AppDatabase database, String householdId) =>
    CategoryRepository(database).createCategory(
      householdId,
      kind: CategoryKind.shopping,
      name: 'Produce',
      icon: 'nutrition',
      color: 0xFF6D9F71,
    );

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'tapping a category header collapses its items, shows the count and a '
    'chevron, and is remembered in ui_state; tapping again expands (F9)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final produce = await _produce(database, householdId);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Apples', categoryId: produce.id);
      await repo.addItem(householdId, name: 'Pears', categoryId: produce.id);
      await repo.addItem(householdId, name: 'Batteries');

      await openShoppingTab(tester);

      final toggle = find.bySemanticsIdentifier(
        'shopping.category.${produce.id}.toggle',
      );
      expect(toggle, findsOneWidget);
      expect(find.text('Apples'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsWidgets);
      expect(find.text('(2)'), findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.text('Apples'), findsNothing);
      expect(find.text('Pears'), findsNothing);
      // Other aisles are untouched.
      expect(find.text('Batteries'), findsOneWidget);
      // Collapsed: the count shows and the chevron points sideways.
      expect(find.text('(2)'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(
        await ShoppingRepository(database).collapsedCategoryKeys(),
        {produce.id},
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('(2)'), findsNothing);
      expect(
        await ShoppingRepository(database).collapsedCategoryKeys(),
        isEmpty,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the uncategorized header collapses too',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Batteries');

      await openShoppingTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('shopping.category.uncategorized.toggle'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Batteries'), findsNothing);
      expect(find.text('(1)'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a collapsed category stays collapsed after a restart',
    today: today,
    seed: (database) async {
      final householdId = await currentHouseholdId(database);
      final produce = await _produce(database, householdId);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Apples', categoryId: produce.id);
      await repo.setCategoryCollapsed(produce.id, collapsed: true);
    },
    (tester, database) async {
      await openShoppingTab(tester);

      expect(find.text('Apples'), findsNothing);
      expect(find.text('(1)'), findsOneWidget);
    },
  );

  testChoreApp(
    'ticking an item in an expanded aisle still works after another aisle '
    'was collapsed',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final produce = await _produce(database, householdId);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Apples', categoryId: produce.id);
      final batteries = await repo.addItem(householdId, name: 'Batteries');

      await openShoppingTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('shopping.category.${produce.id}.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${batteries.id}.check'),
      );
      await settleTickBeat(tester);

      expect(find.text('In the cart (1)'), findsOneWidget);

      handle.dispose();
    },
  );
}
