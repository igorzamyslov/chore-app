import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';

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
      // one recompute now means digestHorizonDays plugin calls, not one.
      await tester.pump(const Duration(milliseconds: 450));
      expect(plugin.scheduledCalls, hasLength(digestHorizonDays));
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

    // One recompute call now means digestHorizonDays plugin calls (both
    // one-offs are overdue on every later horizon day), not one — the
    // count still proves the burst collapsed into a single reschedule
    // rather than two (which would double it).
    expect(
      plugin.scheduledCalls,
      hasLength(digestHorizonDays),
      reason: 'the burst must collapse into a single reschedule call',
    );
    expect(plugin.pending[digestNotificationIdBase]!.body, '2 chores today');

    await _disposeAndClose(tester, container, database);
  });

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
    // whole horizon has something to say: digestHorizonDays plugin calls
    // for this one recompute, not one.
    expect(plugin.scheduledCalls, hasLength(digestHorizonDays));

    final cancelCountBefore = plugin.cancelCallCount;
    await container
        .read(settingsRepositoryProvider)
        .setDigestEnabled(enabled: false);
    await tester.pump(digestRescheduleDebounce);

    expect(plugin.cancelCallCount, greaterThan(cancelCountBefore));
    // No further schedule call after disabling.
    expect(plugin.scheduledCalls, hasLength(digestHorizonDays));

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

      // The whole horizon is armed up front, one id per calendar day.
      expect(plugin.pending, hasLength(digestHorizonDays));
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
      await tester.pump(const Duration(hours: 23));

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
}
