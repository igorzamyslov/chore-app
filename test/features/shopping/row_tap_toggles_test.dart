/// Widget coverage for the row's primary gesture after the 2026-09-19
/// field report: tapping ANYWHERE on a shopping row ticks the item, exactly
/// as the 48dp check ring already did. Ticking is the thing a user does
/// dozens of times per shop; editing is rare, so editing moved to
/// long-press (`long_press_menu_test.dart`).
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'tapping the row body ticks the item and moves it into the cart, '
    'without opening the edit sheet',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Milk'));
      await settleTickBeat(tester);

      expect(find.text('In the cart (1)'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.empty'), findsOneWidget);
      // The row's tap is the tick, not a second door to the edit sheet.
      expect(find.bySemanticsIdentifier('shopping.edit.name'), findsNothing);
      expect(find.bySemanticsIdentifier('shopping.edit.save'), findsNothing);

      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(row.checkedAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'tapping a checked row in the expanded cart section unticks it',
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

      await tester.tap(find.text('Milk'));
      await settleTickBeat(tester);

      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.text('UNCATEGORIZED'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shopping.edit.name'), findsNothing);

      final row = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.id.equals(item.id))).getSingle();
      expect(row.checkedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'the row tap fires exactly one selection-click haptic, the same as the '
    'check ring — one tick, one confirmation',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();

      final hapticCalls = calls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .toList();
      expect(hapticCalls, hasLength(1));
      expect(hapticCalls.single.arguments, 'HapticFeedbackType.selectionClick');

      handle.dispose();
    },
  );
}
