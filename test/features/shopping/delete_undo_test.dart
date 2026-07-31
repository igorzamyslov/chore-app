import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// Widget coverage for the shopping item delete undo (spec
/// `docs/specs/polish-round-1.md` C3): deleting from the edit sheet shows
/// an undo snackbar, and UNDO restores the soft-deleted row.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'deleting an item from its edit sheet removes it and shows an undo '
    'snackbar mirroring the chores undo tone',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'UNDO restores the item by clearing deleted_at (plain soft-delete '
    'restore)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Milk'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsNothing);

      final restored = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(restored.deletedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    "deleting a second item clears the first item's snackbar instead of "
    'queuing behind it — latest action wins (showAppSnackbar semantics)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await ShoppingRepository(database).addItem(householdId, name: 'Eggs');
      await tester.pumpAndSettle();

      await openShoppingTab(tester);
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.tap(find.text('Eggs'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shopping.edit.delete'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);

      handle.dispose();
    },
  );
}
