import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';
import '../features/settings/fake_auth_gateway.dart';

/// A [FakeDigestNotificationPlugin] that pauses the FIRST [zonedSchedule]
/// call for [pauseOnId] until [release] is called, then behaves normally
/// forever after (the guard is one-shot, keyed off having paused once, not
/// off the id, so a *later* recompute's call for the same id never pauses
/// again).
///
/// Used only by the FIX A serialization test below, to hold one recompute
/// mid-loop (after it has already written some slots but before it writes
/// the rest) while a second recompute is triggered — the same shape as the
/// bug it regression-tests: `applyDigestPlans` awaits one sequential
/// platform-channel call per horizon slot, and every `await` yields the
/// isolate.
class _PausingPlugin extends FakeDigestNotificationPlugin {
  _PausingPlugin({required this.pauseOnId});

  /// The notification id whose first [zonedSchedule] call blocks.
  final int pauseOnId;

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
    if (id == pauseOnId && !_hasPaused) {
      _hasPaused = true;
      await _gate.future;
    }
    await super.zonedSchedule(id: id, title: title, body: body, fireAt: fireAt);
  }
}

/// [DigestRescheduleController] tests (spec `docs/specs/notifications.md`
/// testing section): reschedule-on-mutation, debounce, cancel-on-disable —
/// exercised through the real controller + real `SettingsRepository` +
/// real `ChoreService` against an in-memory database, with only the
/// bottom-most OS-facing plugin faked.
///
/// These deliberately don't pump any widget: `testWidgets`'s fake clock
/// (which is what makes `tester.pump(duration)` advance a real `Timer`
/// deterministically) applies to the whole test body regardless of
/// whether a widget tree is ever built, so a bare [ProviderContainer]
/// suffices and keeps this decoupled from `ChoreApp`/`AppShell` entirely —
/// see `DigestRescheduleController`'s doc comment for why that separation
/// matters.
///
/// A bare `await container.read(someProvider.future)` deadlocks under
/// `flutter test`'s fake clock (nothing ever drives it forward without a
/// widget tree scheduling frames), so [_awaitBootstrap] instead polls via
/// repeated zero-duration `tester.pump()` calls, each of which nudges the
/// fake-async zone enough to let the underlying database Future chain make
/// progress.
Future<String> _awaitBootstrap(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var i = 0; i < 400; i++) {
    final value = container.read(bootstrapProvider);
    if (value.hasValue) {
      return value.requireValue;
    }
    if (value.hasError) {
      throw StateError('bootstrapProvider failed: ${value.error}');
    }
    // A *nonzero* duration matters here: a zero-duration `pump()` never
    // gives the underlying database Future chain a chance to make
    // progress under `flutter test`'s fake clock (confirmed empirically —
    // it just spins until this loop gives up).
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('bootstrapProvider never resolved');
}

/// Disposes [container], then closes [database].
///
/// `container.dispose()` cancels every active drift `.watch()` stream this
/// container is still subscribed to (here, `pendingOccurrencesProvider` and
/// `settingsProvider`, both watched by `DigestRescheduleController`); that
/// cancellation's bookkeeping is itself scheduled the same way drift
/// schedules any other stream re-fetch, which under `flutter_test`'s fake
/// clock only ever runs when something pumps time forward (the same
/// `Timer`-needs-a-pump constraint [_awaitBootstrap] works around). A bare
/// `container.dispose(); await database.close();` — with no
/// pump between them and none after — leaves that cancellation forever
/// unscheduled, and `database.close()` then hangs waiting for the query
/// executor to go idle. A single nonzero pump after `dispose()` (confirmed
/// empirically to be necessary; a zero-duration pump doesn't work, matching
/// [_awaitBootstrap]'s own finding) drives it, and only then does
/// `close()` return.
Future<void> _disposeAndClose(
  WidgetTester tester,
  ProviderContainer container,
  AppDatabase database,
) async {
  container.dispose();
  await tester.pump(const Duration(milliseconds: 5));
  await database.close();
}

