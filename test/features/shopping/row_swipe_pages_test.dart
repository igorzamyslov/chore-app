/// Widget coverage for the ONE thing removing the row `Dismissible` was
/// for (field report 2026-09-19, v0.10.1): a horizontal drag that starts on
/// a POPULATED shopping row must reach the shell's tab `PageView` and page
/// the app, instead of being swallowed by the row.
///
/// This file replaces `swipe_delete_test.dart` (backlog D-2, now reversed).
/// Its third case used to assert the exact opposite outcome — that a
/// right-drag over a row did NOT page back to Chores — which is precisely
/// the behaviour Igor hit on a real phone. Keeping the file and inverting
/// the assertion would have hidden that reversal in a diff; a new file with
/// this header records it.
///
/// A drag, not a fling: `tester.drag` releases with no velocity, so the
/// pager settles to whichever page the 500px offset (62.5% of the 800px
/// test surface, see `pump_app.dart`) leaves nearest — deterministic, with
/// no dependence on fling thresholds.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'dragging LEFT from a populated shopping row pages on to Settings '
    'instead of deleting the row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.categories'),
        findsOneWidget,
      );
      expect(find.text('Removed'), findsNothing);

      // Asserted against the database, not the tree: the shell's `PageView`
      // leaves neighbouring pages out of the semantics tree, so `'Milk'`
      // being absent from Settings proves nothing about whether the row was
      // deleted on the way past.
      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(row.deletedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'dragging RIGHT from a populated shopping row pages back to Chores',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a checked row in the expanded cart section does not swallow the drag '
    'either',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repository = ShoppingRepository(database);
      final item = await repository.addItem(householdId, name: 'Milk');
      await repository.setChecked(item.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await expandCartSection(tester, 'In the cart (1)');

      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${item.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.categories'),
        findsOneWidget,
      );
      expect(find.text('Removed'), findsNothing);

      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(row.deletedAt, isNull);

      handle.dispose();
    },
  );
}
