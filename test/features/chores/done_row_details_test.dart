import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Persona review 2026-10-06 E6 (Leon A8/A9/C1): the Done section's rows say
/// "Done early" when the completion beat its due date, a skipped row stops
/// blaming the assignee, Reopen confirms itself ("Reopened"), and reopening
/// somebody else's completion asks first.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  Future<({ChoreService service, ChoreRepository repo, String householdId})>
  setUp(AppDatabase database) async {
    final repo = ChoreRepository(database);
    return (
      service: ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      ),
      repo: repo,
      householdId: await currentHouseholdId(database),
    );
  }

  Future<void> openDone(WidgetTester tester) async {
    await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'a completion before the due date is tagged "Done early"; on the day or '
    'late is not',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final env = await setUp(database);
      final me = await database.select(database.members).getSingle();
      Future<void> make(String title, PlainDate start) async {
        final chore = await env.service.createChore(
          householdId: env.householdId,
          title: title,
          startDate: start,
          assignmentMode: AssignmentMode.anyone,
        );
        final pending = await env.repo.pendingOccurrenceOf(chore.id);
        await env.service.completeOccurrence(pending!.id, completedBy: me.id);
      }

      await make('Early bird', PlainDate(2026, 7, 25));
      await make('On the day', PlainDate(2026, 7, 22));
      await make('Late one', PlainDate(2026, 7, 19));
      await tester.pumpAndSettle();
      await openDone(tester);

      expect(find.text('Done early'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Early bird'),
            matching: find.byType(ListTile),
          ),
          matching: find.text('Done early'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a skipped row does not name the assignee as the closer',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final env = await setUp(database);
      final me = await database.select(database.members).getSingle();
      final chore = await env.service.createChore(
        householdId: env.householdId,
        title: 'Skippable chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [me.id],
      );
      final pending = await env.repo.pendingOccurrenceOf(chore.id);
      await env.service.skipOccurrence(pending!.id);
      await tester.pumpAndSettle();
      await openDone(tester);

      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('by Me'), findsNothing);
      expect(find.textContaining('by '), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'reopening my own completion says "Reopened" and does not ask first',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final env = await setUp(database);
      final me = await database.select(database.members).getSingle();
      final chore = await env.service.createChore(
        householdId: env.householdId,
        title: 'My own chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = await env.repo.pendingOccurrenceOf(chore.id);
      await env.service.completeOccurrence(pending!.id, completedBy: me.id);
      await tester.pumpAndSettle();
      await openDone(tester);

      await tester.tap(
        find.bySemanticsIdentifier('chores.done.${pending.id}.reopen'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.reopen.confirm'), findsNothing);
      expect(find.text('Reopened'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    "reopening somebody else's completion asks first; Cancel keeps it "
    'closed, Reopen removes it from their history',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final env = await setUp(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(env.householdId, name: 'Anna', color: 0xFF112233);
      final chore = await env.service.createChore(
        householdId: env.householdId,
        title: "Anna's chore",
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = await env.repo.pendingOccurrenceOf(chore.id);
      await env.service.completeOccurrence(pending!.id, completedBy: anna.id);
      await tester.pumpAndSettle();
      await openDone(tester);

      final reopen = find.bySemanticsIdentifier(
        'chores.done.${pending.id}.reopen',
      );
      await tester.tap(reopen);
      await tester.pumpAndSettle();

      expect(find.text("Reopen Anna's completion?"), findsOneWidget);
      expect(
        find.text('This removes it from their history.'),
        findsOneWidget,
      );

      // Cancel: nothing changes.
      await tester.tap(find.bySemanticsIdentifier('chores.reopen.cancel'));
      await tester.pumpAndSettle();
      expect(find.text("Reopen Anna's completion?"), findsNothing);
      expect(find.text('Reopened'), findsNothing);
      expect(reopen, findsOneWidget);

      // Confirm: reopened.
      await tester.tap(reopen);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.reopen.confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Reopened'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
