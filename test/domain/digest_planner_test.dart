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

  group('planDigest', () {
    final now = DateTime(2026, 7, 24, 7); // ahead of the 08:00 default

    test('disabled always returns null, even with nonzero counts', () {
      final plan = planDigest(
        now: now,
        digestMinutes: 480,
        enabled: false,
        dueTodayCount: 3,
        overdueCount: 2,
      );
      expect(plan, isNull);
    });

    test('zero counts returns null when enabled (silence is a feature)', () {
      final plan = planDigest(
        now: now,
        digestMinutes: 480,
        enabled: true,
        dueTodayCount: 0,
        overdueCount: 0,
      );
      expect(plan, isNull);
    });

    test('due-today-only still schedules', () {
      final plan = planDigest(
        now: now,
        digestMinutes: 480,
        enabled: true,
        dueTodayCount: 3,
        overdueCount: 0,
      );
      expect(plan, isNotNull);
      expect(plan!.dueTodayCount, 3);
      expect(plan.overdueCount, 0);
      expect(plan.fireAt, DateTime(2026, 7, 24, 8));
    });

    test('overdue-only still schedules (must not silently rot)', () {
      final plan = planDigest(
        now: now,
        digestMinutes: 480,
        enabled: true,
        dueTodayCount: 0,
        overdueCount: 1,
      );
      expect(plan, isNotNull);
      expect(plan!.dueTodayCount, 0);
      expect(plan.overdueCount, 1);
      expect(plan.fireAt, DateTime(2026, 7, 24, 8));
    });

    test('both nonzero counts still schedules, carrying both counts', () {
      final plan = planDigest(
        now: now,
        digestMinutes: 480,
        enabled: true,
        dueTodayCount: 2,
        overdueCount: 1,
      );
      expect(plan!.dueTodayCount, 2);
      expect(plan.overdueCount, 1);
    });

    test('fireAt matches nextDigestSlot for the same now/digestMinutes', () {
      final plan = planDigest(
        now: now,
        digestMinutes: 480,
        enabled: true,
        dueTodayCount: 1,
        overdueCount: 0,
      );
      expect(plan!.fireAt, nextDigestSlot(now: now, digestMinutes: 480));
    });

    test('rejects an out-of-range digestMinutes', () {
      expect(
        () => planDigest(
          now: now,
          digestMinutes: 1440,
          enabled: true,
          dueTodayCount: 1,
          overdueCount: 0,
        ),
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
    test('returns digestHorizonDays consecutive slots by default', () {
      final slots = digestSlots(
        now: DateTime(2026, 7, 24, 7),
        digestMinutes: 480,
      );
      expect(slots, hasLength(digestHorizonDays));
      expect(slots.first, DateTime(2026, 7, 24, 8));
      expect(slots.last, DateTime(2026, 7, 30, 8));
    });

    test('the first slot is exactly nextDigestSlot', () {
      final now = DateTime(2026, 7, 24, 9); // past 08:00
      final slots = digestSlots(now: now, digestMinutes: 480);
      expect(slots.first, nextDigestSlot(now: now, digestMinutes: 480));
      expect(slots.first, DateTime(2026, 7, 25, 8));
      expect(slots.last, DateTime(2026, 7, 31, 8));
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
      expect(slots.last, DateTime(2026, 8, 5, 8));
    });

    test('rejects an out-of-range digestMinutes', () {
      expect(
        () => digestSlots(now: DateTime(2026), digestMinutes: 1440),
        throwsArgumentError,
      );
    });

    test('rejects a horizon below one day', () {
      expect(
        () => digestSlots(
          now: DateTime(2026),
          digestMinutes: 480,
          horizonDays: 0,
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
