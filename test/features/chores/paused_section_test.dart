import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the collapsed 'Paused (N)' section and its Resume
/// action (see `docs/specs/ux-round-2.md` A5).
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'a paused chore appears collapsed under "Paused (1)", and Resume '
    'brings it back to the pending list',
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
        title: 'Pausable chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await service.pauseChore(chore.id);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chores.paused.header'),
        findsOneWidget,
      );
      expect(find.text('Paused (1)'), findsOneWidget);
      // Collapsed: the row (and its title/badge) isn't in the tree yet.
      expect(find.text('Pausable chore'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      expect(find.text('Pausable chore'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('chores.paused.${chore.id}.resume'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.paused.header'), findsNothing);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  // OPD-3. A paused row answers "what was this doing?", which is exactly
  // what recurrence prose is for, and until G-2 it said only "Paused". The
  // pending tiles deliberately do NOT get this: a tile answers "when is
  // this due", already carries a due chip, and prose there would spend
  // density on the most-opened screen for something the user did not come
  // for.
  testChoreApp(
    'a paused recurring chore says what it was doing, via the one shared '
    'recurrence formatter',
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
        title: 'Water the plants',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(
          interval: 2,
          weekdays: {DateTime.tuesday, DateTime.friday},
        ),
      );
      await tester.pumpAndSettle();
      await service.pauseChore(chore.id);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      // Byte-identical to what recurrence_sentence_test.dart asserts of the
      // formatter, and to what the form's own anchor card shows -- that is
      // the point of there being exactly one of them.
      expect(find.text('Every 2 weeks on Tuesday, Friday'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a paused one-off chore shows no recurrence clause',
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
        title: 'Cancel the gym',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      await service.pauseChore(chore.id);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel the gym'), findsOneWidget);
      expect(find.textContaining('Every'), findsNothing);

      handle.dispose();
    },
  );

  // Persona review 2026-10-06 C4 (Maria P2-C): a paused chore could be
  // neither edited nor deleted without resuming it first.
  Future<Chore> seedPaused(AppDatabase database) async {
    final service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    final chore = await service.createChore(
      householdId: await currentHouseholdId(database),
      title: 'Bed sheets',
      startDate: PlainDate(2026, 7, 22),
      assignmentMode: AssignmentMode.anyone,
      recurrence: Recurrence.weekly(),
    );
    await service.pauseChore(chore.id);
    return chore;
  }

  testChoreApp(
    'tapping a paused row opens a sheet with Resume, Edit and Delete only',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final chore = await seedPaused(database);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.paused.${chore.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.menu.resume'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.menu.edit'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.menu.delete'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.menu.skip'), findsNothing);
      expect(find.bySemanticsIdentifier('chores.menu.pause'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('chore_form.save'), findsOneWidget);
      expect(find.text('Bed sheets'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a paused chore can be deleted from its long-press sheet',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final chore = await seedPaused(database);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      await tester.longPress(
        find.bySemanticsIdentifier('chores.paused.${chore.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.delete.confirm'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.paused.header'), findsNothing);
      final details = await ChoreRepository(database).getChore(chore.id);
      expect(details!.chore.deletedAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'Resume from the paused sheet brings the chore back',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final chore = await seedPaused(database);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.paused.${chore.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.resume'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.paused.header'), findsNothing);
      expect(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  // Persona review 2026-10-06 C2 ("Pause until").
  testChoreApp(
    'Pause › Until a date… pauses until the picked day and says so on the '
    'paused row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: await currentHouseholdId(database),
            title: 'Bed sheets',
            startDate: PlainDate(2026, 7, 22),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.weekly(),
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.pause'));
      await tester.pumpAndSettle();
      expect(find.text('Until I resume it'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('chores.pause.untilDate'));
      await tester.pumpAndSettle();
      // The picker opens on tomorrow (its earliest day); accept it.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final details = await ChoreRepository(database).getChore(chore.id);
      expect(details!.chore.pausedUntil, PlainDate(2026, 7, 23));
      expect(find.text('Paused until Thu, Jul 23'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('chores.paused.${chore.id}'),
          matching: find.text('Paused until Thu, Jul 23'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a chore paused until today is back in the list at start-up',
    today: today,
    seed: (database) async {
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(DateTime(2026, 7, 20, 9)),
      );
      final chore = await service.createChore(
        householdId: await currentHouseholdId(database),
        title: 'Bed sheets',
        startDate: PlainDate(2026, 7, 20),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );
      await service.pauseChore(chore.id, until: PlainDate(2026, 7, 22));
    },
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.paused.header'), findsNothing);
      expect(find.text('Bed sheets'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);

      handle.dispose();
    },
  );
}
