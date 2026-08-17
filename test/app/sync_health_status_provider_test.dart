/// `syncHealthStatusProvider` tests (spec
/// `docs/specs/sync-freshness.md` §2.5): proves the full wiring from real
/// settings/repository data to `SyncHealthStatus`, for BOTH independent
/// signals `computeSyncHealth` combines (pull-cursor staleness, and
/// dirty-row duration), plus the observing-since floor that keeps a cold
/// start or a resume from flashing the banner.
///
/// The threshold matrix itself is already covered in isolation by
/// `test/domain/sync_health_test.dart`; this file only proves the PROVIDER
/// reads the right real inputs.
///
/// Same bare-`ProviderContainer` + real-DB + `FakeSyncTransport` technique
/// as `test/app/sync_engine_provider_test.dart`. Uses a MUTABLE clock
/// (`Clock(() => currentTime)`, not `Clock.fixed`) so time can be advanced
/// explicitly -- mirrors `test/app/day_change_catchup_test.dart`'s
/// documented approach. `syncHealthStatusProvider` is a plain (non-stream)
/// `Provider`, so after advancing `currentTime` this file calls
/// `container.invalidate(syncHealthStatusProvider)` before re-reading it --
/// standing in for the 60s self-invalidating tick the provider arms in
/// production (spec §2.5's recomputation bullet), which cannot be waited out
/// under `flutter_test`'s fake clock without pumping a full minute.
///
/// Every test that reaches the linked branch disposes its container INSIDE
/// the test body, not only via `addTearDown`: that branch arms the recheck
/// `Timer`, and flutter_test's "a Timer is still pending" check runs before
/// registered tear-downs.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/sync_health.dart';
import 'package:clock/clock.dart';
// `isNull` here would collide with matcher's -- drift is only needed for
// `driftRuntimeOptions`.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_sync_transport.dart';
import '../features/settings/fake_auth_gateway.dart';

/// A [FakeSyncTransport] whose [serverNow] always throws -- simulates a pull
/// that can never complete, so `syncLastPulledAt` is never written and the
/// pull reference stays `syncLinkedAt`/`syncObservingSince`.
class _AlwaysFailingPullTransport extends FakeSyncTransport {
  @override
  Future<DateTime> serverNow() async {
    throw Exception('simulated total pull outage');
  }
}

/// Mirrors `test/app/sync_engine_provider_test.dart`'s helper of the same
/// name -- see its doc comment for why a bare
/// `await container.read(bootstrapProvider.future)` deadlocks under
/// `flutter test`.
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
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('bootstrapProvider never resolved');
}

/// Mirrors `test/app/sync_engine_provider_test.dart`'s helper of the same
/// name.
Future<void> _awaitLinkedEngine(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var i = 0; i < 400; i++) {
    if (container.read(syncEngineProvider) is SupabaseSyncEngine) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('syncEngineProvider never switched to a real engine');
}

