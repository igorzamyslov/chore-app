import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'completing a recurring occurrence re-renders the tile with the next '
    'due date',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      final chore = await service.createChore(
        householdId: householdId,
        title: 'Weekly chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );

      await tester.pumpAndSettle();

      // Due today: shows under the "Today" section header, and the tile's
      // own due text also reads "Today" (A1: due text on every tile) — two
      // matches, not "Later".
      // Refined A1: tiles under Today show no due text, so 'Today' appears
      // exactly once — as the section header.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Later'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      // Weekly, schedule-anchored, closed on its due date: the next pending
      // occurrence is due exactly 7 days later (2026-07-29) — still in
      // July, so it falls under "This month", not "Today".
      expect(find.text('Today'), findsNothing);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Weekly chore'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
