/// Regression test for a live-repro'd bug (2026-08-01): `syncEngineProvider`
/// used to `ref.watch(settingsProvider)` UNSCOPED, so its own started
/// engine's `pullSince` (which unconditionally writes
/// `settings.syncLastPulledAt` on every successful pull) fed back into a
/// rebuild of `syncEngineProvider` itself -- tearing down the just-started
/// engine (cancelling its debounce `Timer` and subscriptions) and replacing
/// it with a fresh one whose `start()` immediately pulled again, an
/// infinite restart loop that never let a debounced push survive long
/// enough to fire. Fixed by narrowing the watch to
/// `settingsProvider.select((s) => s.valueOrNull?.syncHouseholdId)`.
///
/// Also covers the A5 auth gate (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A5): `syncEngineProvider` must
/// stay [NoopSyncEngine] while signed out, even on an otherwise-linked
/// device -- see the second test below.
///
/// Exercises the REAL provider chain (`syncEngineProvider`,
/// `syncEngineControllerProvider`, `main.dart`'s activation order) rather
/// than constructing `SupabaseSyncEngine` directly -- the bug lived
/// entirely in the provider wiring, not in the engine class itself (which
/// is why `test/application/sync_engine_test.dart` never caught it).
/// `syncTransportProvider` is the override hook that makes this possible:
/// it lets a fake transport reach `syncEngineProvider`'s own "Supabase
/// configured?" branch without needing `supabaseConfigured` (a compile-time
/// constant baked from empty dart-defines in every test run) to be true.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_sync_transport.dart';
import '../features/settings/fake_auth_gateway.dart';

/// Mirrors `test/app/digest_reschedule_test.dart`'s `_awaitBootstrap` --
/// see its doc comment for why a bare `await
/// container.read(bootstrapProvider.future)` deadlocks under `flutter
/// test`'s fake clock, and why the poll below uses a *nonzero* pump
/// duration.
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

/// Polls until `syncEngineProvider` has reacted to the linked state (i.e.
/// `settingsProvider`'s underlying drift stream has emitted the
/// `setSyncLinked` write and `syncEngineProvider` rebuilt from
/// [NoopSyncEngine] to a real, started engine) -- same shape as
/// [_awaitBootstrap], for the same reason.
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

