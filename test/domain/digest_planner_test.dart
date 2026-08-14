import 'package:chore_app/domain/digest_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextDigestSlot', () {
    test('today, when the digest time is still ahead of now', () {
      final now = DateTime(2026, 7, 24, 7, 30);
      final slot = nextDigestSlot(now: now, digestMinutes: 480); // 08:00
      expect(slot, DateTime(2026, 7, 24, 8));
    });

    test('tomorrow, when the digest time has already passed today', () {
      final now = DateTime(2026, 7, 24, 8, 30);
      final slot = nextDigestSlot(now: now, digestMinutes: 480); // 08:00
      expect(slot, DateTime(2026, 7, 25, 8));
    });

    test('boundary: exactly at digest time counts as "already passed"', () {
      // The spec's rule is "today at digest time IF STILL AHEAD of now,
      // else tomorrow" — at the exact instant, today's slot is not ahead
      // of now (it *is* now), so the next slot must be tomorrow: you can't
      // schedule a notification for a moment that isn't in the future.
      final now = DateTime(2026, 7, 24, 8);
      final slot = nextDigestSlot(now: now, digestMinutes: 480);
      expect(slot, DateTime(2026, 7, 25, 8));
    });

    test('midnight digest time is always tomorrow, never today', () {
      // Today's midnight (00:00) is, by construction, always at or before
      // any "now" that falls within today — so with digestMinutes: 0 the
      // resolved slot is always tomorrow's midnight.
      final now = DateTime(2026, 7, 24, 0, 0, 0, 1);
      final slot = nextDigestSlot(now: now, digestMinutes: 0);
      expect(slot, DateTime(2026, 7, 25));
    });

    test('just before midnight rolls over to tomorrow', () {
      final now = DateTime(2026, 7, 24, 23, 59);
      final slot = nextDigestSlot(now: now, digestMinutes: 0);
      expect(slot, DateTime(2026, 7, 25));
    });

    test('rolls over the calendar month and year correctly', () {
      final now = DateTime(2026, 12, 31, 23);
      final slot = nextDigestSlot(now: now, digestMinutes: 480);
      expect(slot, DateTime(2027, 1, 1, 8));
    });

    test(
      'DST spring-forward boundary (2026-03-29, EU clocks jump 02:00->03:00): '
      'the resolved slot keeps the same wall-clock hour:minute on the next '
      'calendar day regardless of the elapsed real-world duration, because '
      'the next slot is built from calendar components rather than '
      '`now.add(Duration(days: 1))`',
      () {
        final now = DateTime(2026, 3, 28, 23, 30);
        final slot = nextDigestSlot(now: now, digestMinutes: 480); // 08:00
        expect(slot, DateTime(2026, 3, 29, 8));
        expect(slot.hour, 8);
        expect(slot.minute, 0);
      },
    );

    test(
      'DST fall-back boundary (2026-10-25, EU clocks fold 03:00->02:00): '
      'same guarantee on the other transition',
      () {
        final now = DateTime(2026, 10, 25, 9);
        final slot = nextDigestSlot(now: now, digestMinutes: 480); // 08:00
        expect(slot, DateTime(2026, 10, 26, 8));
        expect(slot.hour, 8);
        expect(slot.minute, 0);
      },
    );

    test('rejects an out-of-range digestMinutes', () {
      expect(
        () => nextDigestSlot(now: DateTime(2026), digestMinutes: -1),
        throwsArgumentError,
      );
      expect(
        () => nextDigestSlot(now: DateTime(2026), digestMinutes: 1440),
        throwsArgumentError,
      );
    });
  });

  group('DigestPlan equality', () {
    test('two plans with identical fields are equal', () {
      final a = DigestPlan(
        fireAt: DateTime(2026, 7, 24, 8),
        dueTodayCount: 1,
        overdueCount: 2,
      );
      final b = DigestPlan(
        fireAt: DateTime(2026, 7, 24, 8),
        dueTodayCount: 1,
        overdueCount: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('plans differing in any field are not equal', () {
      final base = DigestPlan(
        fireAt: DateTime(2026, 7, 24, 8),
        dueTodayCount: 1,
        overdueCount: 2,
      );
      expect(
        base,
        isNot(
          DigestPlan(
            fireAt: DateTime(2026, 7, 24, 9),
            dueTodayCount: 1,
            overdueCount: 2,
          ),
        ),
      );
      expect(
        base,
        isNot(
          DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 2,
            overdueCount: 2,
          ),
        ),
      );
    });
  });

  group('digestSlots', () {
    test('returns digestHorizonSlots slots by default, reaching day 83', () {
      final slots = digestSlots(
        now: DateTime(2026, 7, 24, 7),
        digestMinutes: 480,
      );
      expect(slots, hasLength(digestHorizonSlots));
      expect(slots.first, DateTime(2026, 7, 24, 8));
      // Day offset (14 - 1) + 7 * 10 = 83 from the first slot.
      expect(slots.last, DateTime(2026, 10, 15, 8));
      // The two segments join with exactly one tail step between them:
      // the last daily slot is offset 13, the first tail slot offset 20.
      expect(slots[digestDailyHorizonDays - 1], DateTime(2026, 8, 6, 8));
      expect(slots[digestDailyHorizonDays], DateTime(2026, 8, 13, 8));
      expect(slots, orderedEquals(<DateTime>[...slots]..sort()));
    });

    test('the first slot is exactly nextDigestSlot', () {
      final now = DateTime(2026, 7, 24, 9); // past 08:00
      final slots = digestSlots(now: now, digestMinutes: 480);
      expect(slots.first, nextDigestSlot(now: now, digestMinutes: 480));
      expect(slots.first, DateTime(2026, 7, 25, 8));
      expect(slots.last, DateTime(2026, 10, 16, 8));
    });

    test('every slot keeps the same local wall-clock time across a DST '
        'transition', () {
      // 2026-03-29 is the European spring-forward day. Built from calendar
      // components, so 08:00 stays 08:00 rather than drifting to 09:00.
      final slots = digestSlots(
        now: DateTime(2026, 3, 27, 7),
        digestMinutes: 480,
      );
      for (final slot in slots) {
        expect(slot.hour, 8);
        expect(slot.minute, 0);
      }
    });

    test('rolls over the month boundary', () {
      final slots = digestSlots(
        now: DateTime(2026, 7, 30, 7),
        digestMinutes: 480,
      );
      // Offset 83 from 2026-07-30, across four month boundaries.
      expect(slots.last, DateTime(2026, 10, 21, 8));
    });

    test('rejects an out-of-range digestMinutes', () {
      expect(
        () => digestSlots(now: DateTime(2026), digestMinutes: 1440),
        throwsArgumentError,
      );
    });

    test('rejects a daily segment below one day', () {
      expect(
        () => digestSlots(
          now: DateTime(2026),
          digestMinutes: 480,
          dailyDays: 0,
        ),
        throwsArgumentError,
      );
    });

    test('a weekly tail follows the daily segment at one tail step of '
        'spacing', () {
      // Explicit parameters rather than the shipped constants, so this
      // test pins the SHAPE and survives any later change to the shipped
      // horizon size.
      final slots = digestSlots(
        now: DateTime(2026, 7, 24, 7),
        digestMinutes: 480,
        dailyDays: 3,
        weeklySlots: 2,
      );
      // Daily offsets 0,1,2; then weekly at (3-1)+7*(j+1) = 9 and 16.
      expect(slots, [
        DateTime(2026, 7, 24, 8),
        DateTime(2026, 7, 25, 8),
        DateTime(2026, 7, 26, 8),
        DateTime(2026, 8, 2, 8),
        DateTime(2026, 8, 9, 8),
      ]);
    });

    test('the weekly tail keeps the same local wall-clock time across a DST '
        'transition', () {
      // 2026-03-29 is the European spring-forward day, and it falls
      // between the daily segment and the first tail slot — so this covers
      // what the daily-only DST test above cannot.
      final slots = digestSlots(
        now: DateTime(2026, 3, 27, 7),
        digestMinutes: 480,
        dailyDays: 3,
        weeklySlots: 2,
      );
      expect(slots, hasLength(5));
      for (final slot in slots) {
        expect(slot.hour, 8);
        expect(slot.minute, 0);
      }
    });

    test('weeklySlots: 0 is exactly a plain daily run — the tail is '
        'genuinely optional', () {
      final now = DateTime(2026, 7, 24, 7);
      expect(
        digestSlots(
          now: now,
          digestMinutes: 480,
          dailyDays: 5,
          // Passed explicitly on purpose: this test pins that a zero tail
          // degenerates to a plain daily run, which must stay true
          // independently of whatever the shipped default happens to be.
          weeklySlots: 0,
        ),
        [
          for (var k = 0; k < 5; k++) DateTime(2026, 7, 24 + k, 8),
        ],
      );
    });

    test('rejects a negative weekly tail', () {
      expect(
        () => digestSlots(
          now: DateTime(2026),
          digestMinutes: 480,
          weeklySlots: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('planDigestSlot', () {
    final fireAt = DateTime(2026, 7, 25, 8);

    test('disabled returns null even with nonzero counts', () {
      expect(
        planDigestSlot(
          fireAt: fireAt,
          enabled: false,
          dueTodayCount: 3,
          overdueCount: 2,
        ),
        isNull,
      );
    });

    test('zero counts returns null (silence is a feature, per day)', () {
      expect(
        planDigestSlot(
          fireAt: fireAt,
          enabled: true,
          dueTodayCount: 0,
          overdueCount: 0,
        ),
        isNull,
      );
    });

    test('overdue-only still schedules (must not silently rot)', () {
      final plan = planDigestSlot(
        fireAt: fireAt,
        enabled: true,
        dueTodayCount: 0,
        overdueCount: 1,
      );
      expect(
        plan,
        DigestPlan(fireAt: fireAt, dueTodayCount: 0, overdueCount: 1),
      );
    });

    test('due-only, zero overdue, still schedules', () {
      final plan = planDigestSlot(
        fireAt: fireAt,
        enabled: true,
        dueTodayCount: 1,
        overdueCount: 0,
      );
      expect(
        plan,
        DigestPlan(fireAt: fireAt, dueTodayCount: 1, overdueCount: 0),
      );
    });

    test('carries both counts and the exact fireAt through', () {
      final plan = planDigestSlot(
        fireAt: fireAt,
        enabled: true,
        dueTodayCount: 2,
        overdueCount: 1,
      );
      expect(plan!.fireAt, fireAt);
      expect(plan.dueTodayCount, 2);
      expect(plan.overdueCount, 1);
    });
  });
}
