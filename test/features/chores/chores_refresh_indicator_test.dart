/// C1 (spec `docs/specs/sync-freshness.md` §2.3): the Chores list's
/// pull-to-refresh `RefreshIndicator` must be shown only when the household
/// is linked AND signed in -- exactly `syncEngineProvider`'s own gate
/// (`lib/app/providers.dart`). A local-only household has no remote to pull
/// from, so the indicator must be ABSENT there; once linked and signed in,
/// it must appear.
///
/// Exercises the REAL provider chain (mirrors
/// `test/app/sync_engine_provider_test.dart`): `syncTransportProvider` is
/// overridden with a fake so the "Supabase configured?" branch is reachable
/// under `flutter test` (which always runs with empty dart-defines), and
/// `settingsRepositoryProvider.setSyncLinked` drives the linked-state
/// transition the same way a real P2 link flow would.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../application/fake_sync_transport.dart';
import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// Polls until `find.bySemanticsIdentifier('chores.refresh')` finds (or, if
/// [expectPresent] is `false`, keeps NOT finding) the refresh indicator --
/// same polling shape as `sync_engine_provider_test.dart`'s
/// `_awaitLinkedEngine`, since `syncEngineProvider` reacting to a settings
/// write happens asynchronously (through drift's stream), not on the same
/// frame as the write.
Future<void> _pumpUntilRefreshIndicator(
  WidgetTester tester, {
  required bool expectPresent,
}) async {
  for (var i = 0; i < 400; i++) {
    final found = find
        .bySemanticsIdentifier('chores.refresh')
        .evaluate()
        .isNotEmpty;
    if (found == expectPresent) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError(
    'chores.refresh never became ${expectPresent ? 'present' : 'absent'}',
  );
}

/// Fires `_refresh` through the `RefreshIndicator`'s own callback rather than
/// a drag gesture -- the same widget `chores.refresh` already wraps, so this
/// exercises the production code path without depending on fling physics.
Future<void> _triggerRefresh(WidgetTester tester) async {
  final indicator = tester.widget<RefreshIndicator>(
    find.descendant(
      of: find.bySemanticsIdentifier('chores.refresh'),
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

      expect(find.bySemanticsIdentifier('chores.refresh'), findsNothing);

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

      // Signed in, but not yet linked: still absent.
      expect(find.bySemanticsIdentifier('chores.refresh'), findsNothing);

      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.now());

      await _pumpUntilRefreshIndicator(tester, expectPresent: true);
      expect(find.bySemanticsIdentifier('chores.refresh'), findsOneWidget);

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
