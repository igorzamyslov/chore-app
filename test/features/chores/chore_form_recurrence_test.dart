import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Finds the [TextField] wrapped by the semantic id [identifier].
Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

void main() {
  // A Friday, so the nth-weekday monthly label is unambiguous (the 4th
  // Friday of July 2026).
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'weekday chips only show for week unit; monthly mode only for month '
    'with a schedule anchor',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();

      // Default unit is week: weekday chips show, monthly mode doesn't.
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.day_of_month',
        ),
        findsNothing,
      );

      // Day unit: neither shows.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.day'),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.day_of_month',
        ),
        findsNothing,
      );

      // Month unit, schedule anchor (the default): monthly mode shows, not
      // weekday chips.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.month'),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.day_of_month',
        ),
        findsOneWidget,
      );

      // Month unit, completion anchor: monthly mode hides again.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.anchor.completion'),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.day_of_month',
        ),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'weekday selection and anchor persist to the saved recurrence',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Weekly chore');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      // Tuesday and Thursday, week unit (default), schedule anchor
      // (default).
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.2'),
      );
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.4'),
      );
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Weekly chore'))).getSingle();
      final recurrence = chore.recurrence!;
      expect(recurrence.unit, RecurrenceUnit.week);
      expect(recurrence.anchor, RecurrenceAnchor.schedule);
      expect(recurrence.weekdays, {DateTime.tuesday, DateTime.thursday});

      handle.dispose();
    },
  );

  testChoreApp(
    'nth-weekday monthly mode persists to the saved recurrence',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Monthly chore');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.month'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.nth_weekday',
        ),
      );
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Monthly chore'))).getSingle();
      final recurrence = chore.recurrence!;
      expect(recurrence.unit, RecurrenceUnit.month);
      expect(recurrence.monthlyMode, MonthlyMode.nthWeekday);
      // 2026-07-24 is the 4th Friday of July 2026.
      expect(recurrence.monthlyOrdinal, 4);
      expect(recurrence.monthlyWeekday, DateTime.friday);

      handle.dispose();
    },
  );
}
