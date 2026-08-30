import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:chore_app/application/digest_plan_builder.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_digest_notification_plugin.dart';

/// Which kind of plugin call [_GatedPlugin] and [_ThrowingOncePlugin] act
/// on.
///
/// `applyDigestPlans` and `cancelDigest` ride one shared write queue
/// (backlog G-12), so the interleaving tests below have to be able to pause
/// either side of it.
enum _DigestCall {
  /// A `zonedSchedule` call, i.e. `applyDigestPlans` arming a slot.
  schedule,

  /// A `cancel` call, i.e. `cancelDigest` (or an apply's null slot)
  /// clearing one.
  cancel,
}

/// A [FakeDigestNotificationPlugin] that pauses the very FIRST call of
/// [target]'s kind it ever receives -- across ANY caller -- until [release]
/// is called, then behaves normally forever after.
///
/// Used only by the serialization tests below, to force two concurrent
/// digest writes to actually overlap in time, deterministically: a fake
/// with uniform latency would make both calls proceed in lockstep and
/// prove nothing about ordering. Mirrors `_PausingPlugin` in
/// `test/app/digest_reschedule_test.dart`, gated on call order rather than
/// notification id since both callers' plans use the same ids.
class _GatedPlugin extends FakeDigestNotificationPlugin {
  _GatedPlugin({this.target = _DigestCall.schedule});

  /// Which kind of call gets paused.
  final _DigestCall target;

  final Completer<void> _gate = Completer<void>();
  bool _hasPaused = false;

  /// Lets the paused call (if any) proceed.
  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  Future<void> _pauseIfFirst(_DigestCall kind) async {
    if (target != kind || _hasPaused) {
      return;
    }
    _hasPaused = true;
    await _gate.future;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelId,
    required String channelName,
    required String channelDescription,
    String? payload,
    bool actionable = false,
  }) async {
    await _pauseIfFirst(_DigestCall.schedule);
    await super.zonedSchedule(
      id: id,
      title: title,
      body: body,
      fireAt: fireAt,
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
      payload: payload,
      actionable: actionable,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _pauseIfFirst(_DigestCall.cancel);
    await super.cancel(id);
  }
}

/// A [FakeDigestNotificationPlugin] whose FIRST call of [target]'s kind
/// throws, then behaves normally forever after.
///
/// Used by the error-isolation guards below (backlog G-12): a failed digest
/// write must surface to the caller that made THAT call, and must not
/// permanently jam the shared write queue for everything after it.
class _ThrowingOncePlugin extends FakeDigestNotificationPlugin {
  _ThrowingOncePlugin({required this.target});

  /// Which kind of call throws, once.
  final _DigestCall target;

  bool _hasThrown = false;

