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
/// and then pings proves nothing about the ping. The cross-connection test
/// below therefore uses a genuinely SEPARATE [AppDatabase] over the same
/// on-disk file, which is exactly the shape the background isolate has, and
/// asserts that the container's stream cannot see that write until the
/// invalidate happens.
library;

import 'dart:io';
import 'dart:ui';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/notification_action_handler.dart';
import 'package:chore_app/application/notification_action_processor.dart';
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
    'a ping makes the app see a completion written through a SEPARATE '
    'database connection, which its own drift stream cannot see',
    (tester) async {
      // The whole mechanism, end to end short of the real isolate. An on-disk
      // file rather than NativeDatabase.memory() because two in-memory
      // databases share nothing -- and sharing a file is exactly the shape the
      // background isolate has.
      final directory = await Directory.systemTemp.createTemp('famdo_ping');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/chore_app.sqlite');

      final database = AppDatabase(NativeDatabase(file));
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
      final chore = await container
          .read(choreServiceProvider)
          .createChore(
            householdId: householdId,
            title: 'Water the plants',
            startDate: today,
            assignmentMode: AssignmentMode.anyone,
          );
      await tester.pump(digestRescheduleDebounce);

      final occurrence = (await container
          .read(choreRepositoryProvider)
          .pendingOccurrenceOf(chore.id))!;
      expect(
        plugin.pending[digestNotificationIdBase]!.body,
        '1 chore today',
        reason:
            'the pre-completion horizon must actually be armed, or the '
            'post-ping assertion below proves nothing',
      );

      // A SECOND connection to the same file -- the background isolate's
      // shape. `applyDoneAction` is the very function the isolate calls.
      final isolateDatabase = AppDatabase(NativeDatabase(file));
      await applyDoneAction(
        database: isolateDatabase,
        occurrenceId: occurrence.id,
        actingMemberId: null,
        clock: Clock.fixed(DateTime(2026, 7, 24, 7)),
      );
      await isolateDatabase.close();

      // THE PREMISE, asserted rather than assumed: drift's stream
      // invalidation bus is per-QueryExecutor, so this container's
      // pendingOccurrencesProvider has no idea that write happened, and the
      // horizon is therefore still describing a chore the user has already
      // said they did.
      await tester.pump(digestRescheduleDebounce);
      expect(
        plugin.pending[digestNotificationIdBase]?.body,
        '1 chore today',
        reason:
            'a write through another connection must be invisible here -- '
            'if it is not, the invalidate this controller performs is '
            'unnecessary and this whole design should be revisited',
      );

      // The ping the isolate sends.
      IsolateNameServer.lookupPortByName(notificationActionPortName)!.send(
        null,
      );

      // Pumped generously: the ping's own triggerRecompute may read
      // pre-invalidation data, and the CORRECT recompute arrives via
      // DigestRescheduleController's existing ref.listen on the freshly
      // re-emitting stream. So this waits for the second one, not the first.
      for (var i = 0; i < 10; i++) {
        await tester.pump(digestRescheduleDebounce);
      }

      expect(
        plugin.pending[digestNotificationIdBase],
        isNull,
        reason:
            'with the only chore done, slot 0 must be cancelled, not left '
            'armed with a stale count',
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
