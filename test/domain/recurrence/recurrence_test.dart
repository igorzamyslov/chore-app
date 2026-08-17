import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unnamed constructor is permissive', () {
    test('does not validate field combinations', () {
      // interval < 1, weekdays on a day-unit rule, nthWeekday fields set
      // without nthWeekday mode: all invalid combinations that `validated`
      // would reject, yet the plain constructor accepts them.
      const rule = Recurrence(
        interval: 0,
        unit: RecurrenceUnit.day,
        anchor: RecurrenceAnchor.schedule,
        weekdays: {9},
        monthlyOrdinal: 99,
        monthlyWeekday: 99,
      );
      expect(rule.interval, 0);
      expect(rule.weekdays, {9});
    });
  });

  group('Recurrence.validated rejects each invalid combination', () {
    test('interval < 1', () {
      expect(
        () => Recurrence.validated(
          interval: 0,
          unit: RecurrenceUnit.day,
          anchor: RecurrenceAnchor.schedule,
        ),
        throwsArgumentError,
      );
    });

    test('weekdays non-empty when unit != week', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.day,
          anchor: RecurrenceAnchor.schedule,
          weekdays: {1},
        ),
        throwsArgumentError,
      );
    });

    test('weekdays value outside 1..7', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.week,
          anchor: RecurrenceAnchor.schedule,
          weekdays: {8},
        ),
        throwsArgumentError,
      );
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.week,
          anchor: RecurrenceAnchor.schedule,
          weekdays: {0},
        ),
        throwsArgumentError,
      );
    });

    test('monthlyOrdinal set when monthlyMode != nthWeekday', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyOrdinal: 1,
        ),
        throwsArgumentError,
      );
    });

    test('monthlyWeekday set when monthlyMode != nthWeekday', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyWeekday: 1,
        ),
        throwsArgumentError,
      );
    });

    test('nthWeekday mode with monthlyOrdinal not in {1,2,3,4,-1}', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: 5,
          monthlyWeekday: 1,
        ),
        throwsArgumentError,
      );
    });

    test('nthWeekday mode with monthlyOrdinal null', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyWeekday: 1,
        ),
        throwsArgumentError,
      );
    });

    test('nthWeekday mode with monthlyWeekday not in 1..7', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: 1,
          monthlyWeekday: 8,
        ),
        throwsArgumentError,
      );
    });

    test('nthWeekday mode with monthlyWeekday null', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: 1,
        ),
        throwsArgumentError,
      );
    });

    test('nthWeekday mode when unit != month', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.week,
          anchor: RecurrenceAnchor.schedule,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: 1,
          monthlyWeekday: 1,
        ),
        throwsArgumentError,
      );
    });

    test('nthWeekday mode when anchor == completion', () {
      expect(
        () => Recurrence.validated(
          interval: 1,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.completion,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: 1,
          monthlyWeekday: 1,
        ),
        throwsArgumentError,
      );
    });

    test('a fully valid combination does not throw', () {
      expect(
        () => Recurrence.validated(
          interval: 2,
          unit: RecurrenceUnit.month,
          anchor: RecurrenceAnchor.schedule,
          monthlyMode: MonthlyMode.nthWeekday,
          monthlyOrdinal: -1,
          monthlyWeekday: 5,
        ),
        returnsNormally,
      );
    });
  });

  group('convenience factories', () {
    test('everyNDays builds a day-unit rule', () {
      final rule = Recurrence.everyNDays(3);
      expect(rule.unit, RecurrenceUnit.day);
      expect(rule.interval, 3);
      expect(rule.anchor, RecurrenceAnchor.schedule);
    });

    test('everyNDays honours a completion anchor', () {
      final rule = Recurrence.everyNDays(
        4,
        anchor: RecurrenceAnchor.completion,
      );
      expect(rule.anchor, RecurrenceAnchor.completion);
    });

    test('weekly builds a week-unit rule with the given weekdays', () {
      final rule = Recurrence.weekly(interval: 2, weekdays: {1, 4});
      expect(rule.unit, RecurrenceUnit.week);
      expect(rule.interval, 2);
      expect(rule.weekdays, {1, 4});
    });

    test('weekly defaults to an empty weekday set', () {
      final rule = Recurrence.weekly();
      expect(rule.weekdays, isEmpty);
    });

    test('monthlyOnDay builds a dayOfMonth month-unit rule', () {
      final rule = Recurrence.monthlyOnDay(interval: 2);
      expect(rule.unit, RecurrenceUnit.month);
      expect(rule.monthlyMode, MonthlyMode.dayOfMonth);
      expect(rule.interval, 2);
    });

    test('monthlyOnNthWeekday builds a schedule-anchored nthWeekday rule', () {
      final rule = Recurrence.monthlyOnNthWeekday(-1, 5);
      expect(rule.unit, RecurrenceUnit.month);
      expect(rule.monthlyMode, MonthlyMode.nthWeekday);
      expect(rule.monthlyOrdinal, -1);
      expect(rule.monthlyWeekday, 5);
      expect(rule.anchor, RecurrenceAnchor.schedule);
    });

    test('factories route through validated and reject bad input', () {
      expect(() => Recurrence.everyNDays(0), throwsArgumentError);
      expect(() => Recurrence.weekly(weekdays: {8}), throwsArgumentError);
    });
  });

  group('fromJson error handling', () {
    Map<String, Object?> validJson() => Recurrence.everyNDays(3).toJson();

    test('throws FormatException for a missing/wrong-typed interval', () {
      final json = validJson()..['interval'] = 'three';
      expect(() => Recurrence.fromJson(json), throwsFormatException);
    });

    test('throws FormatException for an unknown unit value', () {
      final json = validJson()..['unit'] = 'fortnight';
      expect(() => Recurrence.fromJson(json), throwsFormatException);
    });

    test('throws FormatException for an unknown anchor value', () {
      final json = validJson()..['anchor'] = 'whenever';
      expect(() => Recurrence.fromJson(json), throwsFormatException);
    });

    test('throws FormatException for an unknown monthly_mode value', () {
      final json = validJson()..['monthly_mode'] = 'sometimeInTheMonth';
      expect(() => Recurrence.fromJson(json), throwsFormatException);
    });

    test('throws FormatException for a non-list weekdays field', () {
      final json = validJson()..['weekdays'] = 'monday';
      expect(() => Recurrence.fromJson(json), throwsFormatException);
    });

    test('throws FormatException for non-int weekday entries', () {
      final json = validJson()..['weekdays'] = <Object?>['monday'];
      expect(() => Recurrence.fromJson(json), throwsFormatException);
    });

    test(
      'routes bad field combinations through validated as ArgumentError',
      () {
        final json = validJson()..['weekdays'] = [1];
        // day-unit rule with non-empty weekdays: well-typed, but an invalid
        // combination, so this must surface as ArgumentError, not
        // FormatException.
        expect(() => Recurrence.fromJson(json), throwsArgumentError);
      },
    );
  });

  group('JSON round trip', () {
    final representativeRules = <Recurrence>[
      Recurrence.everyNDays(3),
      Recurrence.everyNDays(5, anchor: RecurrenceAnchor.completion),
      Recurrence.weekly(),
      Recurrence.weekly(interval: 2, weekdays: {1, 3, 5}),
      Recurrence.weekly(weekdays: {6}, anchor: RecurrenceAnchor.completion),
      Recurrence.monthlyOnDay(),
      Recurrence.monthlyOnDay(interval: 3, anchor: RecurrenceAnchor.completion),
      Recurrence.monthlyOnNthWeekday(1, 6),
      Recurrence.monthlyOnNthWeekday(-1, 5, interval: 2),
    ];

    for (final rule in representativeRules) {
      test('round-trips ${rule.toJson()}', () {
        final decoded = Recurrence.fromJson(rule.toJson());
        expect(decoded.toJson(), equals(rule.toJson()));
      });
    }

    test('uses the documented snake_case keys', () {
      final json = Recurrence.monthlyOnNthWeekday(-1, 5, interval: 2).toJson();
      expect(json.keys, {
        'interval',
        'unit',
        'anchor',
        'weekdays',
        'monthly_mode',
        'monthly_ordinal',
        'monthly_weekday',
      });
    });

    test('serializes enums as their name', () {
      final json = Recurrence.everyNDays(3).toJson();
      expect(json['unit'], 'day');
      expect(json['anchor'], 'schedule');
    });
  });

  group('equality (backlog E-4)', () {
    test('two rules built with identical fields are equal', () {
      final a = Recurrence.everyNDays(3);
      final b = Recurrence.everyNDays(3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('weekdays equality is order-independent', () {
      final a = Recurrence.weekly(weekdays: {1, 3, 5});
      final b = Recurrence.weekly(weekdays: {5, 3, 1});
      expect(a, b);
      expect(
        a.hashCode,
        b.hashCode,
        reason:
            'a Set is not order-stable, so hashCode must fold the weekdays '
            'order-independently or it breaks the equal-objects-hash-equally '
            'contract this equality now promises',
      );
    });

    test('differing interval makes rules unequal', () {
      expect(Recurrence.everyNDays(3), isNot(Recurrence.everyNDays(4)));
    });

    test('differing unit makes rules unequal', () {
      expect(Recurrence.everyNDays(1), isNot(Recurrence.weekly()));
    });

    test('differing anchor makes rules unequal', () {
      expect(
        Recurrence.everyNDays(3),
        isNot(Recurrence.everyNDays(3, anchor: RecurrenceAnchor.completion)),
      );
    });

    test('differing weekdays makes rules unequal', () {
      expect(
        Recurrence.weekly(weekdays: {1, 3}),
        isNot(Recurrence.weekly(weekdays: {1, 4})),
      );
      expect(
        Recurrence.weekly(weekdays: {1, 3}),
        isNot(Recurrence.weekly(weekdays: {1})),
      );
    });

    test('differing monthlyMode makes rules unequal', () {
      expect(
        Recurrence.monthlyOnDay(),
        isNot(Recurrence.monthlyOnNthWeekday(1, 6)),
      );
    });

    test('differing monthly ordinal/weekday makes rules unequal', () {
      expect(
        Recurrence.monthlyOnNthWeekday(1, 6),
        isNot(Recurrence.monthlyOnNthWeekday(2, 6)),
      );
      expect(
        Recurrence.monthlyOnNthWeekday(1, 6),
        isNot(Recurrence.monthlyOnNthWeekday(1, 7)),
      );
    });

    test('is not equal to an unrelated object', () {
      // Comparing against a deliberately unrelated type is the point of
      // this test: the `other is Recurrence` guard must reject it rather
      // than throw.
      // ignore: unrelated_type_equality_checks
      expect(Recurrence.everyNDays(3) == 'not a recurrence', isFalse);
    });

    test('a rule round-tripped through JSON equals the original', () {
      // The reason E-4 exists at all: this is the comparison every caller
      // reaches for, and identity equality made it silently false.
      final rule = Recurrence.weekly(interval: 2, weekdays: {5, 1, 3});
      expect(Recurrence.fromJson(rule.toJson()), rule);
    });

    test('equal rules collapse in a Set', () {
      final rules = {
        Recurrence.weekly(weekdays: {1, 3}),
        Recurrence.weekly(weekdays: {3, 1}),
        Recurrence.weekly(weekdays: {1, 4}),
      };
      expect(rules, hasLength(2));
    });
  });
}
