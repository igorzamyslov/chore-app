/// C1 (spec `docs/specs/sync-freshness.md` §2.3): the Shopping list's
/// pull-to-refresh `RefreshIndicator` must be shown only when the household
/// is linked AND signed in -- see
/// `test/features/chores/chores_refresh_indicator_test.dart`'s doc comment
/// for the full rationale and the provider-chain approach this mirrors.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../application/fake_sync_transport.dart';
import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';
import 'shopping_test_utils.dart';

Future<void> _pumpUntilRefreshIndicator(
  WidgetTester tester, {
  required bool expectPresent,
}) async {
  for (var i = 0; i < 400; i++) {
    final found = find
        .bySemanticsIdentifier('shopping.refresh')
        .evaluate()
        .isNotEmpty;
    if (found == expectPresent) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError(
    'shopping.refresh never became ${expectPresent ? 'present' : 'absent'}',
  );
}

/// See `chores_refresh_indicator_test.dart`'s `_triggerRefresh`.
Future<void> _triggerRefresh(WidgetTester tester) async {
  final indicator = tester.widget<RefreshIndicator>(
    find.descendant(
      of: find.bySemanticsIdentifier('shopping.refresh'),
      matching: find.byType(RefreshIndicator),
    ),
  );
  await indicator.onRefresh();
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'pull-to-refresh indicator is absent for a local-only household',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openShoppingTab(tester);
      expect(find.bySemanticsIdentifier('shopping.refresh'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'pull-to-refresh indicator appears once the household is linked AND '
    'signed in',
    today: today,
    overrides: [
      syncTransportProvider.overrideWithValue(FakeSyncTransport()),
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openShoppingTab(tester);
      // Signed in, but not yet linked: still absent.
      expect(find.bySemanticsIdentifier('shopping.refresh'), findsNothing);

      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.now());

      await _pumpUntilRefreshIndicator(tester, expectPresent: true);
      expect(find.bySemanticsIdentifier('shopping.refresh'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a pull-to-refresh that discovers revocation shows the revoked-specific '
    "string, not syncRefreshError's now-inaccurate \"will sync later\" "
    '(carried finding, docs/handover-2026-08-14-planning.md §4)',
    today: today,
    overrides: [
      syncTransportProvider.overrideWithValue(
        FakeSyncTransport()..membershipPresent = false,
      ),
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.now());
      await _pumpUntilRefreshIndicator(tester, expectPresent: true);

      await _triggerRefresh(tester);

      expect(find.textContaining('so nothing will sync'), findsOneWidget);
      expect(find.textContaining('will sync later'), findsNothing);

      handle.dispose();
    },
  );
}