  bool _shouldThrow(_DigestCall kind) {
    if (target != kind || _hasThrown) {
      return false;
    }
    _hasThrown = true;
    return true;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    required String channelId,
    required String channelName,
    required String channelDescription,
    String? payload,
    bool actionable = false,
  }) async {
    if (_shouldThrow(_DigestCall.schedule)) {
      // Stands in for the platform channel failing mid-horizon.
      throw StateError('zonedSchedule failed');
    }
    await super.zonedSchedule(
      id: id,
      title: title,
      body: body,
      fireAt: fireAt,
      channelId: channelId,
      channelName: channelName,
      channelDescription: channelDescription,
      payload: payload,
      actionable: actionable,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_shouldThrow(_DigestCall.cancel)) {
      // Stands in for the platform channel failing mid-horizon.
      throw StateError('cancel failed');
    }
    await super.cancel(id);
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

  group('the digest Done action (backlog F-1, spec notifications.md N2)', () {
    List<DigestPlan?> plansOf(Map<int, DigestPlan> byIndex) => [
      for (var k = 0; k < digestHorizonSlots; k++) byIndex[k],
    ];

    DigestPlan planWith({String? soleOccurrenceId, int dueTodayCount = 1}) =>
        DigestPlan(
          fireAt: DateTime(2026, 7, 24, 8),
          dueTodayCount: dueTodayCount,
          overdueCount: 0,
          soleOccurrenceId: soleOccurrenceId,
        );

    test(
      'a slot naming a sole occurrence is scheduled actionable, with a '
      'payload that DECODES to the occurrence and the acting member',
      () async {
        await scheduler.applyDigestPlans(
          plansOf({0: planWith(soleOccurrenceId: 'occ-1')}),
          actingMemberId: 'member-7',
        );

        final call = plugin.pending[1001]!;
        expect(call.actionable, isTrue);
        // Asserted on the DECODED map, never on a hand-written JSON string:
        // string equality would pin key order, which jsonEncode does not
        // guarantee.
        expect(jsonDecode(call.payload!), {
          'v': 1,
          'occ': 'occ-1',
          'by': 'member-7',
        });
      },
    );

    test('a slot naming no sole occurrence is scheduled non-actionable with '
        'no payload at all', () async {
      await scheduler.applyDigestPlans(
        plansOf({0: planWith(dueTodayCount: 2)}),
        actingMemberId: 'member-7',
      );

      final call = plugin.pending[1001]!;
      expect(call.actionable, isFalse);
      expect(call.payload, isNull);
    });

    test('MIXED horizon in ONE apply: actionability is decided per slot, not '
        'once per apply', () async {
      // The assertion that catches a global rather than per-slot gate. Under
      // the real projection this is the common shape: counts only grow along
      // the horizon, so a one-occurrence slot is routinely followed by
      // two-occurrence ones.
      await scheduler.applyDigestPlans(
        plansOf({
          0: planWith(soleOccurrenceId: 'occ-1'),
          5: planWith(dueTodayCount: 2),
          9: planWith(soleOccurrenceId: 'occ-9'),
        }),
        actingMemberId: 'member-7',
      );

      expect(plugin.pending[1001]!.actionable, isTrue);
      expect(plugin.pending[1006]!.actionable, isFalse);
      expect(plugin.pending[1006]!.payload, isNull);
      expect(plugin.pending[1010]!.actionable, isTrue);
      expect(
        (jsonDecode(plugin.pending[1010]!.payload!) as Map)['occ'],
        'occ-9',
      );
    });

    test('a null actingMemberId still yields a valid payload with by: null '
        '-- an unattributed completion, never a dropped action', () async {
      await scheduler.applyDigestPlans(
        plansOf({0: planWith(soleOccurrenceId: 'occ-1')}),
      );

      final call = plugin.pending[1001]!;
      expect(call.actionable, isTrue);
      expect(jsonDecode(call.payload!), {'v': 1, 'occ': 'occ-1', 'by': null});
    });

    test('ensureInitialized passes the localized Done title through for the '
        'iOS category', () async {
      await scheduler.ensureInitialized();
      expect(plugin.lastDoneActionTitle, 'Done');
    });

    test('German locale localizes the Done title', () async {
      final germanScheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await germanScheduler.ensureInitialized();
      expect(plugin.lastDoneActionTitle, 'Erledigt');
    });

    test('the action id is namespaced, so a future per-chore reminder (G-6) '
        'cannot collide with it on the process-global callback', () {
      expect(digestDoneActionId, 'digest.done');
      expect(digestActionsCategoryId, 'digestActions');
    });
  });

  group('resolveDigestLocale', () {
    test('an in-app language override wins over the OS locale', () {
      // The whole point: the UI honours the override, so the notification
      // copy must too -- reading only the OS locale gave a user who picked
      // German on an English phone English notifications behind a German
      // app.
      expect(resolveDigestLocale(const Locale('de')), const Locale('de'));
      expect(resolveDigestLocale(const Locale('en')), const Locale('en'));
    });

    test('no override falls back to the OS locale', () {
      expect(
        resolveDigestLocale(null),
        PlatformDispatcher.instance.locale,
        reason:
            'null means "nothing stored", which is also what an '
            "unrecognized stored value maps to via localeOverrideProvider's "
            'read-time self-heal -- it must degrade to the OS locale, not '
            'throw',
      );
    });
  });

  group('notification channel (backlog E-1)', () {
    test(
      'the reminder and evening channel ids are minted fresh and are '
      "distinct from the digest's -- Android caches channel copy at "
      'creation and cannot rename, so reusing digest_v2 would give these '
      "two the digest's name forever (spec "
      'docs/specs/notifications-n2.md §9.3)',
      () {
        expect(remindersChannelId, 'reminders_v1');
        expect(eveningChannelId, 'evening_v1');
        expect({
          digestChannelId,
          remindersChannelId,
          eveningChannelId,
        }, hasLength(3));
      },
    );

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

    test(
      "the digest still schedules on its OWN channel now that the seam "
      "carries a channel id -- E-1's localized name must not move",
      () async {
        await scheduler.applyDigestPlans(onlySlotZero());
        expect(plugin.scheduledCalls.single.channelId, digestChannelId);
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

  group('cancelAll', () {
    test('initializes the plugin implicitly if not done already', () async {
      await scheduler.cancelAll();
      expect(plugin.initializeCallCount, 1);
    });

    test(
      'cancels every id in all three ranges -- all 64 -- because a wipe '
      'that leaves per-chore reminders armed is strictly worse than the '
      'digest case G-12 fixed: a reminder NAMES a chore that no longer '
      'exists (spec docs/specs/notifications-n2.md §9.2)',
      () async {
        await scheduler.cancelAll();
        expect(
          plugin.cancelCallCount,
          digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
        );
        expect(
          digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
          64,
          reason: 'the whole iOS budget, spent exactly (§3.1)',
        );
        // Derived from the constants rather than hard-coded, so this
        // survives a change to any range's size.
        expect(digestNotificationIds, hasLength(digestHorizonSlots));
        expect(digestNotificationIds.first, digestNotificationIdBase);
        expect(digestNotificationIds, [
          for (var k = 0; k < digestHorizonSlots; k++)
            digestNotificationIdBase + k,
        ]);
      },
    );

    test('leaves nothing armed', () async {
      await scheduler.applyDigestPlans([
        for (var k = 0; k < digestHorizonSlots; k++)
          DigestPlan(
            fireAt: DateTime(2026, 7, 24 + k, 8),
            dueTodayCount: 1,
            overdueCount: 0,
          ),
      ]);
      await scheduler.cancelAll();
      expect(plugin.pending, isEmpty);
    });

    test('leaves nothing armed in ANY range', () async {
      final reminders = List<ReminderPlan?>.filled(reminderCeiling, null);
      reminders[0] = ReminderPlan(
        fireAt: DateTime(2026, 8, 30, 18),
        occurrenceId: 'o1',
        choreId: 'c1',
        choreTitle: 'Bins',
        dueDate: PlainDate(2026, 8, 30),
      );
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[0] = EveningPlan(
        fireAt: DateTime(2026, 8, 30, 20),
        openCount: 1,
      );
      await scheduler.applyPlans(
        NotificationPlanSet(
          digest: List<DigestPlan?>.filled(digestHorizonSlots, null),
          reminders: reminders,
          evening: evening,
          reminderOverflowCount: 0,
        ),
      );
      expect(plugin.pending, isNotEmpty);

      await scheduler.cancelAll();
      expect(plugin.pending, isEmpty);
    });

    test(
      'ONE enqueued write, not three (D9): a wipe arriving DURING an apply '
      'must leave nothing armed in any range -- three enqueued writes would '
      'leave gaps for it to land in, and Rule D couples the ranges (spec '
      'docs/specs/notifications-n2.md §9.2)',
      () async {
        // The obvious version of this test -- two concurrent applies, the
        // later one expected to win the reminder range -- CANNOT FAIL: that
        // is FIFO, the enqueue is synchronous, and three chained sub-writes
        // leave the same winner. What actually distinguishes one write from
        // three is that three leave GAPS a different kind of write can land
        // in, and the only other write is `cancelAll`.
        //
        // Gate the first `cancel`, which pauses `applyPlans` inside its
        // DIGEST range (the digest list here is all-null, so its first act
        // is a cancel). Then enqueue `cancelAll()` behind it. With ONE
        // write the cancel waits for all three ranges and clears
        // everything. With THREE, the reminder and evening sub-writes are
        // only enqueued once the digest sub-write completes -- i.e. BEHIND
        // the cancel -- so they arm ids the wipe has already cleared.
        final gatedPlugin = _GatedPlugin(target: _DigestCall.cancel);
        final gated = NotificationScheduler(
          plugin: gatedPlugin,
          localeResolver: () => const Locale('en'),
        );
        final reminders = List<ReminderPlan?>.filled(reminderCeiling, null);
        reminders[0] = ReminderPlan(
          fireAt: DateTime(2026, 8, 30, 18),
          occurrenceId: 'o1',
          choreId: 'c1',
          choreTitle: 'Bins',
          dueDate: PlainDate(2026, 8, 30),
        );
        final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
        evening[0] = EveningPlan(
          fireAt: DateTime(2026, 8, 30, 20),
          openCount: 1,
        );

        final apply = gated.applyPlans(
          NotificationPlanSet(
            digest: List<DigestPlan?>.filled(digestHorizonSlots, null),
            reminders: reminders,
            evening: evening,
            reminderOverflowCount: 0,
          ),
        );
        // Let the apply actually reach the gate, so the wipe arrives
        // mid-apply rather than before it.
        await pumpEventQueue();
        final wipe = gated.cancelAll();
        gatedPlugin.release();
        await Future.wait([apply, wipe]);

        expect(gatedPlugin.pending, isEmpty);
      },
    );

    test('does not request permission (no schedule attempt)', () async {
      await scheduler.cancelAll();
      expect(plugin.requestPermissionCallCount, 0);
    });
  });

  group(
    'cancelAll is serialized against applyDigestPlans (backlog G-12)',
    () {
      List<DigestPlan?> fullHorizon(int count) => [
        for (var k = 0; k < digestHorizonSlots; k++)
          DigestPlan(
            fireAt: DateTime(2026, 7, 24 + k, 8),
            dueTodayCount: count,
            overdueCount: 0,
          ),
      ];

      test(
        'a cancel issued during an in-flight apply runs AFTER it, so a wipe '
        'cannot be left with slots the apply re-armed behind its back',
        () async {
          final gatedPlugin = _GatedPlugin();
          final gatedScheduler = NotificationScheduler(
            plugin: gatedPlugin,
            localeResolver: () => const Locale('en'),
          );

          // The apply (e.g. the controller's recompute, or the notification
          // action isolate's rewrite) starts first and blocks on the gate
          // BEFORE writing slot 0.
          final apply = gatedScheduler.applyDigestPlans(fullHorizon(1));
          await Future<void>.delayed(Duration.zero);

          // The wipe's cancel arrives while the apply is paused mid-loop.
          final cancel = gatedScheduler.cancelAll();
          await Future<void>.delayed(Duration.zero);

          // Nothing gates `cancel`, so if the cancel could run
          // concurrently it would already have looped over the whole
          // horizon by now. Serialized, it has not issued a single call.
          expect(
            gatedPlugin.cancelCallCount,
            0,
            reason:
                'the cancel must wait behind the in-flight apply, not run '
                'concurrently with it',
          );

          gatedPlugin.release();
          await apply;
          await cancel;

          // The real defect: unserialized, the apply resumes after the
          // cancel has already cleared every id and re-arms all of them,
          // leaving a wiped app with a full armed horizon.
          expect(
            gatedPlugin.pending,
            isEmpty,
            reason: 'the cancel is the later caller, so nothing may stay armed',
          );
        },
      );

      test(
        'an apply issued during an in-flight cancel runs AFTER it, so a '
        'legitimate post-wipe recompute still ends up armed',
        () async {
          final gatedPlugin = _GatedPlugin(target: _DigestCall.cancel);
          final gatedScheduler = NotificationScheduler(
            plugin: gatedPlugin,
            localeResolver: () => const Locale('en'),
          );

          // The cancel starts first and blocks on the gate BEFORE clearing
          // its first id.
          final cancel = gatedScheduler.cancelAll();
          await Future<void>.delayed(Duration.zero);

          // A recompute arrives while the cancel is paused mid-loop.
          final apply = gatedScheduler.applyDigestPlans(fullHorizon(1));
          await Future<void>.delayed(Duration.zero);

          // Nothing gates `zonedSchedule`, so an unserialized apply would
          // already have written its whole horizon by now.
          expect(
            gatedPlugin.scheduledCalls,
            isEmpty,
            reason:
                'the apply must wait behind the in-flight cancel, not run '
                'concurrently with it',
          );

          gatedPlugin.release();
          await cancel;
          await apply;

          // The apply is the later caller and therefore the last word: its
          // horizon must survive. Unserialized, the cancel's trailing ids
          // land after the apply wrote them and silence the digest.
          expect(
            gatedPlugin.pending.keys,
            unorderedEquals(digestNotificationIds),
            reason: 'the apply is the later caller, so its horizon must stand',
          );
        },
      );

      test(
        'a failed cancel surfaces to ITS caller and does not jam the queue '
        'for the next write',
        () async {
          final failingPlugin = _ThrowingOncePlugin(
            target: _DigestCall.cancel,
          );
          final failingScheduler = NotificationScheduler(
            plugin: failingPlugin,
            localeResolver: () => const Locale('en'),
          );

          // Property 1: the error reaches the caller that made THAT call.
          await expectLater(failingScheduler.cancelAll(), throwsStateError);

          // Property 2: the shared tail was never left completing with an
          // error, so everything queued after it still runs. Getting this
          // wrong is silent and permanent -- the digest would simply stop
          // being rewritten for the rest of the process.
          await failingScheduler.applyDigestPlans(fullHorizon(1));
          expect(
            failingPlugin.pending.keys,
            unorderedEquals(digestNotificationIds),
          );
        },
      );

      test(
        'a failed apply surfaces to ITS caller and does not jam the queue '
        'for a following cancel',
        () async {
          final failingPlugin = _ThrowingOncePlugin(
            target: _DigestCall.schedule,
          );
          final failingScheduler = NotificationScheduler(
            plugin: failingPlugin,
            localeResolver: () => const Locale('en'),
          );

          await expectLater(
            failingScheduler.applyDigestPlans(fullHorizon(1)),
            throwsStateError,
          );

          await failingScheduler.cancelAll();
          expect(failingPlugin.cancelCallCount, digestHorizonSlots);
        },
      );
    },
  );

  group('applyPlans (spec docs/specs/notifications-n2.md §9.2)', () {
    NotificationPlanSet planSet({
      List<ReminderPlan?>? reminders,
      List<EveningPlan?>? evening,
      List<DigestPlan?>? digest,
    }) => NotificationPlanSet(
      digest: digest ?? List<DigestPlan?>.filled(digestHorizonSlots, null),
      reminders: reminders ?? List<ReminderPlan?>.filled(reminderCeiling, null),
      evening: evening ?? List<EveningPlan?>.filled(eveningHorizonSlots, null),
      reminderOverflowCount: 0,
    );

    List<ReminderPlan?> onlyReminderZero({
      required DateTime fireAt,
      required PlainDate dueDate,
      String choreTitle = 'Bins',
    }) => [
      ReminderPlan(
        fireAt: fireAt,
        occurrenceId: 'o1',
        choreId: 'c1',
        choreTitle: choreTitle,
        dueDate: dueDate,
      ),
      ...List<ReminderPlan?>.filled(reminderCeiling - 1, null),
    ];

    test('reminder i schedules id reminderNotificationIdBase + i', () async {
      await scheduler.applyPlans(
        planSet(
          reminders: onlyReminderZero(
            fireAt: DateTime(2026, 8, 30, 18),
            dueDate: PlainDate(2026, 8, 30),
          ),
        ),
      );
      final call = plugin.scheduledCalls.single;
      expect(call.id, reminderNotificationIdBase);
      expect(
        call.title,
        'Bins',
        reason:
            'the TITLE is the chore title verbatim -- that is the whole of '
            'AC1 (§11)',
      );
      expect(call.body, 'Due today');
      expect(call.channelId, remindersChannelId);
      expect(
        call.actionable,
        isFalse,
        reason:
            'actions are slice 7; a reminder must NOT reuse '
            'digestDoneActionId (notifications.md requires each surface to '
            'mint its own)',
      );
      expect(call.payload, isNull);
    });

    test(
      'reminder i schedules id reminderNotificationIdBase + i for a '
      'NON-ZERO i too -- the position IS the id, so an off-by-one here '
      'would point the payload at the wrong chore',
      () async {
        final reminders = List<ReminderPlan?>.filled(reminderCeiling, null);
        reminders[5] = ReminderPlan(
          fireAt: DateTime(2026, 8, 30, 18),
          occurrenceId: 'o6',
          choreId: 'c6',
          choreTitle: 'Sixth',
          dueDate: PlainDate(2026, 8, 30),
        );
        await scheduler.applyPlans(planSet(reminders: reminders));
        expect(plugin.scheduledCalls.single.id, reminderNotificationIdBase + 5);
      },
    );

    test(
      'a reminder armed LATER than its due date says "Still open" -- a '
      'snooze or a quiet-hours deferral (§11)',
      () async {
        await scheduler.applyPlans(
          planSet(
            reminders: onlyReminderZero(
              fireAt: DateTime(2026, 8, 31, 7),
              dueDate: PlainDate(2026, 8, 30),
            ),
          ),
        );
        expect(plugin.scheduledCalls.single.body, 'Still open');
      },
    );

    test(
      'evening slot k schedules id eveningNotificationIdBase + k, on its '
      'own channel, with the ICU plural body',
      () async {
        final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
        evening[2] = EveningPlan(
          fireAt: DateTime(2026, 9, 1, 20),
          openCount: 3,
        );
        await scheduler.applyPlans(planSet(evening: evening));
        final call = plugin.scheduledCalls.single;
        expect(call.id, eveningNotificationIdBase + 2);
        expect(call.channelId, eveningChannelId);
        expect(call.body, '3 chores still open today');
        expect(call.actionable, isFalse);
        expect(call.payload, isNull);
      },
    );

    test('a single open chore uses the ICU singular', () async {
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[0] = EveningPlan(
        fireAt: DateTime(2026, 8, 30, 20),
        openCount: 1,
        soleOccurrenceId: 'o1',
      );
      await scheduler.applyPlans(planSet(evening: evening));
      expect(plugin.scheduledCalls.single.body, '1 chore still open today');
    });

    test('German locale produces German reminder and evening copy', () async {
      final german = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      final evening = List<EveningPlan?>.filled(eveningHorizonSlots, null);
      evening[0] = EveningPlan(
        fireAt: DateTime(2026, 8, 30, 20),
        openCount: 2,
      );
      await german.applyPlans(
        planSet(
          reminders: onlyReminderZero(
            fireAt: DateTime(2026, 8, 30, 18),
            dueDate: PlainDate(2026, 8, 30),
          ),
          evening: evening,
        ),
      );
      expect(plugin.pending[reminderNotificationIdBase]!.body, 'Heute fällig');
      expect(
        plugin.pending[reminderNotificationIdBase]!.channelName,
        'Aufgaben-Erinnerungen',
      );
      expect(
        plugin.pending[eveningNotificationIdBase]!.body,
        '2 Aufgaben sind heute noch offen',
      );
    });

    test(
      'a null entry CANCELS its id rather than scheduling it, across all '
      'three ranges',
      () async {
        await scheduler.applyPlans(planSet());
        expect(plugin.scheduledCalls, isEmpty);
        expect(
          plugin.cancelCallCount,
          digestHorizonSlots + reminderCeiling + eveningHorizonSlots,
        );
      },
    );

    test('rejects a plan set whose lists are the wrong length', () {
      expect(
        () => scheduler.applyPlans(
          NotificationPlanSet(
            digest: const [],
            reminders: List<ReminderPlan?>.filled(reminderCeiling, null),
            evening: List<EveningPlan?>.filled(eveningHorizonSlots, null),
            reminderOverflowCount: 0,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => scheduler.applyPlans(
          NotificationPlanSet(
            digest: List<DigestPlan?>.filled(digestHorizonSlots, null),
            reminders: const [],
            evening: List<EveningPlan?>.filled(eveningHorizonSlots, null),
            reminderOverflowCount: 0,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => scheduler.applyPlans(
          NotificationPlanSet(
            digest: List<DigestPlan?>.filled(digestHorizonSlots, null),
            reminders: List<ReminderPlan?>.filled(reminderCeiling, null),
            evening: const [],
            reminderOverflowCount: 0,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
