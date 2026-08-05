import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the chores-list empty states: the two from spec
/// `docs/specs/polish-round-1.md` A1 -- 'fresh install' (zero non-deleted
/// chores in the household) vs 'all done' (chores exist, none pending),
/// both sharing the same outer `chores.empty` container id -- plus the B1
/// filtered-empty state (spec `docs/feedback/2026-08-01-ux-audit.md`),
/// which has its own top-level `chores.empty.filtered` id (not nested
/// under `chores.empty` -- no E2E flow filters, so nothing depends on
/// nesting).
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

  testChoreApp(
    'B1 (spec docs/feedback/2026-08-01-ux-audit.md): filtering to a member '
    'with no matching occurrence at all shows the honest filtered-empty '
    "state instead of the unqualified praise copy, and 'Show everything' "
    'resets the filter',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      // Unassigned ("anyone" mode): never matches ANY specific member
      // filter, so filtering to Anna hides it -- she has no occurrence of
      // any kind (pending, paused, or done-today).
      await service.createChore(
        householdId: householdId,
        title: 'My chore',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      expect(find.text('My chore'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('Anna'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My chore'), findsNothing);
      expect(
        find.bySemanticsIdentifier('chores.empty.filtered'),
        findsOneWidget,
      );
      // Neither of the genuinely-empty variants renders alongside it.
      expect(find.bySemanticsIdentifier('chores.empty'), findsNothing);
      expect(find.text('Nothing here for this filter.'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.filter.clear'));
      await tester.pumpAndSettle();

      expect(find.text('My chore'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.empty.filtered'),
        findsNothing,
      );
      // Both filter icons are back to their unbadged state.
      expect(find.byType(Badge), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'B1 guard: a filter set on a fresh install (zero chores in the '
    'household at all) keeps the fresh-install copy rather than the '
    "filtered-empty state -- clearing the filter wouldn't reveal anything "
    'either',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.empty.fresh'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('Me'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.empty.fresh'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.empty.filtered'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
