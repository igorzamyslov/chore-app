import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  // 2026-07-22 is a Wednesday: exercises the today/+1/Sunday/Monday
  // boundaries from the middle of a week.
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'list grouping: fabricated occurrences land in the right sections',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      Future<void> seed(String title, PlainDate dueDate) {
        return service.createChore(
          householdId: householdId,
          title: title,
          startDate: dueDate,
          assignmentMode: AssignmentMode.anyone,
        );
      }

      // Boundaries: yesterday (overdue), today, tomorrow, the coming Sunday
      // (still "this week"), the following Monday (same month, "this
      // month"), and a date in August ("later").
      await seed('Overdue chore', PlainDate(2026, 7, 21));
      await seed('Today chore', PlainDate(2026, 7, 22));
      await seed('Tomorrow chore', PlainDate(2026, 7, 23));
      await seed('This week chore', PlainDate(2026, 7, 26));
      await seed('This month chore', PlainDate(2026, 7, 27));
      await seed('Later chore', PlainDate(2026, 8, 3));

      await tester.pumpAndSettle();

      // Tiles under Today/Tomorrow show NO due text (refined A1: the
      // header already says it), so each header string appears exactly
      // once. Other sections' tiles carry due text, but those strings
      // ('in 3 days', 'Mon, Aug 3', …) aren't in this filter list.
      const expectedOrder = [
        'Overdue',
        'Overdue chore',
        'Today',
        'Today chore',
        'Tomorrow',
        'Tomorrow chore',
        'This week',
        'This week chore',
        'This month',
        'This month chore',
        'Later',
        'Later chore',
      ];

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
}
