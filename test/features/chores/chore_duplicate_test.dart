import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Persona review 2026-10-06 C9 (Maria P3-L): "I'm typing six chores from
/// scratch, and three of them are 'weekly, assigned to a kid'."
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'Duplicate opens the new-chore form prefilled with every field, and '
    'saving creates a second chore',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final leon = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Leon', color: 0xFF112233);
      final original =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Bins',
            notes: 'Blue bin on Fridays',
            startDate: PlainDate(2026, 7, 22),
            assignmentMode: AssignmentMode.fixed,
            recurrence: Recurrence.weekly(weekdays: {2, 5}),
            reminderMinutes: 18 * 60,
            assigneeMemberIds: [leon.id],
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${original.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.duplicate'));
      await tester.pumpAndSettle();

      // Create mode, everything carried over (title identical).
      expect(find.text('New chore'), findsOneWidget);
      expect(find.text('Bins'), findsOneWidget);
      expect(find.text('Blue bin on Fridays'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chores = await (database.select(
        database.chores,
      )..where((tbl) => tbl.deletedAt.isNull())).get();
      expect(chores, hasLength(2));
      final copy = chores.firstWhere((chore) => chore.id != original.id);
      expect(copy.title, 'Bins');
      expect(copy.notes, 'Blue bin on Fridays');
      expect(copy.recurrence, Recurrence.weekly(weekdays: {2, 5}));
      expect(copy.reminderMinutes, 18 * 60);
      expect(copy.assignmentMode, AssignmentMode.fixed);
      final copyDetails = await ChoreRepository(database).getChore(copy.id);
      expect(copyDetails!.assigneeMemberIds, [leon.id]);

      handle.dispose();
    },
  );
}
