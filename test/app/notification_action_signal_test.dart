/// [NotificationActionSignalController] tests (spec
/// `docs/specs/notifications.md` N2, backlog F-1): the receiving half of the
/// background isolate's cross-isolate ping.
///
/// Testable at all only because `IsolateNameServer` is a same-process,
/// same-VM registry, so a test can look up the port the controller registered
/// and `send()` to it directly — no real isolate spawn, no plugin.
///
/// Mirrors `test/app/digest_reschedule_test.dart`'s `ProviderContainer` +
/// `_awaitBootstrap` + `tester.pump(digestRescheduleDebounce)` pattern; read
/// that file's header comment for why `_awaitBootstrap` polls instead of
/// awaiting and why a nonzero pump sits between `dispose()` and `close()`.
///
/// **The trap in this file, called out so nobody "simplifies" it away.** A
/// change made through the container's OWN database connection recomputes the
/// digest on its own — `DigestRescheduleController` already listens to
/// `pendingOccurrencesProvider` — so a test that mutates through the container
/// and then pings proves NOTHING about the ping. The ping test below therefore
/// asserts a recompute count in a window it has first proved to be quiet, and
/// its own comment states exactly how much that does and does not establish.
library;

import 'dart:ui';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/notification_action_handler.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';
import '../features/settings/fake_auth_gateway.dart';

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
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDown(() {
    // Belt and braces: a mapping leaked by a failing test would break the
    // NEXT test's registration, which is a confusing way to fail.
    IsolateNameServer.removePortNameMapping(notificationActionPortName);
  });

  testWidgets('registers its port at construction and removes the mapping on '
      'dispose', (tester) async {
    expect(
      IsolateNameServer.lookupPortByName(notificationActionPortName),
      isNull,
      reason: 'nothing may be registered before the controller exists',
    );

    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 7))),
        digestNotificationPluginProvider.overrideWithValue(
          FakeDigestNotificationPlugin(),
        ),
        authGatewayProvider.overrideWithValue(FakeAuthGateway()),
      ],
    )..read(notificationActionSignalControllerProvider);
    expect(
      IsolateNameServer.lookupPortByName(notificationActionPortName),
      isNotNull,
    );

    await _disposeAndClose(tester, container, database);

    // Asserted deliberately: without the removal, a leaked mapping survives
    // the container and silently breaks the next registration -- including a
    // hot restart's, which is why the constructor removes before it registers.
    expect(
      IsolateNameServer.lookupPortByName(notificationActionPortName),
      isNull,
    );
  });

  testWidgets('registration survives a second controller over the same name '
      '(the hot-restart case)', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    ProviderContainer newContainer() => ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 7))),
        digestNotificationPluginProvider.overrideWithValue(
          FakeDigestNotificationPlugin(),
        ),
        authGatewayProvider.overrideWithValue(FakeAuthGateway()),
      ],
    );

    final first = newContainer()
      ..read(notificationActionSignalControllerProvider);
    // A hot restart leaves the old mapping behind WITHOUT disposing the old
    // container, so the second registration has to displace it rather than
    // fail. Deliberately not disposing `first` here, to reproduce that.
    final second = newContainer();
    expect(
      () => second.read(notificationActionSignalControllerProvider),
      returnsNormally,
    );
    expect(
      IsolateNameServer.lookupPortByName(notificationActionPortName),
      isNotNull,
    );

    first.dispose();
    await _disposeAndClose(tester, second, database);
  });

  testWidgets(
    'a ping causes a digest recompute that nothing else in the window would '
    'have caused',
    (tester) async {
      // SCOPE, stated plainly: this covers the ping WIRING -- port ->
      // controller -> recompute -- and nothing more. It does NOT demonstrate
      // the cross-connection invisibility the invalidates exist for.
      //
      // Why not: reproducing that needs a genuinely separate AppDatabase over
      // the same file, and an on-disk drift database inside `testWidgets`'
      // fake-async zone hangs the suite (the same Timer-needs-a-pump
      // constraint `_awaitBootstrap` works around, applied to real file I/O
      // that nothing pumps). An earlier revision of this test did exactly that
      // and had to be abandoned after it wedged a CI run past ten minutes.
      //
      // What DOES cover the rest:
      // - that `applyDoneAction` through a second AppDatabase completes and
      //   rotates correctly, and that `rewriteDigestHorizon` then silences the
      //   stale slots: `test/application/notification_action_processor_test.dart`;
      // - that a background write is invisible to the main isolate's streams
      //   until invalidated, on a real device: the GATE items in
      //   `docs/plans/2026-08-08-notification-actions.md` Task 10. UNVERIFIED
      //   by any automated test in this repo.
      //
      // The non-vacuity guard is the "nothing spontaneous" assertion below.
      // Without it, ANY recompute for any reason would satisfy this test --
      // and with a 24-slot horizon even `scheduledCalls.isNotEmpty` passes off
      // the bootstrap recompute alone.
      final database = AppDatabase(NativeDatabase.memory());
      final plugin = FakeDigestNotificationPlugin();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 7)),
          ),
          digestNotificationPluginProvider.overrideWithValue(plugin),
          authGatewayProvider.overrideWithValue(FakeAuthGateway()),
        ],
      );
      await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');

      // Both, exactly as main.dart does before runApp.
      container
        ..read(digestRescheduleControllerProvider)
        ..read(notificationActionSignalControllerProvider);
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
      // Let every bootstrap/mutation trigger drain completely.
      for (var i = 0; i < 4; i++) {
        await tester.pump(digestRescheduleDebounce);
      }
      expect(
        plugin.pending[digestNotificationIdBase]!.body,
        '1 chore today',
        reason:
            'the horizon must be armed before the ping, or the count '
            'assertion below cannot mean anything',
      );

      plugin.scheduledCalls.clear();
      await tester.pump(digestRescheduleDebounce);
      expect(
        plugin.scheduledCalls,
        isEmpty,
        reason:
            'NOTHING may recompute spontaneously in this window -- this is '
            'what makes the post-ping count below attributable to the ping',
      );

      // Exactly what the background isolate sends -- but inside `runAsync`,
      // which is load-bearing and cost a CI cycle to learn. A `SendPort`
      // message to a same-isolate `ReceivePort` is delivered by the VM's own
      // MESSAGE loop, not by the Dart event loop `FakeAsync` controls, and
      // `tester.pump()` only advances fake time. Sending from a plain
      // `testWidgets` body therefore queues a message that is never delivered
      // at all, and every assertion below then fails for a reason that has
      // nothing to do with this controller. The real delay is generous enough
      // to cover the debounce whether the handler's `Timer` lands in the fake
      // zone (its `listen` was registered there) or in the real one.
      await tester.runAsync(() async {
        IsolateNameServer.lookupPortByName(
          notificationActionPortName,
        )!.send(null);
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      // Pumped repeatedly rather than once: the recompute the handler fires
      // directly may read pre-invalidation data -- the invalidated provider is
      // briefly back in its loading state, which `_recompute` bails out of --
      // so the recompute that MATTERS is the one the freshly re-emitting stream
      // drives behind it. See NotificationActionSignalController._onPing.
      for (var i = 0; i < 6; i++) {
        await tester.pump(digestRescheduleDebounce);
      }

      expect(
        plugin.scheduledCalls,
        hasLength(greaterThanOrEqualTo(1)),
        reason: 'the ping must reach DigestRescheduleController',
      );
      expect(
        plugin.pending[digestNotificationIdBase]!.body,
        '1 chore today',
        reason:
            'the recompute reads the same unchanged data, so the horizon '
            'must come back identical rather than empty -- a ping must never '
            'silence a digest that still has something to say',
      );

      await _disposeAndClose(tester, container, database);
    },
  );

  testWidgets('a ping with nothing listening does not throw -- the '
      'app-not-running path the isolate relies on', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 7))),
        digestNotificationPluginProvider.overrideWithValue(
          FakeDigestNotificationPlugin(),
        ),
        authGatewayProvider.overrideWithValue(FakeAuthGateway()),
      ],
    )..read(notificationActionSignalControllerProvider);
    await _disposeAndClose(tester, container, database);

    // This is precisely what the handler does, and the `?.` is the whole
    // safety net: a null lookup means the app is not running, which is the
    // common case for a notification action.
    final port = IsolateNameServer.lookupPortByName(notificationActionPortName);
    expect(port, isNull);
    expect(() => port?.send(null), returnsNormally);
  });
}
