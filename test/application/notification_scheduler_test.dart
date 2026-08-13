import 'dart:ui';

import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_digest_notification_plugin.dart';

void main() {
  late FakeDigestNotificationPlugin plugin;
  late NotificationScheduler scheduler;

  setUp(() {
    plugin = FakeDigestNotificationPlugin();
    scheduler = NotificationScheduler(
      plugin: plugin,
      localeResolver: () => const Locale('en'),
    );
  });

  group('ensureInitialized', () {
    test('initializes the plugin exactly once across repeated calls', () async {
      await scheduler.ensureInitialized();
      await scheduler.ensureInitialized();
      await scheduler.ensureInitialized();
      expect(plugin.initializeCallCount, 1);
    });
  });

  group('applyDigestPlans', () {
    List<DigestPlan?> plansOf(Map<int, DigestPlan> byIndex) => [
      for (var k = 0; k < digestHorizonDays; k++) byIndex[k],
    ];

    test('rejects a list that is not exactly digestHorizonDays long', () {
      expect(
        () => scheduler.applyDigestPlans(const []),
        throwsArgumentError,
      );
    });

    test('slot k schedules id digestNotificationIdBase + k', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
          2: DigestPlan(
            fireAt: DateTime(2026, 7, 26, 8),
            dueTodayCount: 2,
            overdueCount: 0,
          ),
        }),
      );

      expect(plugin.pending.keys, unorderedEquals([1001, 1003]));
      expect(plugin.pending[1001]!.fireAt, DateTime(2026, 7, 24, 8));
      expect(plugin.pending[1003]!.body, '2 chores today');
    });

    test('a null slot cancels that day rather than scheduling it', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
        }),
      );
      expect(plugin.cancelCallCount, digestHorizonDays - 1);
      expect(plugin.pending.keys, [1001]);
    });

    test('a later apply overwrites the whole horizon, silencing days that '
        'no longer have anything to say', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          for (var k = 0; k < digestHorizonDays; k++)
            k: DigestPlan(
              fireAt: DateTime(2026, 7, 24 + k, 8),
              dueTodayCount: 1,
              overdueCount: 0,
            ),
        }),
      );
      expect(plugin.pending, hasLength(digestHorizonDays));

      await scheduler.applyDigestPlans(plansOf({}));
      expect(plugin.pending, isEmpty);
    });

    test('initializes the plugin implicitly, and never requests permission '
        '(spec polish-round-1.md A3)', () async {
      await scheduler.applyDigestPlans(plansOf({}));
      expect(plugin.initializeCallCount, 1);
      expect(plugin.requestPermissionCallCount, 0);
    });

    test('due-only body uses the ICU singular form for a count of 1', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
        }),
      );
      expect(plugin.pending[1001]!.body, '1 chore today');
    });

    test('overdue-only and combined bodies survive the move', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          0: DigestPlan(
            fireAt: DateTime(2026, 7, 24, 8),
            dueTodayCount: 0,
            overdueCount: 1,
          ),
          1: DigestPlan(
            fireAt: DateTime(2026, 7, 25, 8),
            dueTodayCount: 2,
            overdueCount: 1,
          ),
        }),
      );
      expect(plugin.pending[1001]!.body, '1 overdue chore');
      expect(plugin.pending[1002]!.body, '2 chores today · 1 overdue');
      expect(plugin.pending[1001]!.title, 'Famdo');
    });

    test('German locale produces German copy', () async {
      final germanScheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await germanScheduler.applyDigestPlans([
        DigestPlan(
          fireAt: DateTime(2026, 7, 24, 8),
          dueTodayCount: 2,
          overdueCount: 1,
        ),
        for (var k = 1; k < digestHorizonDays; k++) null,
      ]);
      expect(plugin.pending[1001]!.body, '2 Aufgaben heute · 1 überfällig');
    });

    test(
      'day 1 firing leaves days 2-7 armed, with nothing to re-arm them — '
      'this is the whole point of the horizon (audit P0)',
      () async {
        await scheduler.applyDigestPlans([
          for (var k = 0; k < digestHorizonDays; k++)
            DigestPlan(
              fireAt: DateTime(2026, 7, 24 + k, 8),
              dueTodayCount: 1,
              overdueCount: 0,
            ),
        ]);

        // The OS delivers day 1's notification a minute after it fires.
        // Nothing re-arms it, but days 2-7 must remain untouched.
        plugin.deliverDue(DateTime(2026, 7, 24, 8, 1));

        expect(
          plugin.pending.keys,
          unorderedEquals([1002, 1003, 1004, 1005, 1006, 1007]),
        );
      },
    );
  });

  group('cancelDigest', () {
    test('initializes the plugin implicitly if not done already', () async {
      await scheduler.cancelDigest();
      expect(plugin.initializeCallCount, 1);
    });

    test('cancels every id in the horizon, not just the first', () async {
      await scheduler.cancelDigest();
      expect(plugin.cancelCallCount, digestHorizonDays);
      expect(digestNotificationIds, [1001, 1002, 1003, 1004, 1005, 1006, 1007]);
    });

    test('leaves nothing armed', () async {
      await scheduler.applyDigestPlans([
        for (var k = 0; k < digestHorizonDays; k++)
          DigestPlan(
            fireAt: DateTime(2026, 7, 24 + k, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
      ]);
      await scheduler.cancelDigest();
      expect(plugin.pending, isEmpty);
    });

    test('does not request permission (no schedule attempt)', () async {
      await scheduler.cancelDigest();
      expect(plugin.requestPermissionCallCount, 0);
    });
  });
}
