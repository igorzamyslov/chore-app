import 'dart:math';

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/recurrence/recurrence_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formats a list of occurrences as ISO strings for readable expectations.
List<String> _iso(Iterable<PlainDate> dates) =>
    dates.map((d) => d.toIso8601()).toList();

void main() {
  group('scheduleOccurrences - day unit', () {
    test('start 2026-01-01 interval 3', () {
      final rule = Recurrence.everyNDays(3);
      final start = PlainDate(2026, 1, 1);
      expect(_iso(scheduleOccurrences(rule, start).take(4)), [
        '2026-01-01',
        '2026-01-04',
        '2026-01-07',
        '2026-01-10',
      ]);
    });
  });

  group('scheduleOccurrences - week unit', () {
    test('{sat} interval 1 starting Wed 2026-07-22 begins 2026-07-25', () {
      final rule = Recurrence.weekly(weekdays: {DateTime.saturday});
      final start = PlainDate(2026, 7, 22);
      expect(_iso(scheduleOccurrences(rule, start).take(3)), [
        '2026-07-25',
        '2026-08-01',
        '2026-08-08',
      ]);
    });

    test('{mon,thu} interval 2 starting Mon 2026-07-20', () {
      final rule = Recurrence.weekly(
        interval: 2,
        weekdays: {DateTime.monday, DateTime.thursday},
      );
      final start = PlainDate(2026, 7, 20);
      expect(_iso(scheduleOccurrences(rule, start).take(4)), [
        '2026-07-20',
        '2026-07-23',
        '2026-08-03',
        '2026-08-06',
      ]);
    });

    test('{sun} starting Mon lands on the Sunday of the same ISO week', () {
      final rule = Recurrence.weekly(weekdays: {DateTime.sunday});
      final start = PlainDate(2026, 7, 20);
      expect(_iso(scheduleOccurrences(rule, start).take(1)), ['2026-07-26']);
    });

    test('empty weekdays derives the weekday from startDate', () {
      final rule = Recurrence.weekly(); // Wednesday start, no explicit weekdays
      final start = PlainDate(2026, 7, 22);
      expect(_iso(scheduleOccurrences(rule, start).take(3)), [
        '2026-07-22',
        '2026-07-29',
        '2026-08-05',
      ]);
    });
  });

  group('scheduleOccurrences - month unit dayOfMonth', () {
    test('start 2026-01-31 interval 1 clamps through the year', () {
      final rule = Recurrence.monthlyOnDay();
      final start = PlainDate(2026, 1, 31);
      expect(_iso(scheduleOccurrences(rule, start).take(4)), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
      ]);
    });

    test('crosses into leap year 2028 -> 2028-02-29', () {
      final rule = Recurrence.monthlyOnDay();
      final start = PlainDate(2026, 1, 31);
      // 25 months after January 2026 is February 2028.
      final occurrences = scheduleOccurrences(rule, start).take(26).toList();
      expect(occurrences.last.toIso8601(), '2028-02-29');
    });

    test('interval 2 skips months', () {
      final rule = Recurrence.monthlyOnDay(interval: 2);
      final start = PlainDate(2026, 1, 31);
      expect(_iso(scheduleOccurrences(rule, start).take(5)), [
        '2026-01-31',
        '2026-03-31',
        '2026-05-31',
        '2026-07-31',
        '2026-09-30',
      ]);
    });

    test('year rollover: start November, interval 3 -> February next year', () {
      final rule = Recurrence.monthlyOnDay(interval: 3);
      final start = PlainDate(2026, 11, 15);
      expect(_iso(scheduleOccurrences(rule, start).take(2)), [
        '2026-11-15',
        '2027-02-15',
      ]);
    });
  });

  group('scheduleOccurrences - month unit nthWeekday', () {
    test('first Saturday of the month, starting on a Saturday', () {
      // 2026-07-04 is itself a Saturday and thus the first Saturday of July,
      // so it is >= startDate and is included per the documented "filtered
      // to >= startDate" rule; the next two occurrences are the ones the
      // spec calls out explicitly.
      final rule = Recurrence.monthlyOnNthWeekday(1, DateTime.saturday);
      final start = PlainDate(2026, 7, 4);
      expect(_iso(scheduleOccurrences(rule, start).take(3)), [
        '2026-07-04',
        '2026-08-01',
        '2026-09-05',
      ]);
    });

    test('last Friday (ordinal -1) in an ordinary 4-Friday month', () {
      final rule = Recurrence.monthlyOnNthWeekday(-1, DateTime.friday);
      final start = PlainDate(2026, 2, 1);
      // February 2026 has exactly 4 Fridays: 6, 13, 20, 27.
      expect(_iso(scheduleOccurrences(rule, start).take(1)), ['2026-02-27']);
    });

    test('last Friday (ordinal -1) in a month where it is the 5th Friday', () {
      final rule = Recurrence.monthlyOnNthWeekday(-1, DateTime.friday);
      final start = PlainDate(2026, 1, 1);
      // January 2026 has 5 Fridays: 2, 9, 16, 23, 30. The last is the 5th.
      expect(_iso(scheduleOccurrences(rule, start).take(1)), ['2026-01-30']);
    });
  });

  group('nextScheduledOnOrAfter', () {
    test('day unit jumps to the next occurrence after the query date', () {
      final rule = Recurrence.everyNDays(3);
      final start = PlainDate(2026, 1, 1);
      expect(
        nextScheduledOnOrAfter(rule, start, PlainDate(2026, 1, 5)),
        PlainDate(2026, 1, 7),
      );
    });

    test('day unit returns the same date when it is already an occurrence', () {
      final rule = Recurrence.everyNDays(3);
      final start = PlainDate(2026, 1, 1);
      expect(
        nextScheduledOnOrAfter(rule, start, PlainDate(2026, 1, 7)),
        PlainDate(2026, 1, 7),
      );
    });

    test('week unit finds the next matching weekday', () {
      final rule = Recurrence.weekly(
        interval: 2,
        weekdays: {DateTime.monday, DateTime.thursday},
      );
      final start = PlainDate(2026, 7, 20);
      expect(
        nextScheduledOnOrAfter(rule, start, PlainDate(2026, 7, 24)),
        PlainDate(2026, 8, 3),
      );
    });

    test('week unit on an exact occurrence date returns that date', () {
      final rule = Recurrence.weekly(
        interval: 2,
        weekdays: {DateTime.monday, DateTime.thursday},
      );
      final start = PlainDate(2026, 7, 20);
      expect(
        nextScheduledOnOrAfter(rule, start, PlainDate(2026, 8, 6)),
        PlainDate(2026, 8, 6),
      );
    });

    test('month unit dayOfMonth skips into the next valid month', () {
      final rule = Recurrence.monthlyOnDay();
      final start = PlainDate(2026, 1, 31);
      // Query mid-February: Feb 28 (this month's occurrence) is already
      // past, so the answer must be March 31.
      expect(
        nextScheduledOnOrAfter(rule, start, PlainDate(2026, 3, 1)),
        PlainDate(2026, 3, 31),
      );
    });

    test(
      'month unit nthWeekday finds the occurrence within the query month',
      () {
        final rule = Recurrence.monthlyOnNthWeekday(1, DateTime.saturday);
        final start = PlainDate(2026, 1, 1);
        // First Saturday of August 2026 is 2026-08-01.
        expect(
          nextScheduledOnOrAfter(rule, start, PlainDate(2026, 7, 15)),
          PlainDate(2026, 8, 1),
        );
      },
    );

    test(
      'a query date on or before startDate returns the first occurrence',
      () {
        final rule = Recurrence.weekly(weekdays: {DateTime.saturday});
        final start = PlainDate(2026, 7, 22);
        expect(
          nextScheduledOnOrAfter(rule, start, PlainDate(2020, 1, 1)),
          PlainDate(2026, 7, 25),
        );
        expect(
          nextScheduledOnOrAfter(rule, start, start),
          PlainDate(2026, 7, 25),
        );
      },
    );
  });

  group('nextAfterCompletion', () {
    test('day unit: completedOn + interval days', () {
      final rule = Recurrence.everyNDays(
        4,
        anchor: RecurrenceAnchor.completion,
      );
      expect(
        nextAfterCompletion(rule, PlainDate(2026, 7, 1)),
        PlainDate(2026, 7, 5),
      );
      // Shifts relative to the actual completion date regardless of when
      // the chore was "supposed" to be done - completing early or late
      // both just add `interval` days from completedOn.
      expect(
        nextAfterCompletion(rule, PlainDate(2026, 7, 10)),
        PlainDate(2026, 7, 14),
      );
    });

    test('week unit, empty weekdays: completedOn + interval * 7 days', () {
      final rule = Recurrence.weekly(
        interval: 2,
        anchor: RecurrenceAnchor.completion,
      );
      expect(
        nextAfterCompletion(rule, PlainDate(2026, 7, 1)),
        PlainDate(2026, 7, 15),
      );
    });

    test('week unit, pinned weekdays: rolls forward to the nearest match', () {
      final rule = Recurrence.weekly(
        weekdays: {DateTime.saturday},
        anchor: RecurrenceAnchor.completion,
      );
      // Completed Tuesday 2026-07-21: candidate is Tue 2026-07-28, which
      // rolls forward to Sat 2026-08-01.
      expect(
        nextAfterCompletion(rule, PlainDate(2026, 7, 21)),
        PlainDate(2026, 8, 1),
      );
    });

    test(
      'week unit: candidate that already matches rolls forward by zero days',
      () {
        final rule = Recurrence.weekly(
          weekdays: {DateTime.tuesday},
          anchor: RecurrenceAnchor.completion,
        );
        // Completed on a Tuesday: candidate (+7 days) is also a Tuesday.
        expect(
          nextAfterCompletion(rule, PlainDate(2026, 7, 21)),
          PlainDate(2026, 7, 28),
        );
      },
    );

    test('month unit: completedOn.addMonths(interval), clamped', () {
      final rule = Recurrence.monthlyOnDay(anchor: RecurrenceAnchor.completion);
      expect(
        nextAfterCompletion(rule, PlainDate(2026, 1, 31)),
        PlainDate(2026, 2, 28),
      );
    });
  });

  group('firstDueDate', () {
    test('schedule anchor uses the first scheduled occurrence', () {
      final rule = Recurrence.weekly(weekdays: {DateTime.saturday});
      final start = PlainDate(2026, 7, 22);
      expect(firstDueDate(rule, start), PlainDate(2026, 7, 25));
    });

    test('completion anchor uses startDate itself', () {
      final rule = Recurrence.everyNDays(
        4,
        anchor: RecurrenceAnchor.completion,
      );
      final start = PlainDate(2026, 7, 1);
      expect(firstDueDate(rule, start), start);
    });
  });

  group('nextDueDateAfterClosing', () {
    test('schedule anchor: closed shortly after due -> next regular slot', () {
      final rule = Recurrence.weekly(weekdays: {DateTime.tuesday});
      final start = PlainDate(2026, 7, 21); // a Tuesday
      final closedDueDate = start;
      final closedOn = start.addDays(2); // the following Thursday
      final result = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: false,
      );
      expect(result, PlainDate(2026, 7, 28)); // next Tuesday
    });

    test('schedule anchor: closed 3 weeks late skips the missed slots', () {
      final rule = Recurrence.weekly(weekdays: {DateTime.tuesday});
      final start = PlainDate(2026, 7, 21); // a Tuesday
      final closedDueDate = start;
      final closedOn = start.addDays(21); // 3 weeks later, also a Tuesday
      final result = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: false,
      );
      expect(result.isAfter(closedOn), isTrue);
      expect(result, PlainDate(2026, 8, 18));
    });

    test('schedule anchor: result is identical for done and skipped '
        '(unaffected by the skipped flag)', () {
      final rule = Recurrence.weekly(weekdays: {DateTime.tuesday});
      final start = PlainDate(2026, 7, 21); // a Tuesday
      final closedDueDate = start;
      final closedOn = start.addDays(2); // the following Thursday
      final done = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: false,
      );
      final skipped = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: true,
      );
      expect(skipped, done);
      expect(skipped, PlainDate(2026, 7, 28));
    });

    test('completion anchor, done: uses closedOn, not closedDueDate', () {
      final rule = Recurrence.everyNDays(
        4,
        anchor: RecurrenceAnchor.completion,
      );
      final start = PlainDate(2026, 7, 1);
      final closedOn = PlainDate(2026, 7, 10);
      // closedDueDate is deliberately far from closedOn to prove it is
      // ignored for a completion-anchored DONE close.
      final result = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: PlainDate(2020, 1, 1),
        closedOn: closedOn,
        skipped: false,
      );
      expect(result, nextAfterCompletion(rule, closedOn));
      expect(result, PlainDate(2026, 7, 14));
    });

    test('completion anchor, done: completing a FUTURE occurrence early still '
        'anchors at closedOn (today), not the due date (field feedback B3 — '
        'the "watering early" case, deliberately unchanged)', () {
      final rule = Recurrence.everyNDays(
        3,
        anchor: RecurrenceAnchor.completion,
      );
      final start = PlainDate(2026, 7, 1);
      final closedOn = PlainDate(2026, 7, 10); // today
      final closedDueDate = PlainDate(2026, 7, 13); // due 3 days from now
      final result = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: false,
      );
      expect(result, nextAfterCompletion(rule, closedOn));
      expect(result, PlainDate(2026, 7, 13));
    });

    test('completion anchor, skipped: skipping a FUTURE occurrence anchors at '
        'its OWN due date, not closedOn (field feedback B3 — the "skip did '
        'nothing" bug this fixes: closedDueDate + interval, not closedOn + '
        'interval)', () {
      final rule = Recurrence.everyNDays(
        3,
        anchor: RecurrenceAnchor.completion,
      );
      final start = PlainDate(2026, 7, 1);
      final closedOn = PlainDate(2026, 7, 10); // today
      final closedDueDate = PlainDate(2026, 7, 13); // due 3 days from now
      final result = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: true,
      );
      expect(result, nextAfterCompletion(rule, closedDueDate));
      expect(result, PlainDate(2026, 7, 16)); // due date + interval
    });

    test('completion anchor, skipped: an overdue/today skip is unchanged -- '
        'closedOn is already the max, so it anchors at closedOn + interval, '
        'same as a done close would', () {
      final rule = Recurrence.everyNDays(
        3,
        anchor: RecurrenceAnchor.completion,
      );
      final start = PlainDate(2026, 7, 1);
      final closedOn = PlainDate(2026, 7, 10); // today
      final closedDueDate = PlainDate(2026, 7, 5); // overdue
      final result = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedDueDate,
        closedOn: closedOn,
        skipped: true,
      );
      expect(result, nextAfterCompletion(rule, closedOn));
      expect(result, PlainDate(2026, 7, 13)); // closedOn + interval

      // A today-due skip lands at the same place too (closedOn ==
      // closedDueDate, so max() picks either).
      final todayResult = nextDueDateAfterClosing(
        rule: rule,
        startDate: start,
        closedDueDate: closedOn,
        closedOn: closedOn,
        skipped: true,
      );
      expect(todayResult, PlainDate(2026, 7, 13));
    });
  });

  group('performance sanity', () {
    test('nextScheduledOnOrAfter stays fast 50 years past startDate', () {
      final start = PlainDate(2026, 1, 1);
      final farDate = start.addDays(365 * 50 + 20);
      final rules = [
        Recurrence.everyNDays(3),
        Recurrence.weekly(
          interval: 2,
          weekdays: {DateTime.monday, DateTime.thursday},
        ),
        Recurrence.monthlyOnDay(),
        Recurrence.monthlyOnNthWeekday(-1, DateTime.friday),
      ];

      final stopwatch = Stopwatch()..start();
      for (final rule in rules) {
        final result = nextScheduledOnOrAfter(rule, start, farDate);
        expect(result.isOnOrAfter(farDate), isTrue);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('seeded invariant tests (Random(42), >=500 iterations)', () {
    const iterations = 500;

    PlainDate randomDate(Random random) {
      final year = 2000 + random.nextInt(40);
      final month = 1 + random.nextInt(12);
      final day = 1 + random.nextInt(PlainDate.daysInMonth(year, month));
      return PlainDate(year, month, day);
    }

    Set<int> randomWeekdaySet(Random random) {
      return {
        for (var i = 0; i < 1 + random.nextInt(3); i++) 1 + random.nextInt(7),
      };
    }

    Recurrence randomScheduleRule(Random random) {
      final unit = RecurrenceUnit.values[random.nextInt(3)];
      final interval = 1 + random.nextInt(5);
      switch (unit) {
        case RecurrenceUnit.day:
          return Recurrence.everyNDays(interval);
        case RecurrenceUnit.week:
          final weekdays = random.nextBool()
              ? const <int>{}
              : randomWeekdaySet(random);
          return Recurrence.weekly(interval: interval, weekdays: weekdays);
        case RecurrenceUnit.month:
          if (random.nextBool()) {
            return Recurrence.monthlyOnDay(interval: interval);
          }
          const ordinals = [1, 2, 3, 4, -1];
          return Recurrence.monthlyOnNthWeekday(
            ordinals[random.nextInt(ordinals.length)],
            1 + random.nextInt(7),
            interval: interval,
          );
      }
    }

    test(
      '(a) every weekly occurrence weekday is in the effective weekday set',
      () {
        final random = Random(42);
        for (var i = 0; i < iterations; i++) {
          final start = randomDate(random);
          final weekdays = random.nextBool()
              ? const <int>{}
              : randomWeekdaySet(random);
          final rule = Recurrence.weekly(
            interval: 1 + random.nextInt(4),
            weekdays: weekdays,
          );
          final effective = rule.weekdays.isNotEmpty
              ? rule.weekdays
              : {start.weekday};
          for (final occ in scheduleOccurrences(rule, start).take(20)) {
            expect(effective.contains(occ.weekday), isTrue);
          }
        }
      },
    );

    test(
      '(b) scheduleOccurrences is strictly increasing and all >= startDate',
      () {
        final random = Random(42);
        for (var i = 0; i < iterations; i++) {
          final start = randomDate(random);
          final rule = randomScheduleRule(random);
          PlainDate? previous;
          for (final occ in scheduleOccurrences(rule, start).take(15)) {
            expect(occ.isOnOrAfter(start), isTrue);
            if (previous != null) {
              expect(occ.isAfter(previous), isTrue);
            }
            previous = occ;
          }
        }
      },
    );

    test(
      '(c) nextScheduledOnOrAfter(d) >= d and is an element of the series',
      () {
        final random = Random(42);
        for (var i = 0; i < iterations; i++) {
          final start = randomDate(random);
          final rule = randomScheduleRule(random);
          final query = start.addDays(random.nextInt(400) - 50);
          final result = nextScheduledOnOrAfter(rule, start, query);
          expect(result.isOnOrAfter(query), isTrue);
          expect(scheduleOccurrences(rule, start).take(600), contains(result));
        }
      },
    );

    test('(d) nextDueDateAfterClosing > max(closedDueDate, closedOn), '
        'schedule anchor -- holds regardless of the skipped flag', () {
      final random = Random(42);
      for (var i = 0; i < iterations; i++) {
        final start = randomDate(random);
        final rule = randomScheduleRule(random);
        final closedDueDate = start.addDays(random.nextInt(200));
        final closedOn = closedDueDate.addDays(random.nextInt(60) - 20);
        final skipped = random.nextBool();
        final result = nextDueDateAfterClosing(
          rule: rule,
          startDate: start,
          closedDueDate: closedDueDate,
          closedOn: closedOn,
          skipped: skipped,
        );
        final threshold = closedDueDate.isAfter(closedOn)
            ? closedDueDate
            : closedOn;
        expect(result.isAfter(threshold), isTrue);
      }
    });

    test('(e) day-unit occurrences satisfy (occ - start) % interval == 0', () {
      final random = Random(42);
      for (var i = 0; i < iterations; i++) {
        final start = randomDate(random);
        final interval = 1 + random.nextInt(10);
        final rule = Recurrence.everyNDays(interval);
        for (final occ in scheduleOccurrences(rule, start).take(10)) {
          expect(start.daysUntil(occ) % interval, 0);
        }
      }
    });
  });

  group('latestScheduledOnOrBefore', () {
    test('daily rule returns the newest slot at or before notAfter', () {
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.everyNDays(1),
        startDate: PlainDate(2026, 1, 5),
        afterDueDate: PlainDate(2026, 1, 5),
        notAfter: PlainDate(2026, 1, 8),
      );
      expect(slot, PlainDate(2026, 1, 8));
    });

    test('weekly rule skips the days between two slots', () {
      // 2026-01-05 is a Monday; 2026-01-15 is a Thursday.
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.weekly(weekdays: const {DateTime.monday}),
        startDate: PlainDate(2026, 1, 5),
        afterDueDate: PlainDate(2026, 1, 5),
        notAfter: PlainDate(2026, 1, 15),
      );
      expect(slot, PlainDate(2026, 1, 12));
    });

    test('returns null when the next slot is still ahead of notAfter', () {
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.everyNDays(3),
        startDate: PlainDate(2026, 1, 5),
        afterDueDate: PlainDate(2026, 1, 5),
        notAfter: PlainDate(2026, 1, 7),
      );
      expect(slot, isNull);
    });

    test('never returns a slot at or before afterDueDate', () {
      final slot = latestScheduledOnOrBefore(
        rule: Recurrence.everyNDays(1),
        startDate: PlainDate(2026, 1, 1),
        afterDueDate: PlainDate(2026, 1, 10),
        notAfter: PlainDate(2026, 1, 10),
      );
      expect(slot, isNull);
    });
  });
}
