import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Persona review 2026-10-06 E9 (Leon A9): the Done section is "Done
/// recently" and keeps the last three days, newest first, each row naming
/// its day. Reopen stays a same-day affordance: older rows have none.
void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);

  /// Creates a one-off chore and closes its only occurrence on [closedOn].
  Future<ChoreOccurrence> closed(
    AppDatabase database,
    String title,
    PlainDate closedOn, {
    OccurrenceStatus status = OccurrenceStatus.done,
  }) async {
    final repo = ChoreRepository(database);
    final householdId = await currentHouseholdId(database);
    final me = await database.select(database.members).getSingle();
    final chore = await repo.createChore(
      householdId: householdId,
      title: title,
      startDate: closedOn,
      assignmentMode: AssignmentMode.anyone,
    );
    final occurrence = await repo.insertOccurrence(
      choreId: chore.id,
      dueDate: closedOn,
    );
    await repo.closeOccurrence(
      occurrence.id,
      status: status,
      closedOn: closedOn,
      completedBy: status == OccurrenceStatus.done ? me.id : null,
    );
    return occurrence;
  }

  testChoreApp(
    'the section is "Done recently (N)": three days, newest first, with '
    'Today / Yesterday / weekday labels; older closes are left out',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await closed(database, 'Done today', PlainDate(2026, 7, 22));
      await closed(database, 'Done yesterday', PlainDate(2026, 7, 21));
      await closed(database, 'Done monday', PlainDate(2026, 7, 20));
      await closed(database, 'Done long ago', PlainDate(2026, 7, 17));
      await tester.pumpAndSettle();

      expect(find.text('Done recently (3)'), findsOneWidget);
      expect(find.text('Done today (3)'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('Done long ago'), findsNothing);
      final order = ['Done today', 'Done yesterday', 'Done monday'];
      final dy = [for (final t in order) tester.getTopLeft(find.text(t)).dy];
      expect(dy, orderedEquals([...dy]..sort()));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    "only today's rows can be reopened",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final todays = await closed(
        database,
        'Done today',
        PlainDate(2026, 7, 22),
      );
      final older = await closed(
        database,
        'Done yesterday',
        PlainDate(2026, 7, 21),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chores.done.${todays.id}.reopen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chores.done.${older.id}.reopen'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a skipped row from yesterday still reads "Skipped" with its day',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await closed(
        database,
        'Skipped yesterday',
        PlainDate(2026, 7, 21),
        status: OccurrenceStatus.skipped,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(find.text('Skipped yesterday'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);

      handle.dispose();
    },
  );
}
