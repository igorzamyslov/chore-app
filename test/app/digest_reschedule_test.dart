import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
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
    addTearDown(container.dispose);
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

    await database.close();
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
      addTearDown(container.dispose);
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
      // occurrence counted.
      await tester.pump(const Duration(milliseconds: 450));
      expect(plugin.scheduledCalls, hasLength(1));
      expect(plugin.scheduledCalls.single.body, contains('1'));

      await database.close();
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
    addTearDown(container.dispose);
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

    expect(
      plugin.scheduledCalls,
      hasLength(1),
      reason: 'the burst must collapse into a single reschedule call',
    );
    expect(plugin.scheduledCalls.single.body, contains('2'));

    await database.close();
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
    addTearDown(container.dispose);
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
    expect(plugin.scheduledCalls, hasLength(1));

    final cancelCountBefore = plugin.cancelCallCount;
    await container
        .read(settingsRepositoryProvider)
        .setDigestEnabled(enabled: false);
    await tester.pump(digestRescheduleDebounce);

    expect(plugin.cancelCallCount, greaterThan(cancelCountBefore));
    // No further schedule call after disabling.
    expect(plugin.scheduledCalls, hasLength(1));

    await database.close();
  });
}
