import 'dart:async';
import 'dart:ui';

import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_digest_notification_plugin.dart';

/// A [FakeDigestNotificationPlugin] that pauses the very FIRST
/// [zonedSchedule] call it ever receives -- across ANY caller -- until
/// [release] is called, then behaves normally forever after.
///
/// Used only by the FIX 2 serialization test below, to force two
/// concurrent [NotificationScheduler.applyDigestPlans] calls to actually
/// overlap in time, deterministically: a fake with uniform latency would
/// make both calls proceed in lockstep and prove nothing about ordering.
/// Mirrors `_PausingPlugin` in `test/app/digest_reschedule_test.dart`,
/// gated on call order rather than notification id since both callers'
/// plans use the same ids.
class _GatedPlugin extends FakeDigestNotificationPlugin {
  final Completer<void> _gate = Completer<void>();
  bool _hasPaused = false;

  /// Lets the paused call (if any) proceed.
  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    if (!_hasPaused) {
      _hasPaused = true;
      await _gate.future;
    }
    await super.zonedSchedule(id: id, title: title, body: body, fireAt: fireAt);
  }
}

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

  group('the notification id budget', () {
    test("the digest leaves at least 32 of iOS's 64 pending slots for "
        'per-chore reminders', () {
      // iOS caps an app at 64 pending notifications. The number the digest
      // actually competes with is NOT 64 -- it is whatever N2 / per-chore
      // reminders (backlog G-6 / F16) will need, and those are unbuilt, so
      // nothing else can defend their share. Raising the horizon past this
      // guard means renegotiating that split, not editing this number.
      // Documented in docs/specs/notifications.md, "Notification id
      // budget".
      expect(
        digestHorizonSlots,
        lessThanOrEqualTo(32),
        reason:
            "at least 32 of iOS's 64 pending notification slots must stay "
            'available for N2 / per-chore reminders (backlog G-6 / F16)',
      );
    });

    test('the ids are exactly digestHorizonSlots consecutive ids from the '
        'base', () {
      expect(digestNotificationIds, hasLength(digestHorizonSlots));
      expect(digestNotificationIds, [
        for (var k = 0; k < digestHorizonSlots; k++)
          digestNotificationIdBase + k,
      ]);
    });
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
      for (var k = 0; k < digestHorizonSlots; k++) byIndex[k],
    ];

    test('rejects a list that is not exactly digestHorizonSlots long', () {
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
      expect(plugin.cancelCallCount, digestHorizonSlots - 1);
      expect(plugin.pending.keys, [1001]);
    });

    test('a later apply overwrites the whole horizon, silencing days that '
        'no longer have anything to say', () async {
      await scheduler.applyDigestPlans(
        plansOf({
          for (var k = 0; k < digestHorizonSlots; k++)
            k: DigestPlan(
              fireAt: DateTime(2026, 7, 24 + k, 8),
              dueTodayCount: 1,
              overdueCount: 0,
            ),
        }),
      );
      expect(plugin.pending, hasLength(digestHorizonSlots));

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
        for (var k = 1; k < digestHorizonSlots; k++) null,
      ]);
      expect(plugin.pending[1001]!.body, '2 Aufgaben heute · 1 überfällig');
    });

    test(
      'FIX 2: two concurrent calls from different callers cannot '
      'interleave their whole-horizon writes -- the later caller is not '
      'left '
      'with slots clobbered by an earlier one resuming after it',
      () async {
        final gatedPlugin = _GatedPlugin();
        final gatedScheduler = NotificationScheduler(
          plugin: gatedPlugin,
          localeResolver: () => const Locale('en'),
        );

        List<DigestPlan?> plansWithCount(int count) => [
          for (var k = 0; k < digestHorizonSlots; k++)
            DigestPlan(
              fireAt: DateTime(2026, 7, 24 + k, 8),
              dueTodayCount: count,
              overdueCount: 0,
            ),
        ];

        // Caller A (e.g. the controller's recompute) starts first; its
        // very first `zonedSchedule` call blocks on the gate.
        final callA = gatedScheduler.applyDigestPlans(plansWithCount(1));
        // Give A's Future chain a turn to actually run up to the gate.
        await Future<void>.delayed(Duration.zero);

        // Caller B (e.g. the pre-prompt banner's own apply) starts while A
        // is still paused mid-loop.
        final callB = gatedScheduler.applyDigestPlans(plansWithCount(2));
        await Future<void>.delayed(Duration.zero);

        // The gate only pauses the very first `zonedSchedule` call ever
        // (A's). If B's loop could run concurrently with A's, B -- being
        // unblocked -- would already have written its whole horizon by
        // now. Serialized correctly, B is still queued behind A and has
        // written nothing yet.
        expect(
          gatedPlugin.pending,
          isEmpty,
          reason: 'caller B must wait behind caller A, not run concurrently',
        );

        gatedPlugin.release();
        await callA;
        await callB;

        // The final horizon is entirely B's. If the two loops had
        // interleaved (the bug this guards against), A resuming after B
        // had already written would overwrite some slots with A's stale
        // count.
        expect(
          gatedPlugin.pending.values.every(
            (call) => call.body == '2 chores today',
          ),
          isTrue,
          reason: 'no slot may be left over from the earlier, stale call',
        );
      },
    );

    test(
      'slot 0 firing leaves every later slot armed, with nothing to re-arm '
      'them — this is the whole point of the horizon (audit P0)',
      () async {
        await scheduler.applyDigestPlans([
          for (var k = 0; k < digestHorizonSlots; k++)
            DigestPlan(
              fireAt: DateTime(2026, 7, 24 + k, 8),
              dueTodayCount: 1,
              overdueCount: 0,
            ),
        ]);

        // The OS delivers slot 0's notification a minute after it fires.
        // Nothing re-arms it, but every later slot must remain untouched.
        plugin.deliverDue(DateTime(2026, 7, 24, 8, 1));

        expect(
          plugin.pending.keys,
          unorderedEquals([
            for (var k = 1; k < digestHorizonSlots; k++)
              digestNotificationIdBase + k,
          ]),
        );
      },
    );
  });

  group('notification channel (backlog E-1)', () {
    List<DigestPlan?> onlySlotZero() => [
      DigestPlan(
        fireAt: DateTime(2026, 7, 25, 8),
        dueTodayCount: 3,
        overdueCount: 0,
      ),
      for (var k = 1; k < digestHorizonSlots; k++) null,
    ];

    test(
      'the channel id is versioned: Android caches a channel name at '
      'CREATION and offers no rename, so newly-localized copy can only '
      'reach an existing install on a NEW id',
      () {
        expect(digestChannelId, 'digest_v2');
      },
    );

    test('schedules with the localized channel name and description', () async {
      await scheduler.applyDigestPlans(onlySlotZero());
      expect(plugin.pending[1001]!.channelName, 'Daily summary');
      expect(
        plugin.pending[1001]!.channelDescription,
        'The once-a-day chores digest notification.',
      );
    });

    test('German locale produces German channel copy', () async {
      final germanScheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await germanScheduler.applyDigestPlans(onlySlotZero());
      expect(plugin.pending[1001]!.channelName, 'Tägliche Zusammenfassung');
      expect(
        plugin.pending[1001]!.channelDescription,
        'Die einmal täglich versendete Aufgaben-Zusammenfassung.',
      );
    });

    test(
      'ensureInitialized deletes the legacy (pre-l10n) channel exactly '
      'once across repeated calls, so it stops lingering as a dead, '
      'English-named entry in system Settings',
      () async {
        await scheduler.ensureInitialized();
        await scheduler.ensureInitialized();
        await scheduler.ensureInitialized();
        expect(plugin.deleteLegacyDigestChannelCallCount, 1);
      },
    );

    test(
      'the legacy channel is deleted BEFORE anything is scheduled on the '
      'new one, so a user never briefly holds both',
      () async {
        await scheduler.applyDigestPlans(onlySlotZero());
        expect(plugin.deleteLegacyDigestChannelCallCount, 1);
        expect(plugin.pending, hasLength(1));
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
      expect(plugin.cancelCallCount, digestHorizonSlots);
      // Derived from the constant rather than hard-coded, so this survives
      // a change to the horizon's size: the ids are exactly
      // `digestNotificationIdBase` and the `digestHorizonSlots - 1`
      // consecutive ids after it.
      expect(digestNotificationIds, hasLength(digestHorizonSlots));
      expect(digestNotificationIds.first, digestNotificationIdBase);
      expect(digestNotificationIds, [
        for (var k = 0; k < digestHorizonSlots; k++)
          digestNotificationIdBase + k,
      ]);
    });

    test('leaves nothing armed', () async {
      await scheduler.applyDigestPlans([
        for (var k = 0; k < digestHorizonSlots; k++)
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