void main() {
  setUpAll(() {
    // Every test below opens its own fresh in-memory AppDatabase, so
    // drift's "multiple database instances" warning (aimed at accidental
    // duplicate app databases sharing one executor) doesn't apply here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets('initial bootstrap with nothing due cancels, not schedules', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final plugin = FakeDigestNotificationPlugin();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(
          Clock.fixed(DateTime(2026, 7, 24, 7)),
        ),
        digestNotificationPluginProvider.overrideWithValue(plugin),
      ],
    );
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly so
    // _awaitBootstrap below actually resolves instead of erroring.
    await container
        .read(householdRepositoryProvider)
        .createLocalHousehold('Me');

    container.read(digestRescheduleControllerProvider);
    await _awaitBootstrap(tester, container);
    await tester.pump(digestRescheduleDebounce);

    expect(plugin.scheduledCalls, isEmpty);
    expect(plugin.cancelCallCount, greaterThanOrEqualTo(1));

    await _disposeAndClose(tester, container, database);
  });

  testWidgets(
    'reschedules after a mutation creates a due-today occurrence, debounced',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 7)),
          ),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      );
      // bootstrapProvider no longer creates a household (spec
      // docs/specs/onboarding-v2.md §2) -- seed one directly so
      // _awaitBootstrap below actually resolves instead of erroring.
      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');

      container.read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);
      plugin.scheduledCalls.clear();

      final today = PlainDate.fromDateTime(
        container.read(clockProvider).now(),
      );
      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Water the plants',
            startDate: today,
            assignmentMode: AssignmentMode.anyone,
          );

      // Still within the debounce window: nothing scheduled yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(plugin.scheduledCalls, isEmpty);

      // Past the debounce window: exactly one reschedule, with the fresh
      // occurrence counted. A one-off due today is also overdue on every
      // later horizon day, so the whole horizon has something to say —
      // one recompute now means digestHorizonSlots plugin calls, not one.
      await tester.pump(const Duration(milliseconds: 450));
      expect(plugin.scheduledCalls, hasLength(digestHorizonSlots));
      expect(plugin.pending[digestNotificationIdBase]!.body, '1 chore today');

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets('debounce collapses a burst of mutations into one reschedule', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final plugin = FakeDigestNotificationPlugin();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(
          Clock.fixed(DateTime(2026, 7, 24, 7)),
        ),
        digestNotificationPluginProvider.overrideWithValue(plugin),
      ],
    );
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly so
    // _awaitBootstrap below actually resolves instead of erroring.
    await container
        .read(householdRepositoryProvider)
        .createLocalHousehold('Me');

    container.read(digestRescheduleControllerProvider);
    final householdId = await _awaitBootstrap(tester, container);
    await tester.pump(digestRescheduleDebounce);
    plugin.scheduledCalls.clear();

    final today = PlainDate.fromDateTime(container.read(clockProvider).now());
    final choreService = container.read(choreServiceProvider);

    // Two mutations in quick succession, each well within the debounce
    // window of the previous one.
    await choreService.createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: today,
      assignmentMode: AssignmentMode.anyone,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(plugin.scheduledCalls, isEmpty);

    await choreService.createChore(
      householdId: householdId,
      title: 'Take out the trash',
      startDate: today,
      assignmentMode: AssignmentMode.anyone,
    );

    // Only now does the debounce window (restarted by the second
    // mutation) fully elapse.
    await tester.pump(digestRescheduleDebounce);

    // One recompute call now means digestHorizonSlots plugin calls (both
    // one-offs are overdue on every later horizon day), not one — the
    // count still proves the burst collapsed into a single reschedule
    // rather than two (which would double it).
    expect(
      plugin.scheduledCalls,
      hasLength(digestHorizonSlots),
      reason: 'the burst must collapse into a single reschedule call',
    );
    expect(plugin.pending[digestNotificationIdBase]!.body, '2 chores today');

    await _disposeAndClose(tester, container, database);
  });

  // THE COST OF A LARGER HORIZON, PINNED.
  //
  // The arithmetic these two tests defend (plan §4): one apply is now
  // digestHorizonSlots = 24 sequential platform-channel calls rather than
  // 7, each one channel round trip plus one inexact
  // AlarmManager.setAndAllowWhileIdle. That growth is only acceptable
  // because the work per mutation BURST is bounded twice over — the 500ms
  // digestRescheduleDebounce collapses a burst into one firing, and
  // DigestRescheduleController's depth-1 _inFlightRecompute/_recomputeQueued
  // queue collapses everything arriving mid-run into ONE trailing re-run.
  // Worst case per burst is therefore 2 applies = 48 calls, never one apply
  // per mutation. (Projection cost grows too: ~600 PlainDate steps per
  // schedule-anchored occurrence per recompute, so ~30k steps for 50 of
  // them — single-digit milliseconds, and the reason the horizon stops at
  // 24 slots rather than 60.)
  //
  // Both assertions below are EXACT counts on purpose. An isNotEmpty or
  // greaterThan(0) here would pass whether the debounce and the queue work
  // or not, which is precisely the class of never-failing assertion that
  // makes a cost claim worthless.
  testWidgets(
    'five mutations in one debounce window cost exactly ONE apply, not five',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 7)),
          ),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      );
      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');

      container.read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);
      plugin.scheduledCalls.clear();

      final today = PlainDate.fromDateTime(container.read(clockProvider).now());
      final choreService = container.read(choreServiceProvider);

      // Five mutations, with NO pump between them, so every one of them
      // lands inside a single debounce window.
      for (var i = 0; i < 5; i++) {
        await choreService.createChore(
          householdId: householdId,
          title: 'Chore $i',
          startDate: today,
          assignmentMode: AssignmentMode.anyone,
        );
      }
      expect(
        plugin.scheduledCalls,
        isEmpty,
        reason: 'still inside the debounce window',
      );

      await tester.pump(digestRescheduleDebounce);

      expect(
        plugin.scheduledCalls,
        // Observed empirically: pinning this at 2 * digestHorizonSlots
        // failed with a real count of exactly digestHorizonSlots (24), so
        // this bound is live, not vacuous.
        hasLength(digestHorizonSlots),
        reason:
            'five mutations must cost ONE apply of the whole horizon; five '
            'applies would be 5 * digestHorizonSlots calls',
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'recomputes arriving while an apply is in flight coalesce into ONE '
    'trailing re-run -- a burst costs at most two applies, not one per '
    'trigger',
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = _PausingPlugin(pauseOnId: digestNotificationIdBase + 3);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      // Baseline recompute (no chores yet): every slot is null, so this
      // only ever calls `cancel`, never `zonedSchedule` -- the pause guard
      // stays armed for the apply below.
      await tester.pump(digestRescheduleDebounce);

      final choreService = container.read(choreServiceProvider);
      // This apply pauses mid-horizon, blocked on id 1004.
      await choreService.createChore(
        householdId: householdId,
        title: 'Chore 0',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );
      await tester.pump(digestRescheduleDebounce);

      // Three further recomputes, each fully debounced, all arriving while
      // the first apply is still blocked. Each one finds a recompute in
      // flight and must be coalesced into the SAME single trailing re-run.
      for (var i = 1; i <= 3; i++) {
        await choreService.createChore(
          householdId: householdId,
          title: 'Chore $i',
          startDate: PlainDate(2026, 1, 5),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(1),
        );
        await tester.pump(digestRescheduleDebounce);
      }

      plugin.release();
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pump(digestRescheduleDebounce);

      expect(
        plugin.scheduledCalls.length,
        // Observed empirically: pinning this at digestHorizonSlots failed
        // with a real count of exactly 48 = 2 * digestHorizonSlots, so the
        // bound is tight — the in-flight apply plus ONE trailing re-run,
        // with the three triggers genuinely coalesced.
        lessThanOrEqualTo(2 * digestHorizonSlots),
        reason:
            'the in-flight apply plus exactly one coalesced trailing '
            're-run; one apply per trigger would be 4 * digestHorizonSlots',
      );
      // And it really did re-run: the final horizon carries all four
      // chores, so the trailing re-run used the LATEST counts.
      expect(plugin.pending, hasLength(digestHorizonSlots));
      expect(
        plugin.pending.values.every((call) => call.body == '4 chores today'),
        isTrue,
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets('disabling the digest cancels the scheduled notification', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final plugin = FakeDigestNotificationPlugin();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(
          Clock.fixed(DateTime(2026, 7, 24, 7)),
        ),
        digestNotificationPluginProvider.overrideWithValue(plugin),
      ],
    );
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly so
    // _awaitBootstrap below actually resolves instead of erroring.
    await container
        .read(householdRepositoryProvider)
        .createLocalHousehold('Me');

    container.read(digestRescheduleControllerProvider);
    final householdId = await _awaitBootstrap(tester, container);
    final today = PlainDate.fromDateTime(container.read(clockProvider).now());
    await container
        .read(choreServiceProvider)
        .createChore(
          householdId: householdId,
          title: 'Water the plants',
          startDate: today,
          assignmentMode: AssignmentMode.anyone,
        );
    await tester.pump(digestRescheduleDebounce);
    // A one-off due today is overdue on every later horizon day, so the
    // whole horizon has something to say: digestHorizonSlots plugin calls
    // for this one recompute, not one.
    expect(plugin.scheduledCalls, hasLength(digestHorizonSlots));

    final cancelCountBefore = plugin.cancelCallCount;
    await container
        .read(settingsRepositoryProvider)
        .setDigestEnabled(enabled: false);
    await tester.pump(digestRescheduleDebounce);

    expect(plugin.cancelCallCount, greaterThan(cancelCountBefore));
    // No further schedule call after disabling.
    expect(plugin.scheduledCalls, hasLength(digestHorizonSlots));
    // The direct proof that disabling silences all digestHorizonSlots days,
    // not just that some cancels happened somewhere.
    expect(plugin.pending, isEmpty);

    await _disposeAndClose(tester, container, database);
  });

  testWidgets(
    'THE REGRESSION (audit P0): after the first slot fires, with NO app '
    'interaction at all, a digest is still armed for the following day',
    (tester) async {
      var currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      // Seed before the container exists: DigestRescheduleController's
      // constructor eagerly listens to bootstrapProvider.
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Water the plants',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);

      // The whole horizon is armed up front, one id per slot.
      expect(plugin.pending, hasLength(digestHorizonSlots));
      expect(
        plugin.pending[digestNotificationIdBase]!.fireAt,
        DateTime(2026, 1, 5, 8),
      );
      expect(
        plugin.pending[digestNotificationIdBase + 1]!.fireAt,
        DateTime(2026, 1, 6, 8),
      );

      // The OS delivers today's digest. Then NOTHING happens: no mutation,
      // no resume, no launch — the app is never opened again.
      plugin.deliverDue(DateTime(2026, 1, 5, 8));
      currentTime = DateTime(2026, 1, 6, 7);
      // Captured before the 23h pump, so the assertion below can prove the
      // test's own premise ("no app interaction of any kind") rather than
      // merely being satisfied by some OTHER recompute firing during the
      // pump and coincidentally re-arming the same slot.
      final scheduledCallsBefore = plugin.scheduledCalls.length;
      await tester.pump(const Duration(hours: 23));

      expect(
        plugin.scheduledCalls.length,
        scheduledCallsBefore,
        reason:
            'no app interaction occurred, so no recompute should have run '
            'at all during this pump',
      );
      // Tomorrow's digest is still armed. With a single one-shot id this
      // assertion fails: `pending` is empty here.
      expect(
        plugin.pending.values.map((call) => call.fireAt),
        contains(DateTime(2026, 1, 6, 8)),
        reason: 'the digest must not go silent the day after it fires',
      );
      expect(
        plugin.pending.values.every((call) => call.body == '1 chore today'),
        isTrue,
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'THE REGRESSION (A-1b): the digest survives ~12 weeks unopened, not 8 '
    'days -- with NO app interaction at all, something is still armed two '
    'months out',
    (tester) async {
      // The day-8 analogue of the P0 test above. Under the old flat 7-day
      // horizon the furthest armed slot was 2026-01-11, so the
      // furthest-fireAt assertion below fails against roughly
      // `2026-01-11 08:00` where it expects a date on or after
      // `2026-03-26 08:00`, and `pending` is empty after the 60-day
      // delivery.
      var currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Water the plants',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);

      // A daily chore gives every slot something to say, so the whole
      // horizon is armed.
      expect(plugin.pending, hasLength(digestHorizonSlots));

      // THE POINT OF THIS PLAN: the reach, not the slot count. Asserted
      // against an absolute date rather than a constant-derived one, so
      // this cannot follow a shrinking horizon downwards without failing.
      final furthest = plugin.pending.values
          .map((call) => call.fireAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      expect(
        furthest.isBefore(DateTime(2026, 3, 26, 8)),
        isFalse,
        reason:
            'the furthest armed slot must be at least 80 days out, so an '
            'app left unopened for months still has a digest coming — got '
            '$furthest',
      );

      // The OS delivers everything due in the next 60 days. Then NOTHING
      // happens: no mutation, no resume, no launch.
      plugin.deliverDue(DateTime(2026, 3, 6, 8));
      currentTime = DateTime(2026, 3, 6, 9);
      // Captured before the pump, exactly as the P0 test does, so the
      // assertion below cannot be satisfied by some other recompute
      // quietly re-arming the horizon during it.
      final scheduledCallsBefore = plugin.scheduledCalls.length;
      await tester.pump(const Duration(hours: 1));

      expect(
        plugin.scheduledCalls.length,
        scheduledCallsBefore,
        reason:
            'no app interaction occurred, so no recompute should have run '
            'at all during this pump',
      );
      expect(
        plugin.pending,
        isNotEmpty,
        reason:
            'after 60 unopened days the digest must still have something '
            'armed — this is the whole of A-1b',
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'completing the last chore silences the entire horizon',
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      final service = container.read(choreServiceProvider);
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Call the plumber',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pump(digestRescheduleDebounce);
      expect(plugin.pending, isNotEmpty);

      final pendingOccurrence = await container
          .read(choreRepositoryProvider)
          .pendingOccurrenceOf(chore.id);
      // `completedBy` is a FK to `members`, so it must be a real member id
      // (nullable in the schema, but not in this method's signature) —
      // the household's admin member, same as `actingMemberProvider`
      // resolves to.
      await service.completeOccurrence(
        pendingOccurrence!.id,
        completedBy: container.read(actingMemberProvider)!.id,
      );
      await tester.pump(digestRescheduleDebounce);

      expect(
        plugin.pending,
        isEmpty,
        reason: 'a one-off has no successor, so every day is now silent',
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'FIX A: a recompute paused mid-horizon does not interleave with a '
    'second one triggered while it waits -- the final horizon is entirely '
    'from the LATER counts, with nothing left over from the earlier ones',
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = _PausingPlugin(pauseOnId: digestNotificationIdBase + 3);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      // Baseline recompute (no chores yet): every slot is null, so this
      // only ever calls `cancel`, never `zonedSchedule` -- the pause guard
      // below stays armed for recompute A.
      await tester.pump(digestRescheduleDebounce);

      // Recompute A: one daily chore means every horizon slot's count is 1
      // ("counts X"). Its `applyDigestPlans` call pauses after writing ids
      // 1001-1003, blocked on id 1004.
      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Chore X',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);

      expect(plugin.pending[digestNotificationIdBase]!.body, '1 chore today');
      expect(
        plugin.pending.containsKey(digestNotificationIdBase + 3),
        isFalse,
        reason: 'recompute A is paused before writing this slot',
      );

      // A second mutation lands while A is still paused mid-loop: two
      // daily chores are now due every day ("counts Y"). This triggers a
      // second recompute request.
      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Chore Y',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);

      // Let A's paused call proceed, then give both A's remainder and the
      // queued trailing recompute room to run to completion.
      plugin.release();
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pump(digestRescheduleDebounce);

      // Every one of the digestHorizonSlots ids must show Y's count. If the
      // two recomputes had interleaved (the bug), ids 1004 and up would
      // still show A's stale '1 chore today' -- A resuming after B would
      // overwrite them with counts that were already out of date.
      expect(plugin.pending, hasLength(digestHorizonSlots));
      expect(
        plugin.pending.values.every((call) => call.body == '2 chores today'),
        isTrue,
        reason: 'no slot may be left over from the earlier, stale recompute',
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'FIX 1 (regression): dispose() during a queued trailing recompute must '
    'not let that recompute start afterward -- before the fix it reads '
    'from the disposed container and throws',
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final plugin = _PausingPlugin(pauseOnId: digestNotificationIdBase + 3);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      // Baseline recompute (no chores yet): every slot is null, so this
      // only ever calls `cancel`, never `zonedSchedule` -- the pause guard
      // below stays armed for recompute A.
      await tester.pump(digestRescheduleDebounce);

      // Recompute A pauses mid-horizon, same shape as the FIX A test above.
      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Chore X',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);
      expect(
        plugin.pending.containsKey(digestNotificationIdBase + 3),
        isFalse,
        reason: 'recompute A is paused before writing this slot',
      );

      // A second mutation lands while A is still paused mid-loop: this
      // triggers a second recompute request, which finds A in flight and
      // is recorded as a queued trailing re-run (`_recomputeQueued`).
      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Chore Y',
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.anyone,
            recurrence: Recurrence.everyNDays(1),
          );
      await tester.pump(digestRescheduleDebounce);

      // Dispose the container -- via `ref.onDispose`, this calls the
      // controller's own `dispose()` -- while A is still paused mid-flight
      // AND a trailing recompute is queued behind it. This is the exact
      // shape of the regression: before the fix, `dispose()` only
      // cancelled `_debounceTimer`, which is not the path the queued
      // re-run takes.
      container.dispose();
      await tester.pump(const Duration(milliseconds: 5));

      // Let A's paused call proceed. Before the fix, A's `whenComplete`
      // callback then sees the still-set `_recomputeQueued` flag and calls
      // `_startRecompute()` again, which reads from `_ref` -- a container
      // that is now disposed -- and throws "Bad state: Tried to read a
      // provider from a ProviderContainer that was already disposed".
      // That throw happens inside an unawaited Future chain, so it
      // surfaces as an uncaught async error and fails this test. After the
      // fix, `dispose()` clears the queued flag and the re-run path
      // early-returns, so nothing of the sort happens.
      plugin.release();
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pump(digestRescheduleDebounce);

      // The container is already disposed above (that's the whole point
      // of this test) -- only the database still needs closing.
      await database.close();
    },
  );

  testWidgets(
    "a partner's fixed chore does not appear in this device's digest (T2.3)",
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      final householdRepo = HouseholdRepository(database);
      final household = await householdRepo.createLocalHousehold('Me');
      // `createLocalHousehold` already inserted an admin member named 'Me',
      // which is what `actingMemberProvider` resolves to.
      final partner = await householdRepo.addMember(
        household.id,
        name: 'Partner',
        color: 0xFF445566,
      );
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: "Partner's chore",
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.fixed,
            assigneeMemberIds: [partner.id],
          );
      await tester.pump(digestRescheduleDebounce);

      // The acting member resolves to the household's first/admin member —
      // not the partner — so this device's digest has nothing to say.
      expect(container.read(actingMemberProvider)!.id, isNot(partner.id));
      expect(plugin.pending, isEmpty);

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets(
    'the digest scopes to the CLAIMED member in PINNED mode, not to the '
    "household's first admin (FIX 5: the T2.3 scoping test above never "
    'exercises pinned mode — this composes P0 scoping with T1.3 pinning)',
    (tester) async {
      final currentTime = DateTime(2026, 1, 5, 7);
      final database = AppDatabase(NativeDatabase.memory());
      final householdRepo = HouseholdRepository(database);
      final household = await householdRepo.createLocalHousehold('Me');
      // `createLocalHousehold` makes 'Me' the admin. Promote 'Anna' to
      // admin and demote 'Me' to an ordinary member, so the OLD
      // first-admin fallback and the NEW claim-based resolution disagree
      // on who the recipient is -- the only way this test can tell them
      // apart.
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();
      final anna = await householdRepo.addMember(
        household.id,
        name: 'Anna',
        color: 0xFF445566,
        role: MemberRole.admin,
      );
      await householdRepo.setMemberRole(me.id, MemberRole.member);

      const user = AuthUser(id: 'u-1', email: 'me@example.com');
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          digestNotificationPluginProvider.overrideWithValue(plugin),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(currentUser: user),
          ),
        ],
      )..read(digestRescheduleControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);
      await tester.pump(digestRescheduleDebounce);

      // Link and claim 'Me' -- mirrors what `HouseholdLinkService.adopt`
      // now does (spec `docs/specs/household-lifecycle.md` §3.1 G-B).
      await householdRepo.setMemberUserId(me.id, user.id);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: currentTime);
      await tester.pump(digestRescheduleDebounce);

      // Confirm the composed state this test actually exercises: pinned,
      // and resolved via the claim to 'Me' -- the household's first ADMIN
      // is Anna, so this assertion would fail under the old fallback.
      expect(
        container.read(memberIdentityModeProvider),
        MemberIdentityMode.pinned,
      );
      expect(container.read(actingMemberProvider)!.id, me.id);

      // Anna's fixed chore must not appear in THIS device's digest: the
      // claimed recipient is 'Me', not Anna, even though Anna is the
      // admin the old fallback would have picked.
      await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: "Anna's chore",
            startDate: PlainDate(2026, 1, 5),
            assignmentMode: AssignmentMode.fixed,
            assigneeMemberIds: [anna.id],
          );
      await tester.pump(digestRescheduleDebounce);

      expect(plugin.pending, isEmpty);

      await _disposeAndClose(tester, container, database);
    },
  );
}
