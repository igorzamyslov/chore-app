import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the day-progress card's counting rule (spec
/// `docs/specs/theme-v2.md` §4.1 item 1): `M` = still-pending occurrences
/// due today or overdue, plus occurrences completed (done, never skipped)
/// today; `N` = occurrences completed today. The card is hidden entirely
/// when `M == 0`.
void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);
  final todayPlain = PlainDate(2026, 7, 22);

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
    'M counts pending-due-today/overdue plus completed-today; a future-due '
    'pending occurrence and a skipped-today occurrence are both excluded',
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
      // Stays pending, overdue -- counts toward M.
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

      // M = 2 still-pending (due today + overdue) + 1 completed-today = 3.
      // N = 1 completed-today.
      expect(find.bySemanticsIdentifier('chores.progress'), findsOneWidget);
      expect(find.text('1 of 3 done today'), findsOneWidget);
      expect(find.text('2 still to go'), findsOneWidget);

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
      expect(find.text("That's everything — nice work"), findsOneWidget);
      expect(find.text('0 still to go'), findsNothing);

      handle.dispose();
    },
  );
}
