/// C3 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
/// checking a shopping item fires `HapticFeedback.selectionClick()` exactly
/// once, after the write is confirmed. `HapticFeedback` goes through
/// `SystemChannels.platform`, so this asserts via a mock method call
/// handler on that channel rather than trying to observe a side effect.
library;

import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'checking an item fires exactly one selection-click haptic',
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
      final repo = ShoppingRepository(database, newId: () => 'item-1');
      await repo.addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.item-1.check'),
      );
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
