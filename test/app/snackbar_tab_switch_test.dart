import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

/// Field feedback B1 (`docs/feedback/2026-08-01-field-feedback.md`):
/// regardless of the sticky-snackbar mechanism (see
/// `sticky_snackbar_test.dart` for that investigation), switching tabs
/// always clears any snackbar showing on the tab being left immediately --
/// a completion/skip toast is contextual to where it happened, not
/// something that should follow the user to another tab or still be
/// tappable ("Undo") once they've moved on.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'switching tabs clears the showing snackbar immediately, with no need '
    'to wait out its duration',
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
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Switch away immediately -- no waiting at all.
      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      // Gone right away, well before the 4s duration would have elapsed.
      expect(find.byType(SnackBar), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the cleared snackbar does not reappear when switching back to the '
    'original tab',
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
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      handle.dispose();
    },
  );
}
