import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Persona review 2026-10-06 C2 (Maria P2-I): "Anna's ill. I just want Ben
/// to take her turn this week." One action-sheet row hands the open turn
/// to someone else, with Undo.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'Reassign this turn… hands the open turn to the picked member, and '
    'Undo hands it back',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final households = HouseholdRepository(database);
      final anna = await households.addMember(
        householdId,
        name: 'Anna',
        color: 0xFF112233,
      );
      final ben = await households.addMember(
        householdId,
        name: 'Ben',
        color: 0xFF445566,
      );
      final repo = ChoreRepository(database);
      final chore =
          await ChoreService(
            database: database,
            chores: repo,
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Bins',
            startDate: PlainDate(2026, 7, 22),
            assignmentMode: AssignmentMode.fixed,
            recurrence: Recurrence.weekly(),
            assigneeMemberIds: [anna.id],
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.reassign'));
      await tester.pumpAndSettle();

      expect(find.text('Who takes this turn?'), findsOneWidget);
      // The current holder is not offered.
      expect(
        find.bySemanticsIdentifier('chores.reassign.row.${anna.id}'),
        findsNothing,
      );
      await tester.tap(
        find.bySemanticsIdentifier('chores.reassign.row.${ben.id}'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reassigned to Ben'), findsOneWidget);
      expect(
        (await repo.pendingOccurrenceOf(chore.id))!.assignedMemberId,
        ben.id,
      );
      // One turn, not the chore: the chore is still Anna's.
      expect((await repo.getChore(chore.id))!.assigneeMemberIds, [anna.id]);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        (await repo.pendingOccurrenceOf(chore.id))!.assignedMemberId,
        anna.id,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a household of one has nobody to hand the turn to, so no row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: await currentHouseholdId(database),
            title: 'Bins',
            startDate: PlainDate(2026, 7, 22),
            assignmentMode: AssignmentMode.anyone,
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.menu.skip'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.menu.reassign'), findsNothing);

      handle.dispose();
    },
  );
}
