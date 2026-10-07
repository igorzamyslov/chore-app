import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'edit round-trip: open prefilled, change the title, save, list shows it',
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
        title: 'Original title',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();

      // Prefilled from the existing chore.
      expect(find.text('Original title'), findsOneWidget);

      final titleField = find.descendant(
        of: find.bySemanticsIdentifier('chore_form.title'),
        matching: find.byType(TextField),
      );
      await tester.enterText(titleField, 'Updated title');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      // Back on the list, showing the updated title.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);
      expect(find.text('Updated title'), findsOneWidget);
      expect(find.text('Original title'), findsNothing);

      handle.dispose();
    },
  );

  // Persona review 2026-10-06 C6: saving an edit used to pop silently.
  testChoreApp(
    'a plain edit confirms with a "Saved" snackbar',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Water plants',
            startDate: PlainDate(2026, 7, 24),
            assignmentMode: AssignmentMode.anyone,
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.bySemanticsIdentifier('chore_form.title'),
          matching: find.byType(TextField),
        ),
        'Water all plants',
      );
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(find.text('Saved'), findsOneWidget);

      handle.dispose();
    },
  );

  // Persona review 2026-10-06 C1 (Maria P1-A): taking the holder off a
  // chore moves the open turn, and the save says so.
  testChoreApp(
    'changing a fixed assignee moves the open turn and names the new holder',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final members = HouseholdRepository(database);
      final anna = await members.addMember(
        householdId,
        name: 'Anna',
        color: 0xFF112233,
      );
      final ben = await members.addMember(
        householdId,
        name: 'Ben',
        color: 0xFF445566,
      );
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Bins',
            startDate: PlainDate(2026, 7, 24),
            assignmentMode: AssignmentMode.fixed,
            recurrence: Recurrence.everyNDays(1),
            assigneeMemberIds: [anna.id],
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();
      final benChip = find.bySemanticsIdentifier(
        'chore_form.assignee.${ben.id}',
      );
      await tester.ensureVisible(benChip);
      await tester.tap(benChip);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(find.text("Saved — today's turn is now Ben's"), findsOneWidget);
      final pending = await ChoreRepository(
        database,
      ).pendingOccurrenceOf(chore.id);
      expect(pending!.assignedMemberId, ben.id);

      handle.dispose();
    },
  );

  testChoreApp(
    'a schedule edit says when the chore is next due',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Water plants',
            startDate: PlainDate(2026, 7, 24),
            assignmentMode: AssignmentMode.anyone,
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();
      // One-off -> recurring is a schedule change: the open turn is
      // regenerated.
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saved — next due'), findsOneWidget);

      handle.dispose();
    },
  );
}
