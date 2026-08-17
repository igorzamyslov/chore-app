// Pure unit tests for `sectionFor` (see `docs/specs/ux-round-2.md` A2): fast
// and exhaustive, per `docs/specs/testing-strategy.md` §1 ("if a case can be
// expressed at a lower layer, it MUST be"). No widget pump needed.
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/chore_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sectionFor: from a midweek day (Wednesday)', () {
    // 2026-07-22 is a Wednesday; the coming Sunday is 2026-07-26.
    final today = PlainDate(2026, 7, 22);

    test('strictly before today is overdue', () {
      expect(
        sectionFor(today: today, dueDate: PlainDate(2026, 7, 21)),
        ChoreSection.overdue,
      );
      expect(
        sectionFor(today: today, dueDate: PlainDate(2026, 1, 1)),
        ChoreSection.overdue,
      );
    });

    test('today is today', () {
      expect(sectionFor(today: today, dueDate: today), ChoreSection.today);
    });

    test('today + 1 is tomorrow', () {
      expect(
        sectionFor(today: today, dueDate: PlainDate(2026, 7, 23)),
        ChoreSection.tomorrow,
      );
    });

    test(
      'after tomorrow up to and including the coming Sunday is thisWeek',
      () {
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 7, 24)),
          ChoreSection.thisWeek,
        );
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 7, 26)),
          ChoreSection.thisWeek,
        );
      },
    );

    test(
      'after the coming Sunday but still this calendar month is thisMonth',
      () {
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 7, 27)),
          ChoreSection.thisMonth,
        );
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 7, 31)),
          ChoreSection.thisMonth,
        );
      },
    );

    test('a later calendar month is later', () {
      expect(
        sectionFor(today: today, dueDate: PlainDate(2026, 8, 1)),
        ChoreSection.later,
      );
      expect(
        sectionFor(today: today, dueDate: PlainDate(2027, 1, 1)),
        ChoreSection.later,
      );
    });
  });

  group('sectionFor: on a Sunday, "this week" is empty', () {
    // 2026-07-26 is a Sunday: addDays(7 - weekday) = addDays(0) = itself, so
    // there's no "coming Sunday" left this week.
    final today = PlainDate(2026, 7, 26);

    test('the very next day (Monday) is not thisWeek', () {
      final tomorrow = PlainDate(2026, 7, 27);
      expect(
        sectionFor(today: today, dueDate: tomorrow),
        ChoreSection.tomorrow,
      );
    });

    test('two days out lands in thisMonth (same month), not thisWeek', () {
      expect(
        sectionFor(today: today, dueDate: PlainDate(2026, 7, 28)),
        ChoreSection.thisMonth,
      );
    });
  });

  group(
    'sectionFor: month-end boundary (the coming Sunday crosses months)',
    () {
      // 2026-07-29 is a Wednesday; the coming Sunday, 2026-08-02, is already
      // in August. Every day from tomorrow through that Sunday is still
      // caught by thisWeek, so thisMonth is empty this particular week — the
      // day right after the Sunday goes straight to "later" (it's a new
      // month), never "this month".
      final today = PlainDate(2026, 7, 29);

      test('the last days of July are thisWeek, not thisMonth', () {
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 7, 31)),
          ChoreSection.thisWeek,
        );
      });

      test('the coming Sunday itself (already August) is thisWeek', () {
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 8, 2)),
          ChoreSection.thisWeek,
        );
      });

      test('the Monday right after is later, not thisMonth', () {
        expect(
          sectionFor(today: today, dueDate: PlainDate(2026, 8, 3)),
          ChoreSection.later,
        );
      });
    },
  );

  group('sectionFor: year boundary', () {
    // 2025-12-30 is a Tuesday; the coming Sunday is 2026-01-04.
    final today = PlainDate(2025, 12, 30);

    test('a date in January the following year is later, not thisMonth', () {
      expect(
        sectionFor(today: today, dueDate: PlainDate(2026, 1, 5)),
        ChoreSection.later,
      );
    });
  });
}
