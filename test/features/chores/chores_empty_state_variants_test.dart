import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the two distinct chores-list empty states (spec
/// `docs/specs/polish-round-1.md` A1): 'fresh install' (zero non-deleted
/// chores in the household) vs 'all done' (chores exist, none pending),
/// both sharing the same outer `chores.empty` container id.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'fresh install: chores.empty.fresh with the add_task icon, not '
    'chores.empty.done',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.fresh'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.done'), findsNothing);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('chores.empty'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Icon && widget.icon == Icons.add_task_outlined,
          ),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'all done (inline branch, alongside a Done-today section): '
    'chores.empty.done with the task_alt icon',
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
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.done'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.fresh'), findsNothing);
      expect(find.text('No chores pending — nice work!'), findsOneWidget);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('chores.empty'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Icon && widget.icon == Icons.task_alt_outlined,
          ),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'all done (full-screen branch): a chore closed on a PREVIOUS day '
    "(no pending occurrence, not today's Done section, not paused) still "
    'counts as an existing chore, not a fresh install',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Long since finished',
        startDate: PlainDate(2026, 7, 20),
        assignmentMode: AssignmentMode.anyone,
      );
      final occurrence = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 7, 20),
      );
      await repo.closeOccurrence(
        occurrence.id,
        status: OccurrenceStatus.done,
        closedOn: PlainDate(2026, 7, 20),
      );
      await tester.pumpAndSettle();

      // No pending occurrence, nothing closed today, nothing paused: this
      // is the full-screen empty-state branch (`hasCollapsedSections` is
      // false), yet the household clearly isn't a fresh install.
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.done'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.fresh'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'deleting the only chore returns to the fresh-install copy, keeping '
    'the shared chores.empty container id E2E flows assert on',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('chores.empty'), findsNothing);

      await repo.softDeleteChore(chore.id);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.empty.fresh'), findsOneWidget);

      handle.dispose();
    },
  );
}
