import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/fake_digest_notification_plugin.dart';

/// Live-E2E regression (2026-08-05, caught by the welcome-gate suite run,
/// invisible to every widget test): `main.dart` activates the three
/// controllers BEFORE `runApp`, and `CatchUpController`'s constructor
/// listens to `bootstrapProvider` — which, on a fresh install (no
/// household), used to throw a `StateError` that Riverpod then CACHED.
/// When the user subsequently created their household on the welcome
/// gate, `_Bootstrapped` read the cached error and showed the
/// startup-error screen instead of the shell.
///
/// The fix parks `bootstrapProvider` on `householdGateProvider` instead
/// of throwing: pre-gate it simply never resolves, and the gate's first
/// non-null emission re-executes it. This test replays main()'s exact
/// activation order against an EMPTY database, then creates the
/// household, and requires bootstrap to resolve — it fails against the
/// throwing version with the cached `StateError`.
void main() {
  testWidgets(
    'bootstrapProvider survives main()-style eager controller activation '
    'on a fresh install: parks pre-gate, resolves once the household is '
    'created (no cached StateError)',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
          // The digest controller's recompute path would otherwise hit
          // the REAL notifications plugin (LateInitializationError in a
          // test binary) — same override every controller test uses.
          digestNotificationPluginProvider.overrideWithValue(
            FakeDigestNotificationPlugin(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Exactly what main() does before runApp — the eager activations
      // that used to poison bootstrapProvider's cache on an empty db.
      container
        ..read(digestRescheduleControllerProvider)
        ..read(catchUpControllerProvider)
        ..read(syncEngineControllerProvider);

      // Let the pre-gate state settle: bootstrap must be PARKED (still
      // loading), never errored.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        container.read(bootstrapProvider).hasError,
        isFalse,
        reason:
            'pre-gate bootstrap must park, not cache a StateError — '
            'the cached error is exactly the live-E2E startup-crash bug',
      );
      expect(container.read(bootstrapProvider).hasValue, isFalse);

      // The welcome gate's create action.
      final household = await container
          .read(householdRepositoryProvider)
          .createLocalHousehold('Me');

      // Poll .hasValue with pump loops (house deadlock rule) — bootstrap
      // must now resolve to the created household's id.
      var resolved = false;
      for (var i = 0; i < 40 && !resolved; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        resolved = container.read(bootstrapProvider).hasValue;
      }
      expect(
        resolved,
        isTrue,
        reason: 'bootstrap never resolved after the household was created',
      );
      expect(container.read(bootstrapProvider).value, household.id);
      expect(container.read(bootstrapProvider).hasError, isFalse);

      // Drift dispose-vs-close bookkeeping (house deadlock rule).
      container.dispose();
      await tester.pump(const Duration(milliseconds: 50));
      await database.close();
    },
  );
}
