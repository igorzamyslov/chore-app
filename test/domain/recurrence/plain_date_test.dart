import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('construction validity', () {
    test('rejects Feb 30', () {
      expect(() => PlainDate(2026, 2, 30), throwsArgumentError);
    });

    test('rejects month 13', () {
      expect(() => PlainDate(2026, 13, 1), throwsArgumentError);
    });

    test('rejects month 0', () {
      expect(() => PlainDate(2026, 0, 1), throwsArgumentError);
    });

    test('rejects day 0', () {
      expect(() => PlainDate(2026, 1, 0), throwsArgumentError);
    });

    test('accepts 2028-02-29 (leap year)', () {
      final date = PlainDate(2028, 2, 29);
      expect(date.year, 2028);
      expect(date.month, 2);
      expect(date.day, 29);
    });

    test('rejects 2027-02-29 (non-leap year)', () {
      expect(() => PlainDate(2027, 2, 29), throwsArgumentError);
    });

    test('accepts every day-31 month boundary', () {
      for (final month in [1, 3, 5, 7, 8, 10, 12]) {
        expect(PlainDate(2026, month, 31).day, 31);
      }
    });
  });

  group('fromDateTime', () {
    test('takes the calendar components as-is, ignoring time and zone', () {
      final dt = DateTime(2026, 7, 24, 23, 59, 59);
      final date = PlainDate.fromDateTime(dt);
      expect(date, PlainDate(2026, 7, 24));
    });
  });

  group('daysInMonth', () {
    const cases = <List<int>>[
      [2026, 1, 31],
      [2026, 2, 28],
      [2028, 2, 29],
      [2026, 4, 30],
      [2026, 12, 31],
    ];

    for (final c in cases) {
      test('daysInMonth(${c[0]}, ${c[1]}) == ${c[2]}', () {
        expect(PlainDate.daysInMonth(c[0], c[1]), c[2]);
      });
    }

    test('throws ArgumentError for an out-of-range month', () {
      expect(() => PlainDate.daysInMonth(2026, 0), throwsArgumentError);
      expect(() => PlainDate.daysInMonth(2026, 13), throwsArgumentError);
    });
  });

  group('addMonths clamping', () {
    test('Jan 31 + 1 month -> Feb 28 in a non-leap year', () {
      expect(PlainDate(2026, 1, 31).addMonths(1), PlainDate(2026, 2, 28));
    });

    test('Jan 31 + 1 month -> Feb 29 in a leap year', () {
      expect(PlainDate(2028, 1, 31).addMonths(1), PlainDate(2028, 2, 29));
    });

    test('does not roll Feb 30-equivalent into March (clamps instead)', () {
      // Jan 31 + 1 month must land in February, never spill into March.
      final result = PlainDate(2026, 1, 31).addMonths(1);
      expect(result.month, 2);
    });

    test('carries year forward past December', () {
      expect(PlainDate(2026, 11, 30).addMonths(2), PlainDate(2027, 1, 30));
    });

    test('carries year backward past January with negative n', () {
      expect(PlainDate(2026, 1, 15).addMonths(-2), PlainDate(2025, 11, 15));
    });

    test('addMonths(0) is a no-op', () {
      final date = PlainDate(2026, 3, 17);
      expect(date.addMonths(0), date);
    });

    test('unaffected days are preserved exactly', () {
      expect(PlainDate(2026, 3, 15).addMonths(1), PlainDate(2026, 4, 15));
    });
  });

  group('weekday correctness for known dates', () {
    // Verified against `cal`: 2026-07-04 is a Saturday.
    const cases = <List<int>>[
      [2026, 7, 20, DateTime.monday],
      [2026, 7, 21, DateTime.tuesday],
      [2026, 7, 22, DateTime.wednesday],
      [2026, 7, 23, DateTime.thursday],
      [2026, 7, 24, DateTime.friday],
      [2026, 7, 25, DateTime.saturday],
      [2026, 7, 26, DateTime.sunday],
      [2026, 7, 4, DateTime.saturday],
      [2026, 1, 1, DateTime.thursday],
    ];

    for (final c in cases) {
      test('${c[0]}-${c[1]}-${c[2]} has weekday ${c[3]}', () {
        expect(PlainDate(c[0], c[1], c[2]).weekday, c[3]);
      });
    }
  });

  group('parse / toIso8601 round trip', () {
    const isoStrings = ['2026-07-24', '2026-01-01', '2028-02-29', '0999-12-31'];

    for (final iso in isoStrings) {
      test('round-trips $iso', () {
        expect(PlainDate.parse(iso).toIso8601(), iso);
      });
    }

    test('throws FormatException on garbage input', () {
      expect(() => PlainDate.parse('not-a-date'), throwsFormatException);
      expect(() => PlainDate.parse('2026/07/24'), throwsFormatException);
      expect(() => PlainDate.parse('2026-7-24'), throwsFormatException);
      expect(() => PlainDate.parse(''), throwsFormatException);
    });

    test(
      'throws FormatException for a syntactically valid but impossible date',
      () {
        expect(() => PlainDate.parse('2027-02-29'), throwsFormatException);
        expect(() => PlainDate.parse('2026-02-30'), throwsFormatException);
        expect(() => PlainDate.parse('2026-13-01'), throwsFormatException);
      },
    );

    test('toString matches toIso8601', () {
      final date = PlainDate(2026, 7, 24);
      expect(date.toString(), date.toIso8601());
    });
  });

  group('ordering and equality', () {
    test('equal dates compare equal and share a hash code', () {
      final a = PlainDate(2026, 7, 24);
      final b = PlainDate(2026, 7, 24);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.compareTo(b), 0);
    });

    test('different dates are not equal', () {
      expect(PlainDate(2026, 7, 24), isNot(PlainDate(2026, 7, 25)));
    });

    test('isBefore / isAfter / isOnOrBefore / isOnOrAfter', () {
      final earlier = PlainDate(2026, 7, 24);
      final later = PlainDate(2026, 7, 25);
      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier.isAfter(later), isFalse);
      expect(later.isBefore(earlier), isFalse);

      expect(earlier.isOnOrBefore(earlier), isTrue);
      expect(earlier.isOnOrAfter(earlier), isTrue);
      expect(earlier.isOnOrBefore(later), isTrue);
      expect(later.isOnOrBefore(earlier), isFalse);
      expect(earlier.isOnOrAfter(later), isFalse);
      expect(later.isOnOrAfter(earlier), isTrue);
    });

    test('compareTo is negative/zero/positive as expected', () {
      final earlier = PlainDate(2026, 7, 24);
      final later = PlainDate(2026, 7, 25);
      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
      expect(earlier.compareTo(earlier), 0);
    });

    test('sorts correctly via Comparable', () {
      final dates = [
        PlainDate(2026, 7, 25),
        PlainDate(2026, 1, 1),
        PlainDate(2025, 12, 31),
        PlainDate(2026, 7, 24),
      ]..sort();
      expect(dates.map((d) => d.toIso8601()).toList(), [
        '2025-12-31',
        '2026-01-01',
        '2026-07-24',
        '2026-07-25',
      ]);
    });
  });

  group('daysUntil signs', () {
    test('is positive when other is later', () {
      expect(PlainDate(2026, 7, 24).daysUntil(PlainDate(2026, 7, 25)), 1);
    });

    test('is negative when other is earlier', () {
      expect(PlainDate(2026, 7, 25).daysUntil(PlainDate(2026, 7, 24)), -1);
    });

    test('is zero for the same date', () {
      expect(PlainDate(2026, 7, 24).daysUntil(PlainDate(2026, 7, 24)), 0);
    });

    test('spans months and years correctly', () {
      expect(PlainDate(2026, 1, 1).daysUntil(PlainDate(2027, 1, 1)), 365);
      expect(PlainDate(2028, 1, 1).daysUntil(PlainDate(2029, 1, 1)), 366);
    });
  });

  group('addDays', () {
    test('supports negative offsets', () {
      expect(PlainDate(2026, 7, 24).addDays(-1), PlainDate(2026, 7, 23));
    });

    test('crosses month and year boundaries', () {
      expect(PlainDate(2026, 12, 31).addDays(1), PlainDate(2027, 1, 1));
      expect(PlainDate(2026, 1, 1).addDays(-1), PlainDate(2025, 12, 31));
    });
  });

  group('DST immunity', () {
    // Europe/Berlin springs forward on 2026-03-29 and falls back on
    // 2026-10-25. PlainDate is backed by UTC midnight and never touches the
    // local timezone, so addDays must shift by exactly one calendar day
    // across both transitions regardless of what the local clock does.
    test('addDays(1) across the spring-forward transition shifts one day', () {
      expect(PlainDate(2026, 3, 29).addDays(1), PlainDate(2026, 3, 30));
    });

    test('addDays(1) across the fall-back transition shifts one day', () {
      expect(PlainDate(2026, 10, 25).addDays(1), PlainDate(2026, 10, 26));
    });
  });
}