/// Tears down a container that reached the linked branch: stops the engine
/// (its poll/debounce timers) and disposes the container (the health
/// provider's recheck timer) before the database closes, then gives drift's
/// stream cleanup a pump to drain.
Future<void> _shutDown(
  WidgetTester tester,
  ProviderContainer container,
  AppDatabase database,
) async {
  container.read(syncEngineProvider).stop();
  container.dispose();
  await tester.pump(const Duration(milliseconds: 50));
  await database.close();
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets('healthy while unlinked, regardless of the clock', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    expect(container.read(syncHealthStatusProvider), SyncHealthStatus.healthy);
    expect(
      container.read(syncObservingSinceProvider),
      isNull,
      reason: 'nothing to observe on an unlinked device',
    );

    await database.close();
  });

  testWidgets(
    'unhealthy once the pull cursor is older than the grace period, using '
    'the link/observing time as the reference before the first pull ever '
    'completes',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      var currentTime = DateTime.utc(2026, 8, 11, 8);
      final transport = _AlwaysFailingPullTransport();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          syncTransportProvider.overrideWithValue(transport),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');
      container.read(syncEngineControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);

      await container
          .read(settingsRepositoryProvider)
          .setSyncLinked(householdId: householdId, linkedAt: currentTime);
      await _awaitLinkedEngine(tester, container);
      // Let the engine's start-time push/pull settle, so the initial
      // dirty flags from createLocalHousehold are cleared and the
      // starting health state is deterministic.
      await tester.pump(const Duration(seconds: 1));

      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.healthy,
        reason: 'just linked -- still inside the grace period',
      );

      currentTime = currentTime.add(const Duration(minutes: 6));
      container.invalidate(syncHealthStatusProvider);
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.unhealthy,
      );

      await _shutDown(tester, container, database);
    },
  );

  testWidgets(
    'an app resume re-arms the grace period: a cursor that is only stale '
    'because the app was away does not flag the device',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      var currentTime = DateTime.utc(2026, 8, 11, 8);
      final transport = _AlwaysFailingPullTransport();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          syncTransportProvider.overrideWithValue(transport),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');
      final controller = container.read(syncEngineControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);

      await container
          .read(settingsRepositoryProvider)
          .setSyncLinked(householdId: householdId, linkedAt: currentTime);
      await _awaitLinkedEngine(tester, container);
      // Let the engine's start-time push/pull settle, so the initial
      // dirty flags from createLocalHousehold are cleared and the
      // starting health state is deterministic.
      await tester.pump(const Duration(seconds: 1));
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.healthy,
      );

      // Three hours backgrounded: the cursor is genuinely ancient, and
      // nothing this device did caused that.
      currentTime = currentTime.add(const Duration(hours: 3));
      container.invalidate(syncHealthStatusProvider);
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.unhealthy,
        reason:
            'without a resume the ancient cursor is exactly what the '
            'indicator is for -- this is the state the resume must clear',
      );

      controller.triggerOnResume();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.healthy,
        reason:
            'the resume is this session first chance to reach the '
            'household; it gets the full grace period before being flagged',
      );

      // ...and the resumed session can itself go stale.
      currentTime = currentTime.add(const Duration(minutes: 6));
      container.invalidate(syncHealthStatusProvider);
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.unhealthy,
      );

      await _shutDown(tester, container, database);
    },
  );

  testWidgets(
    'unhealthy once a synced row has been dirty for longer than the grace '
    'period, and heals once it is pushed',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      var currentTime = DateTime.utc(2026, 8, 11, 8);
      final transport = FakeSyncTransport();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock(() => currentTime)),
          syncTransportProvider.overrideWithValue(transport),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');
      container.read(syncEngineControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);

      await container
          .read(settingsRepositoryProvider)
          .setSyncLinked(householdId: householdId, linkedAt: currentTime);
      await _awaitLinkedEngine(tester, container);
      // Let the engine's start-time push/pull settle, so the initial
      // dirty flags from createLocalHousehold are cleared and the
      // starting health state is deterministic.
      await tester.pump(const Duration(seconds: 1));

      transport.beforeUpsert = () async {
        throw Exception('simulated permanent push failure');
      };
      await container
          .read(shoppingRepositoryProvider)
          .addItem(householdId, name: 'Milk');
      // Let the debounced push attempt (and fail) -- 5s against the engine's
      // default 2s debounce, matching the proven-safe margin
      // `test/app/sync_engine_provider_test.dart` already uses.
      await tester.pump(const Duration(seconds: 5));
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.healthy,
        reason: 'freshly dirty -- still inside the grace period',
      );

      currentTime = currentTime.add(const Duration(minutes: 4));
      container.invalidate(syncHealthStatusProvider);
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.unhealthy,
        reason:
            'pulls are irrelevant here: this is the asymmetric push-only '
            'failure only the dirty-duration signal can see',
      );

      // Recovery: let the push succeed. `transport.now` is the FAKE SERVER's
      // own clock (defaults to 2026-01-01, independent of this test's
      // `currentTime`) -- it stamps `updated_at` on every pushed row and is
      // what the following pull's `serverNow()` returns, so it must be
      // brought up to `currentTime` first. Otherwise the pull below would
      // set `syncLastPulledAt` to the fake's stale default.
      transport.now = currentTime;
      transport.beforeUpsert = null;
      await container.read(syncEngineProvider).pushDirty();
      await tester.pump(const Duration(milliseconds: 50));
      container.invalidate(syncHealthStatusProvider);
      expect(
        container.read(syncHealthStatusProvider),
        SyncHealthStatus.healthy,
      );

      await _shutDown(tester, container, database);
    },
  );
}
