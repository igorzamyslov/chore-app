import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
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

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Restored: back under "Today", the "This month"/"Done today"
      // sections it briefly created/populated are gone.
      expect(find.bySemanticsIdentifier('chores.done.header'), findsNothing);
      expect(find.text('This month'), findsNothing);
      expect(find.text('Today'), findsNWidgets(2));
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
}
