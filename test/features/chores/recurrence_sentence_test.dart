// Pure unit tests for `recurrenceSentence`, the app's single formatter for
// recurrence prose (G-2, `docs/plans/2026-08-18-repeat-form-sentence.md`
// Task 1). Loads AppLocalizations directly through its generated delegate —
// no widget pump needed — following `due_text_test.dart`'s pattern.
//
// Task 1 is an EXTRACTION with zero behaviour change: every string asserted
// below is the string `AnchorRow._subtitle`/`_scheduleSubtitle` produced
// before the move, and `test/features/chores/chore_form/repeat_section_test.dart`
// asserts the same strings through the widget. If the two ever disagree,
// the extraction changed behaviour and is wrong.
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/recurrence_sentence.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations de;

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
    en = await AppLocalizations.delegate.load(const Locale('en'));
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  // 2026-07-24 is a Friday, and the 4th Friday of July 2026.
  final friday = PlainDate(2026, 7, 24);
  // 2026-07-31 is the 5th (i.e. last) Friday of July 2026.
  final lastFriday = PlainDate(2026, 7, 31);

  String sentence(
    AppLocalizations l10n,
    String localeName, {
    int interval = 1,
    RecurrenceUnit unit = RecurrenceUnit.day,
    RecurrenceAnchor anchor = RecurrenceAnchor.schedule,
    Set<int> weekdays = const {},
    MonthlyMode monthlyMode = MonthlyMode.dayOfMonth,
    PlainDate? startDate,
  }) {
    return recurrenceSentence(
      l10n,
      localeName,
      interval: interval,
      unit: unit,
      anchor: anchor,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      startDate: startDate ?? friday,
    );
  }

  group('schedule anchor, day unit', () {
    test('interval 1 reads "Every day"', () {
      expect(sentence(en, 'en'), 'Every day');
    });

    test('interval 3 pluralizes', () {
      expect(sentence(en, 'en', interval: 3), 'Every 3 days');
    });

    test('de', () {
      expect(sentence(de, 'de'), 'Jeden Tag');
      expect(sentence(de, 'de', interval: 3), 'Alle 3 Tage');
    });
  });

  group('schedule anchor, week unit', () {
    test('one explicitly picked weekday names it, not the start date', () {
      expect(
        sentence(
          en,
          'en',
          unit: RecurrenceUnit.week,
          weekdays: {DateTime.saturday},
        ),
        'Every week on Saturday',
      );
    });

    test('several weekdays are comma-joined in ascending ISO order', () {
      expect(
        sentence(
          en,
          'en',
          interval: 2,
          unit: RecurrenceUnit.week,
          weekdays: {DateTime.friday, DateTime.tuesday},
        ),
        'Every 2 weeks on Tuesday, Friday',
      );
    });

    test('an empty set falls back to the start date weekday', () {
      expect(
        sentence(en, 'en', unit: RecurrenceUnit.week),
        'Every week on Friday',
      );
    });

    test('de', () {
      expect(
        sentence(
          de,
          'de',
          unit: RecurrenceUnit.week,
          weekdays: {DateTime.saturday},
        ),
        'Jede Woche am Samstag',
      );
      expect(
        sentence(
          de,
          'de',
          interval: 2,
          unit: RecurrenceUnit.week,
          weekdays: {DateTime.friday, DateTime.tuesday},
        ),
        'Alle 2 Wochen am Dienstag, Freitag',
      );
    });
  });

  group('schedule anchor, month unit', () {
    test('day-of-month names the start date day as an ordinal', () {
      expect(
        sentence(
          en,
          'en',
          unit: RecurrenceUnit.month,
          startDate: PlainDate(2026, 7, 15),
        ),
        'Every month on the 15th',
      );
    });

    test('nth-weekday names the ordinal and weekday', () {
      expect(
        sentence(
          en,
          'en',
          unit: RecurrenceUnit.month,
          monthlyMode: MonthlyMode.nthWeekday,
        ),
        'Every month on the 4th Friday',
      );
    });

    test('the 5th occurrence of a weekday reads "last"', () {
      expect(
        sentence(
          en,
          'en',
          unit: RecurrenceUnit.month,
          monthlyMode: MonthlyMode.nthWeekday,
          startDate: lastFriday,
        ),
        'Every month on the last Friday',
      );
    });

    test('de', () {
      expect(
        sentence(
          de,
          'de',
          unit: RecurrenceUnit.month,
          startDate: PlainDate(2026, 7, 15),
        ),
        'Jeden Monat am 15.',
      );
      expect(
        sentence(
          de,
          'de',
          unit: RecurrenceUnit.month,
          monthlyMode: MonthlyMode.nthWeekday,
        ),
        'Jeden Monat am 4. Freitag',
      );
      expect(
        sentence(
          de,
          'de',
          unit: RecurrenceUnit.month,
          monthlyMode: MonthlyMode.nthWeekday,
          startDate: lastFriday,
        ),
        'Jeden Monat am letzten Freitag',
      );
    });
  });

  group('completion anchor', () {
    test('names the interval, per unit, and ignores the pattern', () {
      expect(
        sentence(
          en,
          'en',
          interval: 3,
          anchor: RecurrenceAnchor.completion,
        ),
        '3 days after last done',
      );
      expect(
        sentence(
          en,
          'en',
          unit: RecurrenceUnit.week,
          weekdays: {DateTime.saturday},
          anchor: RecurrenceAnchor.completion,
        ),
        '1 week after last done',
      );
      expect(
        sentence(
          en,
          'en',
          interval: 2,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.completion,
        ),
        '2 months after last done',
      );
    });

    test('de', () {
      expect(
        sentence(de, 'de', interval: 3, anchor: RecurrenceAnchor.completion),
        '3 Tage nach der letzten Erledigung',
      );
      expect(
        sentence(
          de,
          'de',
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.completion,
        ),
        '1 Monat nach der letzten Erledigung',
      );
    });
  });

  // ---------------------------------------------------------------------
  // Task 4 -- the explicit monthly holes, and the preview line.
  // ---------------------------------------------------------------------

  String preview(
    AppLocalizations l10n,
    String localeName, {
    required PlainDate startDate,
    required PlainDate today,
    int interval = 1,
    RecurrenceUnit unit = RecurrenceUnit.day,
    RecurrenceAnchor anchor = RecurrenceAnchor.schedule,
    Set<int> weekdays = const {},
    MonthlyMode monthlyMode = MonthlyMode.dayOfMonth,
    int? monthlyDayOfMonth,
    int? monthlyOrdinal,
    int? monthlyWeekday,
  }) {
    return recurrencePreview(
      l10n,
      localeName,
      interval: interval,
      unit: unit,
      anchor: anchor,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      monthlyDayOfMonth: monthlyDayOfMonth,
      monthlyOrdinal: monthlyOrdinal,
      monthlyWeekday: monthlyWeekday,
      startDate: startDate,
      today: today,
    );
  }

  group('recurrenceSentence renders the explicit monthly holes', () {
    test('an explicit day of month wins over the start date day', () {
      expect(
        recurrenceSentence(
          en,
          'en',
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          weekdays: const {},
          monthlyMode: MonthlyMode.dayOfMonth,
          monthlyDayOfMonth: 20,
          startDate: PlainDate(2026, 7, 15),
        ),
        'Every month on the 20th',
      );
    });

    test('the -1 sentinel reads "last day", not an ordinal', () {
      expect(
        recurrenceSentence(
          en,
          'en',
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          weekdays: const {},
          monthlyMode: MonthlyMode.dayOfMonth,
          monthlyDayOfMonth: -1,
          startDate: PlainDate(2026, 7, 15),
        ),
        'Every month on the last day',
      );
      expect(
        recurrenceSentence(
          de,
          'de',
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          weekdays: const {},
          monthlyMode: MonthlyMode.dayOfMonth,
          monthlyDayOfMonth: -1,
          startDate: PlainDate(2026, 7, 15),
        ),
        'Jeden Monat am letzten Tag',
      );
    });

    test('an explicit ordinal + weekday wins over the start date', () {
      // The start date is a Friday and the 4th of its month; the rule says
      // the 2nd Tuesday, and the rule is what must be rendered.
      expect(
        recurrenceSentence(
          en,
          'en',
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          weekdays: const {},
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: 2,
          monthlyWeekday: DateTime.tuesday,
          startDate: friday,
        ),
        'Every month on the 2nd Tuesday',
      );
    });

    test('an explicit ordinal of -1 still reads "last"', () {
      expect(
        recurrenceSentence(
          en,
          'en',
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          weekdays: const {},
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: -1,
          monthlyWeekday: DateTime.tuesday,
          startDate: friday,
        ),
        'Every month on the last Tuesday',
      );
    });
  });

  group('recurrencePreview, schedule anchor', () {
    // The whole reason the preview exists (Analysis 9): "every 2 weeks on
    // Tue and Fri" is TWO chores a fortnight, not one alternating. Nothing
    // in the sentence says which reading is meant; three real dates do.
    test(
      'multi-weekday: two dates in the active week, then a skipped week',
      () {
        final monday = PlainDate(2026, 8, 3);
        expect(
          preview(
            en,
            'en',
            interval: 2,
            unit: RecurrenceUnit.week,
            weekdays: {DateTime.tuesday, DateTime.friday},
            startDate: monday,
            today: monday,
          ),
          'Every 2 weeks on Tuesday, Friday. '
          'Next Tue, Aug 4, then Fri, Aug 7 and Tue, Aug 18.',
        );
      },
    );

    test('multi-weekday, de', () {
      final monday = PlainDate(2026, 8, 3);
      expect(
        preview(
          de,
          'de',
          interval: 2,
          unit: RecurrenceUnit.week,
          weekdays: {DateTime.tuesday, DateTime.friday},
          startDate: monday,
          today: monday,
        ),
        'Alle 2 Wochen am Dienstag, Freitag '
        '— als Nächstes Di., 4. Aug., dann Fr., 7. Aug. und Di., 18. Aug.',
      );
    });

    // The clamp is real and the preview shows it happening (g2notes): a
    // 31st-of-the-month rule simply lands on Feb 28.
    test('day 31 shows the February clamp rather than hiding it', () {
      expect(
        preview(
          en,
          'en',
          unit: RecurrenceUnit.month,
          monthlyDayOfMonth: 31,
          startDate: PlainDate(2026, 1, 31),
          today: PlainDate(2026, 1, 31),
        ),
        'Every month on the 31st. '
        'Next Sat, Jan 31, then Sat, Feb 28 and Tue, Mar 31.',
      );
    });

    test('day 31 clamp, de', () {
      expect(
        preview(
          de,
          'de',
          unit: RecurrenceUnit.month,
          monthlyDayOfMonth: 31,
          startDate: PlainDate(2026, 1, 31),
          today: PlainDate(2026, 1, 31),
        ),
        'Jeden Monat am 31. '
        '— als Nächstes Sa., 31. Jan., dann Sa., 28. Feb. und Di., 31. März',
      );
    });

    test('only dates on or after today are named', () {
      // The series began in January; today is March, so the preview must
      // start at the March slot, not replay history.
      expect(
        preview(
          en,
          'en',
          unit: RecurrenceUnit.month,
          monthlyDayOfMonth: 31,
          startDate: PlainDate(2026, 1, 31),
          today: PlainDate(2026, 3, 1),
        ),
        'Every month on the 31st. '
        'Next Tue, Mar 31, then Thu, Apr 30 and Sun, May 31.',
      );
    });
  });

  group('recurrencePreview, completion anchor', () {
    // No real dates exist -- the series depends on when the user ticks --
    // so the preview is prose, matching the prototype's `anchor === done`
    // branch.
    test('week unit with more than one weekday explains the roll-forward', () {
      expect(
        preview(
          en,
          'en',
          unit: RecurrenceUnit.week,
          anchor: RecurrenceAnchor.completion,
          weekdays: {DateTime.tuesday, DateTime.friday},
          startDate: friday,
          today: friday,
        ),
        '1 week after last done, '
        'rolled forward to the next Tuesday, Friday.',
      );
    });

    test('every other case says the next date depends on the day', () {
      expect(
        preview(
          en,
          'en',
          interval: 3,
          anchor: RecurrenceAnchor.completion,
          startDate: friday,
          today: friday,
        ),
        '3 days after last done '
        '— the next due date depends on the day you do it.',
      );
    });

    test('a single-weekday week rule is not a roll-forward case', () {
      // With one pinned weekday the roll-forward is a no-op, so the
      // generic wording is the honest one.
      expect(
        preview(
          en,
          'en',
          unit: RecurrenceUnit.week,
          anchor: RecurrenceAnchor.completion,
          weekdays: {DateTime.tuesday},
          startDate: friday,
          today: friday,
        ),
        '1 week after last done '
        '— the next due date depends on the day you do it.',
      );
    });

    test('de', () {
      expect(
        preview(
          de,
          'de',
          interval: 3,
          anchor: RecurrenceAnchor.completion,
          startDate: friday,
          today: friday,
        ),
        '3 Tage nach der letzten Erledigung '
        '— das nächste Fälligkeitsdatum hängt vom Tag ab, '
        'an dem du sie erledigst.',
      );
    });
  });
}
