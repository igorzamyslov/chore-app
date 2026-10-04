/// Wiring test for `ErrorReporterController` (spec
/// `docs/specs/client-error-reporting.md` §4.1): a successful sync pull --
/// observed as `settings.syncLastPulledAt` changing -- flushes the error
/// buffer through the REAL provider chain, and the four-condition gate is
/// read live at that moment. `errorReportTransportProvider` is the override
/// hook that reaches the reporter without `supabaseConfigured` (always false
/// under `flutter test`) being true.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/error_reporter.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_auth_gateway.dart';

class _FakeTransport implements ErrorReportTransport {
  final List<List<Map<String, Object?>>> batches = [];

  @override
  Future<void> insertErrors(List<Map<String, Object?>> rows) async {
    batches.add(rows);
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets(
    'a successful pull flushes pending errors when signed in, linked and '
    'enabled -- and not once the switch is off',
    timeout: const Timeout(Duration(seconds: 20)),
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final transport = _FakeTransport();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock.fixed(DateTime.utc(2026))),
          errorReportTransportProvider.overrideWithValue(transport),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      final settings = container.read(settingsRepositoryProvider);
      final log = container.read(errorLogRepositoryProvider);
      Future<void> record(String message) => log.record(
        source: 'ui.test',
        error: ErrorScrubber.scrub(StateError(message), null),
        appVersion: '0.13.0+20',
        platform: 'android 14',
      );

      await record('first');
      await settings.setSyncLinked(
        householdId: 'h-1',
        linkedAt: DateTime.utc(2026),
      );

      container.read(errorReporterControllerProvider);
      // Let the settings and auth streams deliver their first values.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(
        transport.batches,
        isEmpty,
        reason: 'no pull has completed yet and startup found a closed gate',
      );

      await settings.setSyncLastPulledAt(DateTime.utc(2026, 1, 2));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(transport.batches, hasLength(1));
      expect(transport.batches.single.single['message'], 'Bad state: first');

      await settings.setErrorReportsEnabled(enabled: false);
      await record('second');
      await settings.setSyncLastPulledAt(DateTime.utc(2026, 1, 3));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(
        transport.batches,
        hasLength(1),
        reason: 'the switch is off: nothing more is uploaded',
      );

      await settings.setErrorReportsEnabled(enabled: true);
      // The gate reads the settings stream's latest value: let it deliver.
      await tester.pump(const Duration(milliseconds: 50));
      container.read(errorReporterControllerProvider).triggerOnResume();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(transport.batches, hasLength(2));
      expect(transport.batches.last.single['message'], 'Bad state: second');

      container.dispose();
      await tester.pump(const Duration(milliseconds: 10));
      await database.close();
    },
  );
}