void main() {
  setUpAll(() {
    // Every test below opens its own fresh in-memory AppDatabase, so
    // drift's "multiple database instances" warning (aimed at accidental
    // duplicate app databases sharing one executor) doesn't apply here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets(
    'linking a device through the REAL provider chain starts a real '
    'engine whose debounced push survives long enough to reach the '
    'transport (regression: syncEngineProvider used to churn on every '
    "pull's own settings write and never let the debounce survive)",
    // IMPORTANT if this test ever goes red: against the pre-fix code this
    // doesn't fail a clean assertion -- it HANGS, and the explicit
    // `timeout` below does NOT reliably preempt it. `settingsProvider`'s
    // unscoped watch turns every successful pull's own
    // `syncLastPulledAt` write into another `syncEngineProvider` rebuild,
    // which starts a new engine that pulls again -- forever, with no
    // `Timer`/elapsed virtual time anywhere in the cycle, so the
    // microtask queue never drains. Verified empirically (twice) by
    // reverting the `.select()` fix below: the flutter_tester process
    // pegs a CPU core, `package:test`'s own ~90s default watchdog
    // eventually reports "did not complete", but the process itself
    // keeps spinning after that and needs a manual `pkill
    // flutter_tester` -- this project's own documented "hung flutter
    // test" deadlock class (see the chore-app-conventions memory / CI
    // lore). If this test ever hangs, that IS the regression signal --
    // don't wait on it, kill the process and re-check
    // `syncEngineProvider`'s watch scope first.
    timeout: const Timeout(Duration(seconds: 20)),
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final transport = FakeSyncTransport();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock.fixed(DateTime.utc(2026))),
          syncTransportProvider.overrideWithValue(transport),
          // The A5 gate (spec docs/feedback/2026-08-01-ux-audit.md) also
          // requires a signed-in user -- this test is about the debounce/
          // churn regression, not the auth gate, so it signs in up front
          // (see the second test below for the auth gate itself).
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // bootstrapProvider no longer creates a household (spec
      // docs/specs/onboarding-v2.md §2) -- seed one directly so
      // _awaitBootstrap below actually resolves instead of erroring.
      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');

      // Mirrors main.dart's activation order: read the controller before
      // anything links, exactly like the app does before runApp.
      container.read(syncEngineControllerProvider);
      final householdId = await _awaitBootstrap(tester, container);

      // Unlinked so far: still the inert engine.
      expect(container.read(syncEngineProvider), isA<NoopSyncEngine>());

      await container
          .read(settingsRepositoryProvider)
          .setSyncLinked(
            householdId: householdId,
            linkedAt: container.read(clockProvider).now(),
          );
      await _awaitLinkedEngine(tester, container);

      // A real repository write while linked -- this is what the
      // write-listener (`db.tableUpdates`) should schedule a debounced
      // push for.
      await container
          .read(shoppingRepositoryProvider)
          .addItem(householdId, name: 'Milk');

      // Advance well past the engine's default ~2s debounce. Under the
      // bug, `syncEngineProvider` kept rebuilding (tearing down whichever
      // engine instance's Timer this write armed) every time a pull wrote
      // `settings.syncLastPulledAt`, so no amount of pumping ever let a
      // push survive to fire.
      await tester.pump(const Duration(seconds: 5));

      expect(
        transport.pushedTables,
        contains('shopping_items'),
        reason:
            'the debounced push never reached the transport -- the '
            'syncEngineProvider rebuild-churn bug is back',
      );
      expect(
        transport.serverRows['shopping_items']!.any(
          (row) => row['name'] == 'Milk',
        ),
        isTrue,
      );

      // Stop the engine INSIDE the test body: this test starts a REAL one,
      // which since spec `docs/specs/sync-freshness.md` §2.2 owns a
      // periodic safety-net poll `Timer`, and `flutter_test` asserts "no
      // Timer still pending" as soon as the body returns — too early for
      // the `addTearDown(container.dispose)` above to have run.
      //
      // `stop()`, not `container.dispose()`: disposing the whole graph here
      // cancels the drift stream subscriptions that `database.close()`
      // below then waits on, and that await never completes under
      // `flutter test`'s fake clock (this project's documented
      // bare-await-deadlock class). Stopping just the engine cancels its
      // timers and subscriptions and nothing else.
      container.read(syncEngineProvider).stop();

      await database.close();
    },
  );

  testWidgets('syncEngineProvider stays Noop when signed out, even on an '
      'otherwise-linked device (spec docs/feedback/2026-08-01-ux-audit.md '
      'A5)', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final transport = FakeSyncTransport();
    final authGateway = FakeAuthGateway(); // signed out
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime.utc(2026))),
        syncTransportProvider.overrideWithValue(transport),
        authGatewayProvider.overrideWithValue(authGateway),
      ],
    );
    addTearDown(container.dispose);
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly so
    // _awaitBootstrap below actually resolves instead of erroring.
    await container
        .read(householdRepositoryProvider)
        .createLocalHousehold('Me');

    container.read(syncEngineControllerProvider);
    final householdId = await _awaitBootstrap(tester, container);

    await container
        .read(settingsRepositoryProvider)
        .setSyncLinked(
          householdId: householdId,
          linkedAt: container.read(clockProvider).now(),
        );
    // Give the linked-state write every chance to propagate.
    await tester.pump(const Duration(seconds: 1));

    expect(
      container.read(syncEngineProvider),
      isA<NoopSyncEngine>(),
      reason:
          'linked but signed out must still resolve to the inert '
          'engine -- gating on linked state alone is exactly the bug '
          'A5 fixes',
    );

    // Signing in now flips it to a real, started engine.
    authGateway.signIn(const AuthUser(id: 'u1', email: 'me@example.com'));
    await _awaitLinkedEngine(tester, container);

    // Signing back out flips it right back to Noop.
    await authGateway.signOut();
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(syncEngineProvider), isA<NoopSyncEngine>());

    await database.close();
  });
}
