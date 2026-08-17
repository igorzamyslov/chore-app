import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Verification suite for `docs/next-session-plan.md` #3: the 'Done today'
/// section filters on `closed_on == today`, NOT on due date, so completing
/// an overdue occurrence or a future-due occurrence today must both appear
/// there immediately, and undoing (reopening) either one must restore it at
/// its ORIGINAL due date — [ChoreService.reopenOccurrence] never touches
/// `dueDate`.
///
/// Kept in its own file (separate from `done_today_test.dart`, which covers
/// the collapsed-section mechanics themselves) so the two suites don't
/// collide while both are being worked on.
void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'a chore overdue before today, completed today: files under '
    'Done-today with the right closer, disappears from Overdue, and '
    'Reopen restores it to Overdue at its ORIGINAL due date',
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
        title: 'Overdue chore',
        startDate: PlainDate(2026, 7, 18),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      // Section headers render uppercase (theme-v2.md §2/§4.1 item 2).
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('Overdue chore'), findsOneWidget);

      // Completed via the service directly (not by tapping the tile's own
      // complete button), like done_today_test.dart: tapping the UI button
      // for a one-off chore also pops the bare "Done" undo snackbar, which
      // would otherwise collide with the Done-row's own "Done" status text
      // once the section below is expanded.
      final pending = await repo.pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(pending!.id, completedBy: meMember.id);
      await tester.pumpAndSettle();

      // Filters on closed_on == today, not due date: it appears in
      // Done-today immediately, despite being due days before today, and
      // the Overdue section (its only pending occurrence) is gone.
      expect(find.text('OVERDUE'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.done.header'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);
      // Collapsed by default; no pending occurrences remain (one-off, no
      // next slot), so the empty state shows alongside the collapsed Done
      // section -- same pattern as done_today_test.dart.
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('Overdue chore'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('by Me'), findsOneWidget);

      final closed = await repo.latestClosedOccurrence(chore.id);
      expect(closed!.status, OccurrenceStatus.done);
      expect(closed.dueDate, PlainDate(2026, 7, 18));
      expect(closed.closedOn, PlainDate(2026, 7, 22));

      await tester.tap(
        find.bySemanticsIdentifier('chores.done.${closed.id}.reopen'),
      );
      await tester.pumpAndSettle();

      // Undo restores it to pending AT ITS ORIGINAL (overdue) due date --
      // never at today's date.
      expect(find.bySemanticsIdentifier('chores.done.header'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.empty'), findsNothing);
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('Overdue chore'), findsOneWidget);

      final restored = await repo.pendingOccurrenceOf(chore.id);
      expect(restored!.id, closed.id);
      expect(restored.dueDate, PlainDate(2026, 7, 18));
      expect(restored.status, OccurrenceStatus.pending);

      handle.dispose();
    },
  );

  testChoreApp(
    'a chore due tomorrow, completed today: files under Done-today '
    'immediately, leaves no pending occurrence, and Reopen restores it to '
    'Tomorrow at its ORIGINAL due date',
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
        title: 'Tomorrow chore',
        startDate: PlainDate(2026, 7, 23),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Tomorrow chore'), findsOneWidget);

      // Completed via the service directly -- see the sibling test above
      // for why (avoids the bare "Done" undo snackbar colliding with the
      // Done-row's own status text).
      final pending = await repo.pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(pending!.id, completedBy: meMember.id);
      await tester.pumpAndSettle();

      // Not due until tomorrow, yet it shows up today: closed_on == today
      // is what drives this section, not due date.
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.done.header'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('Tomorrow chore'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('by Me'), findsOneWidget);

      final closed = await repo.latestClosedOccurrence(chore.id);
      expect(closed!.status, OccurrenceStatus.done);
      expect(closed.dueDate, PlainDate(2026, 7, 23));
      expect(closed.closedOn, PlainDate(2026, 7, 22));

      await tester.tap(
        find.bySemanticsIdentifier('chores.done.${closed.id}.reopen'),
      );
      await tester.pumpAndSettle();

      // Undo restores it to pending AT ITS ORIGINAL (future) due date --
      // never at today's date.
      expect(find.bySemanticsIdentifier('chores.done.header'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.empty'), findsNothing);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Tomorrow chore'), findsOneWidget);

      final restored = await repo.pendingOccurrenceOf(chore.id);
      expect(restored!.id, closed.id);
      expect(restored.dueDate, PlainDate(2026, 7, 23));
      expect(restored.status, OccurrenceStatus.pending);

      handle.dispose();
    },
  );

  testChoreApp(
    'an overdue-completed-today chore and a future-due-completed-today '
    'chore coexist in Done-today at once, each correctly attributed, and '
    'reopening one leaves the other untouched',
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
      final overdueChore = await service.createChore(
        householdId: householdId,
        title: 'Overdue chore',
        startDate: PlainDate(2026, 7, 18),
        assignmentMode: AssignmentMode.anyone,
      );
      final futureChore = await service.createChore(
        householdId: householdId,
        title: 'Tomorrow chore',
        startDate: PlainDate(2026, 7, 23),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      final overduePending = await repo.pendingOccurrenceOf(overdueChore.id);
      final futurePending = await repo.pendingOccurrenceOf(futureChore.id);
      await service.completeOccurrence(
        overduePending!.id,
        completedBy: meMember.id,
      );
      await service.completeOccurrence(
        futurePending!.id,
        completedBy: meMember.id,
      );
      await tester.pumpAndSettle();

      expect(find.text('OVERDUE'), findsNothing);
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.text('Done today (2)'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('Overdue chore'), findsOneWidget);
      expect(find.text('Tomorrow chore'), findsOneWidget);
      expect(find.text('by Me'), findsNWidgets(2));

      // Reopen only the overdue one; the future-due one stays closed.
      final overdueClosed = await repo.latestClosedOccurrence(overdueChore.id);
      await tester.tap(
        find.bySemanticsIdentifier('chores.done.${overdueClosed!.id}.reopen'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.empty'), findsNothing);
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('Overdue chore'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);

      final futureStillClosed = await repo.latestClosedOccurrence(
        futureChore.id,
      );
      expect(futureStillClosed!.status, OccurrenceStatus.done);
      expect(await repo.pendingOccurrenceOf(futureChore.id), isNull);

      handle.dispose();
    },
  );
}
