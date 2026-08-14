/// The UI half of backlog A-2 / audit P1: with NOTHING overdue and no other
/// trigger, crossing local midnight must re-bucket the list and empty the
/// 'Done today' section.
///
/// The controller half (what actually calls [TodayNotifier.refresh] at
/// midnight and on resume) is covered in `test/app/day_change_catchup_test.dart`;
/// this test calls `refresh()` directly rather than arming the real
/// day-change timer inside a pumped widget tree, which would leave a pending
/// Timer for `flutter_test`'s leak check.
library;

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  // Moved by the test body to cross local midnight. 2026-01-05 is a Monday,
  // so 'Tomorrow' (the 6th) is unambiguously not also 'This week'.
  var currentTime = DateTime(2026, 1, 5, 9);

  testChoreApp(
    'at local midnight the list re-buckets and "Done today" empties, with '
    'nothing overdue',
    today: DateTime(2026, 1, 5, 9),
    clock: Clock(() => currentTime),
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final me = await database.select(database.members).getSingle();
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
      // Completed today: sits under 'Done today (1)' until midnight.
      final dishes = await service.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = await ChoreRepository(
        database,
      ).pendingOccurrenceOf(dishes.id);
      await service.completeOccurrence(pending!.id, completedBy: me.id);
      await tester.pumpAndSettle();

      // Section headers render uppercase (theme-v2.md §2/§4.1 item 2) via
      // the widget's own .toUpperCase(); chore titles are untouched. Same
      // idiom as list_grouping_test.dart.
      expect(find.text('Done today (1)'), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);

      // Midnight. Not one row in the database changes.
      currentTime = DateTime(2026, 1, 6, 0, 0, 1);
      ProviderScope.containerOf(
        tester.element(find.byType(ChoreApp)),
        listen: false,
      ).read(todayProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text('Done today (1)'), findsNothing);
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);

      const expectedOrder = ['TODAY', 'Vacuum'];
      final renderedTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .where(expectedOrder.contains)
          .toList();
      expect(renderedTexts, expectedOrder);
    },
  );

  // A second mutable clock, independent of the one above: each testChoreApp
  // body runs once, but these variables live at file scope, so the two
  // tests must not share one.
  var formTime = DateTime(2026, 1, 5, 9);

  testChoreApp(
    'a start date the user already picked never moves under them when the '
    'day rolls over with the chore form open',
    today: DateTime(2026, 1, 5, 9),
    clock: Clock(() => formTime),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      // The new-chore form defaults its start date to today, rendered by
      // StartDateField as DateFormat.yMMMd('en').
      expect(find.text('Jan 5, 2026'), findsOneWidget);

      // Midnight passes with the form still open.
      formTime = DateTime(2026, 1, 6, 0, 0, 1);
      ProviderScope.containerOf(
        tester.element(find.byType(ChoreApp)),
        listen: false,
      ).read(todayProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // The picker's RANGE reference moved (today - 1 year is now
      // 2025-01-06); the user's chosen VALUE did not. `_startDate` is read
      // once in initState precisely so this stays true.
      expect(find.text('Jan 5, 2026'), findsOneWidget);
      expect(find.text('Jan 6, 2026'), findsNothing);
      expect(
        find.bySemanticsIdentifier('chore_form.start_date'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
