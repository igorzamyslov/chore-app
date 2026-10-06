import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the day-progress card's counting rule (spec
/// `docs/specs/theme-v2.md` §4.1 item 1): `M` = still-pending occurrences
/// due TODAY, plus occurrences completed (done, never skipped) today; `N` =
/// occurrences completed today. The overdue pile is NOT part of `M`: it is
/// reported separately as "N to catch up" on the sub-line (persona review
/// 2026-10-06 E5, amending the original due-or-overdue rule). The card is
/// hidden entirely when `M == 0`.
///
/// **Changed 2026-08-07** (triage T1.1/D3): `M`/`N` are now computed from
/// the SAME member/category-filtered collections the sections below render
/// -- never the whole household when a filter is active -- and the card
/// shows a short line when a filter is narrowing them. See the "member
/// filter" and "filter-active line" tests below for the exact regression
/// this fixes and the new behavior it replaces it with.
void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);
  final todayPlain = PlainDate(2026, 7, 22);

  Future<void> tapMenuEntry(WidgetTester tester, String text) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String?>),
        matching: find.text(text),
      ),
    );
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'M == 0 on a fresh install: the progress card is hidden entirely',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.progress'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'M counts pending-due-today plus completed-today; overdue is reported '
    'as "to catch up" instead, and a future-due pending occurrence and a '
    'skipped-today occurrence are both excluded',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final meMember = await database.select(database.members).getSingle();
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );

      // Stays pending, due today -- counts toward M.
      await service.createChore(
        householdId: householdId,
        title: 'Due today, still pending',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.anyone,
      );
      // Completed today -- counts toward both M and N.
      final completedChore = await service.createChore(
        householdId: householdId,
        title: 'Due today, completed',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.anyone,
      );
      // Stays pending, overdue -- NOT part of M (E5), counted as catch-up.
      await service.createChore(
        householdId: householdId,
        title: 'Overdue, still pending',
        startDate: PlainDate(2026, 7, 20),
        assignmentMode: AssignmentMode.anyone,
      );
      // Due tomorrow, never touched -- NOT due today or overdue, so it must
      // NOT count toward M.
      await service.createChore(
        householdId: householdId,
        title: 'Due tomorrow',
        startDate: PlainDate(2026, 7, 23),
        assignmentMode: AssignmentMode.anyone,
      );
      // Skipped today -- neither "still pending" nor "completed" (done), so
      // it must be excluded from M entirely, not just from N.
      final skippedChore = await service.createChore(
        householdId: householdId,
        title: 'Due today, skipped',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      final completedPending = await repo.pendingOccurrenceOf(
        completedChore.id,
      );
      await service.completeOccurrence(
        completedPending!.id,
        completedBy: meMember.id,
      );
      final skippedPending = await repo.pendingOccurrenceOf(skippedChore.id);
      await service.skipOccurrence(skippedPending!.id);
      await tester.pumpAndSettle();

      // M = 1 still-pending due today + 1 completed-today = 2; N = 1.
      // The overdue chore sits beside it as "1 to catch up".
      expect(find.bySemanticsIdentifier('chores.progress'), findsOneWidget);
      expect(find.text('1 of 2 done today'), findsOneWidget);
      expect(find.text('1 still to go'), findsOneWidget);
      expect(find.text('1 to catch up'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'K == 0 (every counted occurrence completed) shows the done-for-the-day '
    'line instead of "still to go"',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final meMember = await database.select(database.members).getSingle();
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );

      final chore = await service.createChore(
        householdId: householdId,
        title: 'Only chore today',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      final pending = await repo.pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(pending!.id, completedBy: meMember.id);
      await tester.pumpAndSettle();

      // M = N = 1, K = 0.
      expect(find.bySemanticsIdentifier('chores.progress'), findsOneWidget);
      expect(find.text('1 of 1 done today'), findsOneWidget);
      expect(find.text("That's everything for today."), findsOneWidget);
      expect(find.text('0 still to go'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'E5: only an overdue pile and nothing due today hides the card; the '
    'overdue tiles still show in their own section',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      ).createChore(
        householdId: householdId,
        title: 'Long overdue',
        startDate: PlainDate(2026, 7, 15),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.progress'), findsNothing);
      expect(find.text('Long overdue'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'E5: everything due today done, with two overdue: the "everything" line '
    'and the catch-up count share the sub-line, and the ring stays at 100%',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final me = await database.select(database.members).getSingle();
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );
      final dueToday = await service.createChore(
        householdId: householdId,
        title: 'Due today',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.anyone,
      );
      for (final title in ['Overdue one', 'Overdue two']) {
        await service.createChore(
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 7, 18),
          assignmentMode: AssignmentMode.anyone,
        );
      }
      await tester.pumpAndSettle();
      final pending = await repo.pendingOccurrenceOf(dueToday.id);
      await service.completeOccurrence(pending!.id, completedBy: me.id);
      await tester.pumpAndSettle();

      expect(find.text('1 of 1 done today'), findsOneWidget);
      expect(find.text("That's everything for today."), findsOneWidget);
      expect(find.text('2 to catch up'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'T1.1 regression: filtering to one member narrows the card exactly like '
    'it narrows the list beneath it, instead of still showing the whole '
    "household's count",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final households = HouseholdRepository(database);
      final me = await database.select(database.members).getSingle();
      final anna = await households.addMember(
        householdId,
        name: 'Anna',
        color: 0xFF8C7BC9,
      );
      final repo = ChoreRepository(database);
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );

      // Anna: one still-pending, one completed today.
      await service.createChore(
        householdId: householdId,
        title: 'Anna pending',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [anna.id],
      );
      final annaDone = await service.createChore(
        householdId: householdId,
        title: 'Anna done',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [anna.id],
      );
      // Me: one still-pending.
      await service.createChore(
        householdId: householdId,
        title: 'Me pending',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [me.id],
      );
      await tester.pumpAndSettle();

      final annaDonePending = await repo.pendingOccurrenceOf(annaDone.id);
      await service.completeOccurrence(
        annaDonePending!.id,
        completedBy: anna.id,
      );
      await tester.pumpAndSettle();

      // Unfiltered (household-wide): M = 2 pending + 1 completed = 3, N = 1.
      expect(find.text('1 of 3 done today'), findsOneWidget);

      // Filter to Me: the list beneath shows only "Me pending" -- before
      // this fix, the card still read "1 of 3" (the whole household) here.
      // Now it must match the filtered list: M = 1 pending + 0 completed
      // for Me = 1, N = 0.
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'Me (you)');

      expect(find.text('Me pending'), findsOneWidget);
      expect(find.text('Anna pending'), findsNothing);
      expect(find.textContaining('Done recently'), findsNothing);

      expect(find.text('0 of 1 done today'), findsOneWidget);
      expect(find.text('1 still to go'), findsOneWidget);
      expect(find.text('1 of 3 done today'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the filter-active line shows only while a member/category filter is '
    'on, and never changes the N-of-M sentence itself',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await database.select(database.members).getSingle();
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      await service.createChore(
        householdId: householdId,
        title: 'Fixed to me',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [me.id],
      );
      await tester.pumpAndSettle();

      // No filter yet: no filter-active line.
      expect(find.text('0 of 1 done today'), findsOneWidget);
      expect(
        find.text('Filtered — not the whole household'),
        findsNothing,
      );

      // Filter to Me: the occurrence still matches, so the sentence is
      // unchanged, but the card now discloses that a filter is active.
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'Me');

      expect(find.text('0 of 1 done today'), findsOneWidget);
      expect(
        find.text('Filtered — not the whole household'),
        findsOneWidget,
      );

      // Reset: the line disappears again.
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'All members');

      expect(
        find.text('Filtered — not the whole household'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
