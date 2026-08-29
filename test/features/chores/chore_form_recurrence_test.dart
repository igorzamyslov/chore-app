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

  /// Picks a repeat unit. The unit is a menu hole in the sentence now
  /// (G-2), not a segmented control, so this is two taps: open the chip,
  /// then choose. The three `chore_form.repeat.unit.<x>` ids survive
  /// unchanged inside it -- they are E2E API.
  Future<void> pickUnit(WidgetTester tester, String unit) async {
    await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.unit'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('chore_form.repeat.unit.$unit'),
    );
    await tester.pumpAndSettle();
  }

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
      await pickUnit(tester, 'day');
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
      await pickUnit(tester, 'month');
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
      // (default). The form now opens with the start date's own weekday
      // already selected -- G-2 removed the hidden "empty set means derive
      // from the start date" rule by making that derivation explicit -- so
      // today's Friday has to be deselected to get exactly {Tue, Thu}.
      // That also exercises the other half of the min-one rule: a day that
      // is NOT the last one selected can still be turned off.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.2'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.4'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.5'),
      );
      await tester.pumpAndSettle();
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
      await pickUnit(tester, 'month');
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

  // -------------------------------------------------------------------
  // G-2 (docs/plans/2026-08-18-repeat-form-sentence.md)
  // -------------------------------------------------------------------

  /// Picks a day from the sentence's day-of-month hole.
  Future<void> pickMonthlyDay(WidgetTester tester, String label) async {
    await tester.tap(
      find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'an explicitly picked monthly day persists to the saved recurrence',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Rent');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await pickUnit(tester, 'month');
      await pickMonthlyDay(tester, '20th');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Rent'))).getSingle();
      final recurrence = chore.recurrence!;
      expect(recurrence.unit, RecurrenceUnit.month);
      expect(recurrence.monthlyMode, MonthlyMode.dayOfMonth);
      // The whole point of G-2: the day is what the user picked, not what
      // the start date happened to be (the 24th).
      expect(recurrence.monthlyDayOfMonth, 20);

      handle.dispose();
    },
  );

  testChoreApp(
    'the "last day" sentinel persists as -1, never as 32',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Meter reading');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await pickUnit(tester, 'month');
      await pickMonthlyDay(tester, 'last day');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Meter reading'))).getSingle();
      expect(chore.recurrence!.monthlyDayOfMonth, -1);
      // The alignment contract: the start date sits on the last day of its
      // own month so a client predating the field stays as close as it can.
      expect(chore.startDate.day, 31);

      handle.dispose();
    },
  );

  // OPD-1 / Analysis §2a. The engine's derived branch is
  // min(startDate.day, daysInMonth) and the explicit branch is
  // min(D, daysInMonth), so keeping startDate.day == D makes a household
  // member on a client predating the field compute an identical series.
  // The move is forwards only, so the first occurrence never lands in the
  // past, and it happens in a field the user can see and override.
  testChoreApp(
    'picking a monthly day moves the start date onto that day, forwards',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await pickUnit(tester, 'month');

      expect(find.text('Jul 24, 2026'), findsOneWidget);

      // The 20th of July is already past, so the nearest 20th on or after
      // the current start date is in August -- never July 20, which would
      // put the first occurrence in the past.
      await pickMonthlyDay(tester, '20th');

      expect(find.text('Aug 20, 2026'), findsOneWidget);
      expect(find.text('Jul 24, 2026'), findsNothing);

      handle.dispose();
    },
  );

  // The other direction of the same invariant. The start date is editable
  // in this very form, so without this the user could pick the 20th and
  // then move the start date to the 5th, persisting D=20 against
  // startDate.day=5 -- reopening the divergence, and reopening it worse,
  // because the gap can then fall either way and the older client can be
  // LATE rather than early.
  testChoreApp(
    'moving the start date re-derives the monthly day, keeping them aligned',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Bins');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await pickUnit(tester, 'month');
      await pickMonthlyDay(tester, '20th');

      // Now move the start date to the 28th through the picker.
      await tester.tap(find.bySemanticsIdentifier('chore_form.start_date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('28'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Bins'))).getSingle();
      expect(chore.startDate.day, 28);
      expect(
        chore.recurrence!.monthlyDayOfMonth,
        28,
        reason: 'the picked start date must win and the day chip follow it',
      );

      handle.dispose();
    },
  );

  // OPD-2. An nth-weekday pattern is a position in the calendar, so
  // Recurrence.validated refuses it with a completion anchor. Rather than
  // offering a choice and silently reverting it, the anchor card is
  // ABSENT -- the same "does not apply, does not exist" rule the weekday
  // chips already follow -- with a line saying why.
  testChoreApp(
    'the completion anchor does not exist in monthly weekday mode',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await pickUnit(tester, 'month');

      expect(
        find.bySemanticsIdentifier('chore_form.repeat.anchor.completion'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.nth_weekday',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.repeat.anchor.completion'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.anchor.schedule'),
        findsOneWidget,
      );
      expect(
        find.text(
          'A weekday pattern is a position in the calendar, so there is '
          'nothing for a completion date to count from.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  // OPD-2's converse: already on the completion anchor, then switching the
  // monthly mode. The anchor still has to change; it must explain itself on
  // the same frame rather than reverting silently. Asserting the PERSISTED
  // rule, not merely that nothing threw -- a test that only checked for the
  // absence of a throw would pass against a form that saved nothing at all.
  testChoreApp(
    'switching to weekday mode from the completion anchor saves a valid rule '
    'and says why the anchor changed',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Deep clean');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await pickUnit(tester, 'month');
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.anchor.completion'),
      );
      await tester.pumpAndSettle();

      // The monthly mode row does not apply under a completion anchor
      // either -- nextAfterCompletion's month branch reads no monthly
      // field -- so get back to a schedule anchor to reach it.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.anchor.schedule'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.nth_weekday',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'A weekday pattern is a position in the calendar, so there is '
          'nothing for a completion date to count from.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Deep clean'))).getSingle();
      final recurrence = chore.recurrence!;
      expect(recurrence.monthlyMode, MonthlyMode.nthWeekday);
      expect(recurrence.anchor, RecurrenceAnchor.schedule);

      handle.dispose();
    },
  );

  testChoreApp(
    'the last selected weekday cannot be deselected',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Hoover');
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();

      // Exactly one day is selected on open: the start date's own weekday,
      // today being a Friday. Tapping it must be a no-op -- an empty set
      // would put the hidden start-date dependency straight back.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.5'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Hoover'))).getSingle();
      expect(chore.recurrence!.weekdays, {DateTime.friday});

      handle.dispose();
    },
  );

  // Analysis §9: "every 2 weeks on Tuesday and Friday" is two chores a
  // fortnight, not one alternating, and no wording of the sentence settles
  // that. Three real dates do. This is the same assertion
  // recurrence_sentence_test.dart makes on the formatter, made again at the
  // UI level so the form is proved to be feeding it the right values.
  testChoreApp(
    'the preview names the next three real dates',
    // A Monday, so the first active week is unambiguous.
    today: DateTime(2026, 8, 3, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.repeat.interval'), '2');
      await tester.pumpAndSettle();
      // Tuesday and Friday, and drop the seeded Monday.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.2'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.5'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('chore_form.repeat.preview'),
          matching: find.text(
            'Every 2 weeks on Tuesday, Friday. '
            'Next Tue, Aug 4, then Fri, Aug 7 and Tue, Aug 18.',
          ),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
