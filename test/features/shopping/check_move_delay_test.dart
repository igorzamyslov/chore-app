/// Widget coverage for the tick beat (field report 2026-09-19, Igor's last
/// paragraph): *"it would be nice if the ticking action would be seen for a
/// brief moment, before the item is moved (right now I click on it and it
/// feels that it just disappears)"*.
///
/// The mechanism under test is deliberately NOT a delayed write. The write
/// lands immediately, exactly as before; only the row's MOVE between the
/// aisle list and the cart section is held back for
/// [shoppingCheckedMoveDelay]. The first case below is what pins that
/// distinction down, and it is the reason the design is safe: a user's tick
/// cannot be lost by a delay that does not exist.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/shopping/shopping_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the WRITE lands immediately while the row is still held in its aisle — '
    'only the move is delayed, so a tick can never be lost',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'item-1');
      final item = await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(
        row.checkedAt,
        isNotNull,
        reason:
            'the write must be through before the beat expires — the beat '
            'delays the row MOVE, never the user action',
      );
      expect(find.text('In the cart (1)'), findsNothing);

      // Let the beat expire so nothing is left mid-flight for the next
      // assertion or for teardown.
      await tester.pumpAndSettle();

      handle.dispose();
    },
  );

  testChoreApp(
    'a ticked row stays under its category header, visibly ticked, for the '
    'beat — then moves to the cart',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'item-1');
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Still where it was...
      expect(find.text('UNCATEGORIZED'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('In the cart (1)'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsNothing);
      // ...and already showing as ticked. Strikethrough rather than the
      // ring's fill colour because `design-language.md` makes the
      // strikethrough the non-colour signal — the one a user who cannot
      // distinguish the ring's fill still gets.
      expect(
        tester.widget<Text>(find.text('Milk')).style?.decoration,
        TextDecoration.lineThrough,
      );

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('In the cart (1)'), findsOneWidget);
      expect(find.text('UNCATEGORIZED'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'unticking from the cart section is symmetric: the row stays in the '
    'cart, visibly unticked, for the same beat',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'item-1');
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(item.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await expandCartSection(tester, 'In the cart (1)');

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Still inside the cart section, which is still mounted...
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsOneWidget,
      );
      expect(find.text('UNCATEGORIZED'), findsNothing);
      // ...and already showing as unticked.
      expect(
        tester.widget<Text>(find.text('Milk')).style?.decoration,
        isNot(TextDecoration.lineThrough),
      );

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.text('UNCATEGORIZED'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a tick left mid-beat leaves no pending timer behind',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'item-1');
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Deliberately NOT waiting the beat out. There is no assertion here,
      // because the assertion is made for us: `flutter_test` fails a test
      // that ends with a pending timer, and that check runs AFTER the
      // binding unmounts the tree (backlog A-2b). So this case passes if
      // and only if the beat's timer is cancelled in `dispose()`, and fails
      // with "A Timer is still pending" if a future edit forgets to.

      handle.dispose();
    },
  );

  test('the beat is long enough to see and short enough not to drag', () {
    // Not a change-detector on the exact number: a band, with the reasoning
    // that picks it. Below ~250ms the two visual changes (ring fill,
    // strikethrough) are gone before a glance lands on them, which is the
    // complaint. Above ~400ms — the Doherty threshold, and the point
    // Material's own long transitions stop at — the list starts feeling
    // like it is lagging behind the thumb, which is a worse complaint than
    // the one being fixed. 350ms sits near the top of that band because the
    // beat competes with the NEXT tap, not with nothing: a shopper ticking
    // a row every half second still sees each row leave before the next one
    // is touched.
    expect(shoppingCheckedMoveDelay.inMilliseconds, inInclusiveRange(250, 400));
  });
}
