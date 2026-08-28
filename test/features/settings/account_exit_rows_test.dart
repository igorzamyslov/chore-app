/// Widget tests for the Account section's exit rows (spec
/// `docs/specs/household-lifecycle.md` §2.2/§3.3/§3.4, D-L3/D-L5/D-L6):
/// leaving a household through the shared keep-or-delete-this-phone
/// confirm, the last-claimed-member cascade warning, and deleting the
/// account behind that same sheet PLUS one final confirmation.
///
/// The delete-account group's whole job is pinning D-L6's ORDER -- sheet
/// first (the choice, with D-L3's checkbox), then a single last gate whose
/// copy names the outcome the checkbox just selected. A confirmation moved
/// in front of the sheet is the explicitly rejected design, because it
/// cannot describe the consequence; several of these tests fail if anyone
/// "improves" it that way.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'fake_household_gateway.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);
  const me = AuthUser(id: 'me', email: 'me@x.y');

  // One fake per test that asserts on recorded calls: `overrides` is
  // evaluated when `main()` runs, so a fake shared across tests would carry
  // the previous test's calls. Same shape as Task 16's tests.
  final leaveGateway = FakeHouseholdGateway();
  final wipeGateway = FakeHouseholdGateway();
  final cancelGateway = FakeHouseholdGateway();
  final deleteGateway = FakeHouseholdGateway();
  final deleteAuth = FakeAuthGateway(currentUser: me);
  final cancelDeleteGateway = FakeHouseholdGateway();
  final cancelDeleteAuth = FakeAuthGateway(currentUser: me);
  final sheetCancelGateway = FakeHouseholdGateway();
  final wipeDeleteGateway = FakeHouseholdGateway();
  final failingDeleteGateway = FakeHouseholdGateway()
    ..deleteAccountError = Exception('offline');
  final failingDeleteAuth = FakeAuthGateway(currentUser: me);

  /// Links the seeded household and marks the bootstrap member claimed by
  /// [me], i.e. the ordinary signed-in-and-linked state that
  /// `memberIdentityModeProvider` calls `pinned` -- the state
  /// `leave_household` needs.
  ///
  /// Writes `members.userId` directly: `user_id` is server-owned (only the
  /// `create_household`/`claim_member`/`join_as_new_member` RPCs set it) and
  /// no local flow can produce a claim in a widget test.
  Future<String> linkAndClaim(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    final member = await (database.select(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(member.id))).write(
      const MembersCompanion(userId: Value('me')),
    );
    await SettingsRepository(
      database,
    ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));
    return householdId;
  }

  testChoreApp(
    'linked + signed in: the Leave row is offered beside Disconnect; '
    'unlinked it is not (spec §3.3)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      expect(
        find.bySemanticsIdentifier('settings.account.leave'),
        findsNothing,
      );

      await linkAndClaim(database);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.leave'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.disconnect'),
        findsOneWidget,
        reason: 'Disconnect is a different, purely local action and stays',
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'leaving as the last claimed member warns that the online household '
    'goes too, then leaves anyway (D-L5: neither silent nor blocked)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(leaveGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last person here'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.confirm'),
      );
      await tester.pumpAndSettle();

      expect(leaveGateway.leaveHouseholdCalls, [householdId]);
      // D-L3 default: the box was left untouched, so this phone keeps
      // everything. Do not weaken this -- it is the whole point of D-L3.
      expect(await database.select(database.households).get(), hasLength(1));
      expect(await database.select(database.members).get(), hasLength(1));
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'with another claimed member present, the cascade warning is NOT shown',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(anna.id))).write(
        const MembersCompanion(userId: Value('anna-auth')),
      );

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last person here'), findsNothing);
      expect(find.textContaining('Your profile stays'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'ticking "also delete this phone\'s copy" wipes this device too (D-L3)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(wipeGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.deleteLocal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.confirm'),
      );
      await tester.pumpAndSettle();

      expect(wipeGateway.leaveHouseholdCalls, [householdId]);
      // resetAppData clears every table, which is what returns the app to
      // the welcome screen. This is the destructive path; without a test it
      // is the one nobody finds out is broken until a user runs it.
      expect(await database.select(database.households).get(), isEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the leave confirm calls nothing and stays linked',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(cancelGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();
      // Even with the wipe box ticked, Cancel must delete nothing and call
      // nothing -- this pins that the checkbox never leaks out on a decline.
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.deleteLocal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.cancel'),
      );
      await tester.pumpAndSettle();

      expect(cancelGateway.leaveHouseholdCalls, isEmpty);
      expect(await database.select(database.households).get(), hasLength(1));
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);

      handle.dispose();
    },
  );

  testChoreApp(
    'a failed leave says so and leaves the device linked, so the retry is a '
    'plain retry',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(
        FakeHouseholdGateway()..leaveHouseholdError = Exception('offline'),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.leave'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.leave.confirm'),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't leave the household"),
        findsOneWidget,
      );
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);
      expect(await database.select(database.households).get(), hasLength(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'the Delete account row is offered whenever signed in -- linked or not '
    '(GDPR erasure must not require linking first)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      expect(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
        findsOneWidget,
        reason: 'unlinked but signed in: erasure is still reachable',
      );

      await linkAndClaim(database);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'deleting the account calls the RPC, signs out, and keeps this phone by '
    'default (D-L3)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(deleteAuth),
      householdGatewayProvider.overrideWithValue(deleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();

      // D-L6: the shared sheet comes FIRST -- the choice, before any
      // confirmation of it. This pair goes before the checkbox lookup on
      // purpose: both orderings fail if a confirmation is moved in front of
      // the sheet, but `tester.widget<CheckboxListTile>` fails with
      // 'Bad state: No element', which says nothing about what broke, while
      // these two name the rule.
      expect(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
        findsNothing,
        reason: 'D-L6: the final gate must not precede the sheet',
      );
      expect(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.deleteLocal',
        ),
        findsOneWidget,
        reason: 'the sheet, with D-L3 checkbox, is the first thing shown',
      );
      final box = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.bySemanticsIdentifier(
            'settings.account.deleteAccount.deleteLocal',
          ),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(box.value, isFalse, reason: 'D-L3: unchecked by default');
      // Last claimed member: the cascade warning, same plain wording D-L5
      // requires for leaving.
      expect(find.textContaining('last person here'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();

      // Then, and only then, the final gate -- naming the outcome the
      // checkbox just selected. Nothing has been called yet.
      expect(deleteGateway.deleteAccountCallCount, 0);
      expect(
        find.textContaining('This phone keeps everything'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
      );
      await tester.pumpAndSettle();

      expect(deleteGateway.deleteAccountCallCount, 1);
      expect(deleteAuth.currentUser, isNull);
      // D-L3 default: the box was left untouched, so this phone keeps
      // everything. Do not weaken this -- it is the whole point of D-L3,
      // and GDPR erasure covers the server copy, not the user's own device.
      expect(await database.select(database.households).get(), hasLength(1));
      expect(await database.select(database.members).get(), hasLength(1));
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the final confirmation is a complete no-op -- no RPC, still '
    'signed in, still linked (D-L6)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(cancelDeleteAuth),
      householdGatewayProvider.overrideWithValue(cancelDeleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.cancel',
        ),
      );
      await tester.pumpAndSettle();

      expect(cancelDeleteGateway.deleteAccountCallCount, 0);
      expect(cancelDeleteAuth.currentUser, isNotNull);
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);
      expect(await database.select(database.households).get(), hasLength(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the exit sheet never reaches the final confirmation at all',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(sheetCancelGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      // Even with the wipe box ticked, Cancel must call nothing and must not
      // open the second gate -- this pins that the checkbox never leaks out
      // on a decline.
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.deleteLocal',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.cancel'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
        findsNothing,
      );
      expect(sheetCancelGateway.deleteAccountCallCount, 0);
      expect(await database.select(database.households).get(), hasLength(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'ticking the box changes what the final confirmation SAYS, then wipes '
    'this phone as well (D-L6: you confirm the thing you configured)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway(currentUser: me)),
      householdGatewayProvider.overrideWithValue(wipeDeleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await linkAndClaim(database);
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.deleteLocal',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();

      // The OTHER body -- this is the entire point of confirming after the
      // choice. 'Neither can be undone' is unique to
      // accountDeleteFinalBodyDeletePhone; "this phone's copy" would NOT
      // be, since that is verbatim the sheet's own checkbox label
      // (exitConfirmDeleteLocalLabel).
      expect(find.textContaining('Neither can be undone'), findsOneWidget);
      expect(find.textContaining('This phone keeps everything'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
      );
      await tester.pumpAndSettle();

      expect(wipeDeleteGateway.deleteAccountCallCount, 1);
      expect(await database.select(database.households).get(), isEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'a failed account deletion is reported and changes nothing',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(failingDeleteAuth),
      householdGatewayProvider.overrideWithValue(failingDeleteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await linkAndClaim(database);

      await openSettingsTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.deleteAccount.confirm'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'settings.account.deleteAccount.final.confirm',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't delete your account"),
        findsOneWidget,
      );
      // The RPC runs before anything local moves, so 'nothing was changed'
      // in that snackbar has to be literally true.
      expect(failingDeleteAuth.currentUser, isNotNull);
      final row = await SettingsRepository(database).ensureSettings();
      expect(row.syncHouseholdId, householdId);
      expect(await database.select(database.households).get(), hasLength(1));

      handle.dispose();
    },
  );
}
