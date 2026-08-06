/// C3 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
/// completing a chore occurrence fires `HapticFeedback.mediumImpact()`
/// exactly once, after the write is confirmed. `HapticFeedback` goes
/// through `SystemChannels.platform`, so this asserts via a mock method
/// call handler on that channel rather than trying to observe a side
/// effect.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'completing an occurrence fires exactly one medium-impact haptic',
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
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      final hapticCalls = calls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .toList();
      expect(hapticCalls, hasLength(1));
      expect(hapticCalls.single.arguments, 'HapticFeedbackType.mediumImpact');

      handle.dispose();
    },
  );
}
