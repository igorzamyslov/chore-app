import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
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
}
