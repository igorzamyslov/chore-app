import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the collapsed 'Done today (N)' section and its
/// Reopen action (see `docs/specs/ux-round-2.md` A3).
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'a completed one-off chore appears collapsed under "Done today (1)", '
    'with the closer shown, and Reopen restores it to pending',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final meMember = await database.select(database.members).getSingle();
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

      final pending = await ChoreRepository(
        database,
      ).pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(pending!.id, completedBy: meMember.id);
      await tester.pumpAndSettle();

      // Collapsed by default: the header shows the count, but the row
      // itself (and its title text) isn't in the tree yet.
      expect(find.bySemanticsIdentifier('chores.done.header'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);
      expect(find.text('One-off chore'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('One-off chore'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('by Me'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('chores.done.${pending.id}.reopen'),
      );
      await tester.pumpAndSettle();

      // Reopened: back to pending, the Done section is gone (count 0).
      expect(find.bySemanticsIdentifier('chores.done.header'), findsNothing);
      expect(find.text('One-off chore'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a skipped occurrence shows the "Skipped" marker instead of "Done"',
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
        title: 'Skippable chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      final pending = await ChoreRepository(
        database,
      ).pendingOccurrenceOf(chore.id);
      await service.skipOccurrence(pending!.id);
      await tester.pumpAndSettle();

      expect(find.text('Done today (1)'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Done'), findsNothing);

      handle.dispose();
    },
  );
}
