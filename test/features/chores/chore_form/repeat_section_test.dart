import 'package:chore_app/app/theme.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/repeat_section.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget-level tests for `AnchorRow`, the chore form's recurrence-anchor
/// radio cards (spec `docs/specs/theme-v2.md` §4.4 item 4): both cards must
/// name the actual configured interval, never a generic example.
void main() {
  Future<void> pumpAnchorRow(
    WidgetTester tester, {
    required RecurrenceUnit unit,
    required Set<int> weekdays,
    required MonthlyMode monthlyMode,
    required PlainDate startDate,
    RecurrenceAnchor value = RecurrenceAnchor.schedule,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnchorRow(
            value: value,
            interval: 1,
            unit: unit,
            weekdays: weekdays,
            monthlyMode: monthlyMode,
            startDate: startDate,
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('day unit: the fixed-schedule card names "Every day"', (
    tester,
  ) async {
    await pumpAnchorRow(
      tester,
      unit: RecurrenceUnit.day,
      weekdays: const {},
      monthlyMode: MonthlyMode.dayOfMonth,
      startDate: PlainDate(2026, 7, 24),
    );

    expect(find.text('Every day'), findsOneWidget);
  });

  testWidgets(
    'week unit, an explicit weekday picked: the fixed-schedule card names '
    'it',
    (tester) async {
      // 2026-07-24 is a Friday -- picking Saturday must show Saturday, not
      // the start date's own weekday.
      await pumpAnchorRow(
        tester,
        unit: RecurrenceUnit.week,
        weekdays: {DateTime.saturday},
        monthlyMode: MonthlyMode.dayOfMonth,
        startDate: PlainDate(2026, 7, 24),
      );

      expect(find.text('Every week on Saturday'), findsOneWidget);
    },
  );

  testWidgets(
    "week unit, no weekday picked yet: derives the name from the start date's "
    'own weekday',
    (tester) async {
      await pumpAnchorRow(
        tester,
        unit: RecurrenceUnit.week,
        weekdays: const {},
        monthlyMode: MonthlyMode.dayOfMonth,
        startDate: PlainDate(2026, 7, 24), // a Friday
      );

      expect(find.text('Every week on Friday'), findsOneWidget);
    },
  );

  testWidgets(
    'month unit, day-of-month mode: the fixed-schedule card names the '
    'actual configured day',
    (tester) async {
      await pumpAnchorRow(
        tester,
        unit: RecurrenceUnit.month,
        weekdays: const {},
        monthlyMode: MonthlyMode.dayOfMonth,
        startDate: PlainDate(2026, 7, 15),
      );

      expect(find.text('Every month on the 15th'), findsOneWidget);
    },
  );

  testWidgets(
    'month unit, nth-weekday mode: the fixed-schedule card names the '
    'actual configured ordinal and weekday',
    (tester) async {
      // 2026-07-24 is the 4th Friday of July 2026.
      await pumpAnchorRow(
        tester,
        unit: RecurrenceUnit.month,
        weekdays: const {},
        monthlyMode: MonthlyMode.nthWeekday,
        startDate: PlainDate(2026, 7, 24),
      );

      expect(find.text('Every month on the 4th Friday'), findsOneWidget);
    },
  );

  testWidgets(
    'the after-last-completion card keeps naming the actual interval too',
    (tester) async {
      await pumpAnchorRow(
        tester,
        unit: RecurrenceUnit.day,
        weekdays: const {},
        monthlyMode: MonthlyMode.dayOfMonth,
        startDate: PlainDate(2026, 7, 24),
        value: RecurrenceAnchor.completion,
      );

      expect(find.text('1 day after last done'), findsOneWidget);
    },
  );
}
