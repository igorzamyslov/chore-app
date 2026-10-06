/// §2.4 (spec `docs/specs/sync-freshness.md`): Settings -> Account gains a
/// relative "Last synced <time>" line under the linked-household subtitle,
/// read from the `syncLastPulledAt` cursor the engine already persists on
/// every successful pull.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart' show SnackBar;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  final signedIn = [
    authGatewayProvider.overrideWithValue(
      FakeAuthGateway(
        currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
      ),
    ),
  ];

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

  // Spec `docs/specs/sync-freshness.md` §2.4 amendment 2026-10-06: a second
  // line names how many changes are still waiting to be sent, and the
  // whole tile is tappable to sync now.
  group('pending-changes line', () {
    testChoreApp(
      'shows "N changes waiting to send" under "Last synced" while unsent '
      'changes exist, and both are under the tappable sync tile',
      today: today,
      overrides: signedIn,
      (tester, database) async {
        final handle = tester.ensureSemantics();
        final householdId = await currentHouseholdId(database);
        final settingsRepository = SettingsRepository(database);
        await settingsRepository.setSyncLinked(
          householdId: householdId,
          linkedAt: today,
        );
        await settingsRepository.setSyncLastPulledAt(
          DateTime(2026, 7, 24, 8, 50),
        );
        await clearAllDirtyFlags(database);
        await ShoppingRepository(database).addItem(householdId, name: 'Milk');

        await openSettingsTab(tester);

        expect(find.text('Last synced 10 minutes ago'), findsOneWidget);
        expect(
          find.bySemanticsIdentifier('settings.account.pendingChanges'),
          findsOneWidget,
        );
        expect(find.text('1 change waiting to send'), findsOneWidget);
        expect(
          find.descendant(
            of: find.bySemanticsIdentifier('settings.account.syncNow'),
            matching: find.text('1 change waiting to send'),
          ),
          findsOneWidget,
        );

        // A second edit: the count follows the database live.
        await ShoppingRepository(database).addItem(householdId, name: 'Eggs');
        await tester.pumpAndSettle();
        expect(find.text('2 changes waiting to send'), findsOneWidget);

        handle.dispose();
      },
    );

    testChoreApp(
      'no pending line while nothing is waiting',
      today: today,
      overrides: signedIn,
      (tester, database) async {
        final handle = tester.ensureSemantics();
        final householdId = await currentHouseholdId(database);
        await SettingsRepository(
          database,
        ).setSyncLinked(householdId: householdId, linkedAt: today);
        await clearAllDirtyFlags(database);

        await openSettingsTab(tester);

        expect(
          find.bySemanticsIdentifier('settings.account.pendingChanges'),
          findsNothing,
        );

        handle.dispose();
      },
    );

    testChoreApp(
      'tapping the tile runs a sync; a successful one is silent',
      today: today,
      overrides: signedIn,
      (tester, database) async {
        final handle = tester.ensureSemantics();
        final householdId = await currentHouseholdId(database);
        await SettingsRepository(
          database,
        ).setSyncLinked(householdId: householdId, linkedAt: today);

        await openSettingsTab(tester);
        await tester.tap(
          find.bySemanticsIdentifier('settings.account.syncNow'),
        );
        await tester.pumpAndSettle();

        // Unlinked-from-Supabase under `flutter test`, so the engine is the
        // NoopSyncEngine whose refreshNow() reports ok -- and ok shows no
        // snackbar (spec §2.3: success is silent).
        expect(find.byType(SnackBar), findsNothing);

        handle.dispose();
      },
    );
  });
}

/// Clears `syncDirty` on every synced table, so a test can then dirty
/// exactly the rows it means to count. Goes through `customUpdate` with an
/// explicit `updates:` set so drift notifies the watching streams (a
/// `customStatement` would not -- see `sync_repository_test.dart`).
Future<void> clearAllDirtyFlags(AppDatabase database) async {
  for (final table in <TableInfo<Table, dynamic>>[
    database.households,
    database.members,
    database.categories,
    database.chores,
    database.choreAssignees,
    database.choreOccurrences,
    database.shoppingItems,
  ]) {
    await database.customUpdate(
      'UPDATE ${table.actualTableName} SET sync_dirty = 0',
      updates: {table},
    );
  }
}
