/// §2.4 (spec `docs/specs/sync-freshness.md`): Settings -> Account gains a
/// relative "Last synced <time>" line under the linked-household subtitle,
/// read from the `syncLastPulledAt` cursor the engine already persists on
/// every successful pull.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'linked but never pulled yet: no "Last synced" line',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: today);

      await openSettingsTab(tester);

      expect(find.text('Synced with My household'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.lastSynced'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'shows a relative "Last synced" line once the engine has recorded a '
    'pull cursor',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final settingsRepository = SettingsRepository(database);
      await settingsRepository.setSyncLinked(
        householdId: householdId,
        linkedAt: today,
      );
      // 10 minutes before `today` -- same local convention `today` itself
      // uses, so the elapsed-time math below lands on a clean 10 minutes
      // regardless of the test runner's own timezone.
      await settingsRepository.setSyncLastPulledAt(
        DateTime(2026, 7, 24, 8, 50),
      );

      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.lastSynced'),
        findsOneWidget,
      );
      expect(find.text('Last synced 10 minutes ago'), findsOneWidget);

      handle.dispose();
    },
  );
}
