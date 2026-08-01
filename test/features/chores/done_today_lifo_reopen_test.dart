import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the LIFO Reopen-affordance rule (field feedback B2,
/// `docs/feedback/2026-08-01-field-feedback.md`; spec
/// `docs/specs/ux-round-2.md` A3 and `docs/specs/occurrence-lifecycle.md`
/// §reopenOccurrence): with several closed-today rows for ONE chore, only
/// the latest (by due date, then close time) shows the Reopen action, and
/// the affordance reappears on the next row as the chain unwinds.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'two closed-today rows for one chore: only the latest shows Reopen; '
    'after reopening it, the other row shows it',
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
        title: 'Water plants',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          3,
          anchor: RecurrenceAnchor.completion,
        ),
      );
      await tester.pumpAndSettle();

      // Close A (due today), which creates B due today+3 (completion
      // anchor). Then close B TODAY too (early), which creates C, ALSO due
      // today+3 (done always anchors at closedOn) -- leaving A and B as
      // the two closed-today rows, B (due today+3) the latest.
      final a = await repo.pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(a!.id, completedBy: meMember.id);
      final b = await repo.pendingOccurrenceOf(chore.id);
      expect(b!.dueDate, PlainDate(2026, 7, 25));
      await service.completeOccurrence(b.id, completedBy: meMember.id);
      await tester.pumpAndSettle();

      expect(find.text('Done today (2)'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      // Only B's row shows Reopen; A's does not.
      expect(
        find.bySemanticsIdentifier('chores.done.${b.id}.reopen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chores.done.${a.id}.reopen'),
        findsNothing,
      );

      // Reopen B (the only affordance available) -- the chain unwinds one
      // step, and A's row now shows the affordance.
      await tester.tap(
        find.bySemanticsIdentifier('chores.done.${b.id}.reopen'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Done today (1)'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.done.${a.id}.reopen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chores.done.${b.id}.reopen'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
