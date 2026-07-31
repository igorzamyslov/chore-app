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

  group('scheduleDigest', () {
    final plan = DigestPlan(
      fireAt: DateTime(2026, 7, 25, 8),
      dueTodayCount: 3,
      overdueCount: 0,
    );

    test('initializes the plugin implicitly if not done already', () async {
      await scheduler.scheduleDigest(plan);
      expect(plugin.initializeCallCount, 1);
    });

    test(
      'never requests permission itself (spec polish-round-1.md A3: the '
      'OS dialog only ever fires from an explicit user tap)',
      () async {
        await scheduler.scheduleDigest(plan);
        await scheduler.scheduleDigest(plan);
        await scheduler.scheduleDigest(plan);
        expect(plugin.requestPermissionCallCount, 0);
      },
    );

    test('schedules with the fixed digest notification id', () async {
      await scheduler.scheduleDigest(plan);
      expect(plugin.scheduledCalls, hasLength(1));
      expect(plugin.scheduledCalls.single.id, digestNotificationId);
      expect(plugin.scheduledCalls.single.id, 1001);
    });

    test('title is the app name', () async {
      await scheduler.scheduleDigest(plan);
      expect(plugin.scheduledCalls.single.title, 'Famdo');
    });

    test("passes the plan's fireAt through unchanged", () async {
      await scheduler.scheduleDigest(plan);
      expect(plugin.scheduledCalls.single.fireAt, plan.fireAt);
    });

    test('due-only body, singular', () async {
      await scheduler.scheduleDigest(
        DigestPlan(fireAt: plan.fireAt, dueTodayCount: 1, overdueCount: 0),
      );
      expect(plugin.scheduledCalls.single.body, '1 chore today');
    });

    test('due-only body, plural', () async {
      await scheduler.scheduleDigest(
        DigestPlan(fireAt: plan.fireAt, dueTodayCount: 3, overdueCount: 0),
      );
      expect(plugin.scheduledCalls.single.body, '3 chores today');
    });

    test('overdue-only body (overdue-only days still notify)', () async {
      await scheduler.scheduleDigest(
        DigestPlan(fireAt: plan.fireAt, dueTodayCount: 0, overdueCount: 1),
      );
      expect(plugin.scheduledCalls.single.body, '1 overdue chore');
    });

    test('combined due + overdue body', () async {
      await scheduler.scheduleDigest(
        DigestPlan(fireAt: plan.fireAt, dueTodayCount: 2, overdueCount: 1),
      );
      expect(plugin.scheduledCalls.single.body, '2 chores today · 1 overdue');
    });

    test('German locale produces German copy', () async {
      final germanScheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await germanScheduler.scheduleDigest(
        DigestPlan(fireAt: plan.fireAt, dueTodayCount: 2, overdueCount: 1),
      );
      expect(plugin.scheduledCalls.single.title, 'Famdo');
      expect(
        plugin.scheduledCalls.single.body,
        '2 Aufgaben heute · 1 überfällig',
      );
    });
  });

  group('cancelDigest', () {
    test('initializes the plugin implicitly if not done already', () async {
      await scheduler.cancelDigest();
      expect(plugin.initializeCallCount, 1);
    });

    test('cancels the fixed digest notification id', () async {
      await scheduler.cancelDigest();
      expect(plugin.cancelCallCount, 1);
    });

    test('does not request permission (no schedule attempt)', () async {
      await scheduler.cancelDigest();
      expect(plugin.requestPermissionCallCount, 0);
    });
  });
}
