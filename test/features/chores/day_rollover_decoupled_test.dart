/// A regression test that decouples `ChoresListScreen`'s direct
/// `ref.watch(todayProvider)` (backlog A-2 / audit P1) from
/// `closedTodayOccurrencesProvider`'s OWN dependency on [todayProvider].
///
/// Both providers watch `todayProvider`, so
/// `test/features/chores/day_rollover_widget_test.dart` -- which leaves
/// `closedTodayOccurrencesProvider` live -- cannot tell "the list re-buckets
/// because it reads today itself"
/// apart from "the list rebuilds only because its sibling stream provider
/// happened to rebuild for its own, unrelated reason". A reviewer confirmed
/// by controlled experiment that reverting `ChoresListScreen`'s
/// `todayProvider` watch to a one-shot `clockProvider.now()` read leaves the
/// full suite green -- proof the existing coverage was masking exactly this.
///
/// This test overrides `closedTodayOccurrencesProvider` with a FIXED, one-shot
/// empty stream that never depends on [todayProvider] at all, so it can never
/// rebuild `ChoresListScreen` on its own. With no chore ever completed today,
/// there is nothing for that section to show either way, so the override
/// changes nothing observable except removing the masking dependency.
library;

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  // Moved by the test body to cross local midnight. 2026-01-05 is a Monday,
  // so 'Tomorrow' (the 6th) is unambiguously not also 'This week'.
  var currentTime = DateTime(2026, 1, 5, 9);

  testChoreApp(
    'with closedTodayOccurrencesProvider held fixed (so it cannot mask the '
    'effect), crossing local midnight still re-buckets Tomorrow into Today',
    today: DateTime(2026, 1, 5, 9),
    clock: Clock(() => currentTime),
    overrides: [
      // A one-shot empty stream: it emits once and never again, so it never
      // depends on -- and never rebuilds in response to -- todayProvider.
      // Any re-bucketing observed below can therefore only come from
      // ChoresListScreen's own direct todayProvider watch.
      closedTodayOccurrencesProvider.overrideWith(
        (ref) => Stream.value(const []),
      ),
    ],
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock(() => currentTime),
      );

      // Due tomorrow: sits under TOMORROW today, under TODAY after midnight.
      // Nothing is ever overdue in this test, so catch-up would change
      // nothing and the date is the ONLY signal.
      await service.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate(2026, 1, 6),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);

      // Midnight. Not one row in the database changes.
      currentTime = DateTime(2026, 1, 6, 0, 0, 1);
      ProviderScope.containerOf(
        tester.element(find.byType(ChoreApp)),
        listen: false,
      ).read(todayProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text('TOMORROW'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);
    },
  );
}
