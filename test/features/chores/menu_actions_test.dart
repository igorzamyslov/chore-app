import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'skip creates the next occurrence',
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
        title: 'Weekly chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );
      await tester.pumpAndSettle();
      // The "TODAY" section header, plus the tile's own due text (A1: due
      // text on every tile) — two matches.
      // Refined A1: tiles under Today show no due text, so 'TODAY' appears
      // exactly once — as the section header. Section headers render
      // uppercase (theme-v2.md §2/§4.1 item 2).
      expect(find.text('TODAY'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.skip'));
      await tester.pumpAndSettle();

      // Skipping today's occurrence inserts the next weekly slot, 7 days
      // out (2026-07-29) — still in July, so "THIS MONTH", not "TODAY".
      expect(find.text('TODAY'), findsNothing);
      expect(find.text('THIS MONTH'), findsOneWidget);
      expect(find.text('Weekly chore'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'pause removes the tile',
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
      expect(find.text('One-off chore'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.pause'));
      await tester.pumpAndSettle();

      expect(find.text('One-off chore'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'delete asks for confirmation; cancel keeps it, confirm removes it',
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
        title: 'Deletable chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      Future<void> openMenuAndDelete() async {
        await tester.tap(
          find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('chores.menu.delete'));
        await tester.pumpAndSettle();
      }

      // Cancel: the confirmation dialog closes, the tile stays.
      await openMenuAndDelete();
      expect(
        find.bySemanticsIdentifier('chores.delete.confirm'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('chores.delete.cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Deletable chore'), findsOneWidget);

      // Confirm: the tile is removed.
      await openMenuAndDelete();
      await tester.tap(find.bySemanticsIdentifier('chores.delete.confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Deletable chore'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      handle.dispose();
    },
  );
}
