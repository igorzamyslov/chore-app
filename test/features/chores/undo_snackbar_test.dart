import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the complete/skip undo snackbar (see
/// `docs/specs/ux-round-2.md` A4).
void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'completing a recurring chore shows the "next due" snackbar, and UNDO '
    'restores the original occurrence',
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
        title: 'Recurring chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      // Weekly, due exactly 7 days out from today: "In 7 days".
      expect(find.text('Done — next due In 7 days'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);

      // showAppSnackbar's presentation: 4s floating (see
      // lib/app/snackbars.dart), not the 5s fixed bar this used to be.
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.duration, const Duration(seconds: 4));
      expect(snackBar.behavior, SnackBarBehavior.floating);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Restored: back under "TODAY", the "THIS MONTH"/"Done today"
      // sections it briefly created/populated are gone. Section headers
      // render uppercase (theme-v2.md §2/§4.1 item 2).
      expect(find.bySemanticsIdentifier('chores.done.header'), findsNothing);
      expect(find.text('THIS MONTH'), findsNothing);
      // Refined A1: tiles under Today show no due text, so 'TODAY' appears
      // exactly once — as the section header.
      expect(find.text('TODAY'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'completing a one-off chore shows the bare "Done" snackbar',
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
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Done — next due In 7 days'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'skipping a recurring chore shows the "next due" snackbar with '
    '"Skipped"',
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
        title: 'Recurring chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.skip'));
      await tester.pumpAndSettle();

      expect(find.text('Skipped — next due In 7 days'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    "completing a second chore clears the first chore's snackbar instead "
    'of queuing behind it — latest action wins',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final oneOff = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      final recurring = await service.createChore(
        householdId: householdId,
        title: 'Recurring chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${oneOff.id}.complete'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier(
          'chores.occurrence.${recurring.id}.complete',
        ),
      );
      await tester.pumpAndSettle();

      // Still exactly one SnackBar — the first's is gone, replaced by (not
      // queued behind) the second's, per showAppSnackbar's clearSnackBars()
      // call (lib/app/snackbars.dart).
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Done — next due In 7 days'), findsOneWidget);
      expect(find.text('Done'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the snackbar presents above the bottom tab bar, never overlapping it',
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
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      final snackBarRect = tester.getRect(find.byType(SnackBar));
      // The hand-rolled tab bar (`_BottomTabBar` in lib/app/app_shell.dart)
      // has no finder of its own; its footprint is approximated by the
      // union of its three public per-tab semantic identifiers.
      final tabBarRect = tester
          .getRect(find.bySemanticsIdentifier('shell.tab.chores'))
          .expandToInclude(
            tester.getRect(find.bySemanticsIdentifier('shell.tab.shopping')),
          )
          .expandToInclude(
            tester.getRect(find.bySemanticsIdentifier('shell.tab.settings')),
          );

      expect(snackBarRect.overlaps(tabBarRect), isFalse);
      // Not merely non-overlapping but with the floating margin's
      // breathing room above it, not a coincidental touching edge.
      expect(snackBarRect.bottom, lessThan(tabBarRect.top));

      handle.dispose();
    },
  );
}
