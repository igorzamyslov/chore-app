import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'fake_household_gateway.dart';
import 'settings_test_utils.dart';

/// Finds the [TextField] wrapped by the semantic id [identifier].
Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

/// Finds the [FilledButton] wrapped by the semantic id [identifier].
Finder _filledButtonFor(String identifier) {
  return find
      .descendant(
        of: find.bySemanticsIdentifier(identifier),
        matching: find.byType(FilledButton),
      )
      .first;
}

/// Widget-level tests for the Settings tab's Account section (spec
/// `docs/specs/sync-backend.md` §5): the disabled 'coming soon' row under
/// the built-in `NoopAuthGateway`, and -- via [FakeAuthGateway] -- the
/// signed-out magic-link form (email validation, send, confirmation state,
/// send failure) and the signed-in display/sign-out confirm flow.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    "Noop gateway: shows the disabled 'coming soon' row, no interactive "
    'account UI',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(const NoopAuthGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.comingSoon'),
        findsOneWidget,
      );
      expect(find.text('Sync — coming soon'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsNothing,
      );

      final tile = tester.widget<ListTile>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.account.comingSoon'),
              matching: find.byType(ListTile),
            )
            .first,
      );
      expect(tile.enabled, isFalse);

      // The rest of the screen still renders fine alongside it.
      expect(
        find.bySemanticsIdentifier('settings.digest.toggle'),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('settings.reset'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out: the send button stays disabled until the email looks '
    'plausible, then sends and shows the confirmation state',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.text('Sign in to sync your household across your devices.'),
        findsOneWidget,
      );

      FilledButton sendButtonWidget() => tester.widget<FilledButton>(
        _filledButtonFor('settings.account.sendLink'),
      );

      expect(sendButtonWidget().onPressed, isNull, reason: 'empty field');

      await tester.enterText(
        _fieldFor('settings.account.email'),
        'not-an-email',
      );
      await tester.pump();
      expect(
        sendButtonWidget().onPressed,
        isNull,
        reason: 'missing @ and domain',
      );

      await tester.enterText(
        _fieldFor('settings.account.email'),
        'me@example.com',
      );
      await tester.pump();
      expect(sendButtonWidget().onPressed, isNotNull);
      expect(find.text('Send sign-in link'), findsOneWidget);

      await tester.tap(_filledButtonFor('settings.account.sendLink'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Check your email at me@example.com for your sign-in link.',
        ),
        findsOneWidget,
      );
      expect(find.text('Send again'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out: a magic-link send failure shows the generic error '
    'snackbar and stays in the signed-out (non-confirmation) state',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway()..sendMagicLinkError = Exception('network down'),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.enterText(
        _fieldFor('settings.account.email'),
        'me@example.com',
      );
      await tester.pump();
      await tester.tap(_filledButtonFor('settings.account.sendLink'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't send the sign-in link. Please try again."),
        findsOneWidget,
      );
      expect(find.text('Send sign-in link'), findsOneWidget);
      expect(find.text('Send again'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in: shows the account email; cancelling the sign-out confirm '
    'dialog is a no-op',
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
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsOneWidget,
      );
      expect(find.text('me@example.com'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsNothing,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.account.signOut'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.account.signOut.confirm'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.signOut.cancel'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsOneWidget,
      );
      expect(find.text('me@example.com'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in: confirming the sign-out dialog signs out and returns to '
    'the signed-out form',
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
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.account.signOut'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.signOut.confirm'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'unlinked+signed-out: shows no adopt row and no join row',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in+unlinked: shows both the adopt row and the join row',
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
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'linked: hides the adopt row and the join row, shows the linked '
    'subtitle on the signed-in tile',
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
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join'),
        findsNothing,
      );
      expect(find.text('Synced with My household'), findsOneWidget);

      handle.dispose();
    },
  );

  final happyPathGateway = FakeHouseholdGateway();
  testChoreApp(
    'adopt happy path: creates the household with the LOCAL id and the '
    "acting member's id/name/color, uploads everything else, links "
    "settings, flips the acting member's role to admin, and flips the UI "
    'to the linked subtitle',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(happyPathGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
      // Demote the bootstrap member first, so the "flips to admin" part of
      // this test is actually exercised (it's created as admin already).
      await HouseholdRepository(
        database,
      ).setMemberRole(me.id, MemberRole.member);
      final expectedCategoryIds =
          (await database.select(database.categories).get())
              .map((category) => category.id)
              .toSet();

      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.account.adopt'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsNothing,
      );
      expect(find.text('Synced with My household'), findsOneWidget);

      expect(happyPathGateway.createHouseholdCalls, hasLength(1));
      final createCall = happyPathGateway.createHouseholdCalls.single;
      expect(createCall.householdId, householdId);
      expect(createCall.memberId, me.id);
      expect(createCall.memberName, 'Me');
      expect(createCall.memberColor, me.color);

      expect(happyPathGateway.uploadHouseholdDataCalls, hasLength(1));
      final uploaded = happyPathGateway.uploadHouseholdDataCalls.single;
      // The acting member is excluded -- it was already created by step 1.
      expect(uploaded.members, isEmpty);
      expect(
        uploaded.categories.map((category) => category.id).toSet(),
        expectedCategoryIds,
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, householdId);
      expect(settings.syncLinkedAt, isNotNull);

      final updatedMe = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(updatedMe.role, MemberRole.admin);

      handle.dispose();
    },
  );

  final retryGateway = FakeHouseholdGateway()
    ..uploadHouseholdDataError = Exception('network down');
  testChoreApp(
    'adopt with upload failure then successful retry: a second '
    'createHousehold call that throws (simulating "already exists with me '
    'as member") is tolerated as step-1 success, and the flow completes',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(retryGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.adopt'));
      await tester.pumpAndSettle();

      // First attempt: createHousehold succeeds, upload fails -> inline
      // error + "Try again", still unlinked.
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text("Couldn't put your household online. Please try again."),
        findsOneWidget,
      );
      var settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, isNull);
      expect(retryGateway.createHouseholdCalls, hasLength(1));
      expect(retryGateway.uploadHouseholdDataCalls, hasLength(1));

      // Retry: this time createHousehold itself throws (e.g. a unique
      // violation on rerun) -- the service must detect the household
      // already exists (from the first attempt) and continue anyway; the
      // upload succeeds this time.
      retryGateway
        ..uploadHouseholdDataError = null
        ..createHouseholdError = Exception('household already exists');

      await tester.tap(find.bySemanticsIdentifier('settings.account.adopt'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsNothing,
      );
      expect(find.text('Synced with My household'), findsOneWidget);

      expect(retryGateway.createHouseholdCalls, hasLength(2));
      expect(retryGateway.downloadHouseholdCalls, isNotEmpty);
      expect(retryGateway.uploadHouseholdDataCalls, hasLength(2));

      settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, householdId);

      handle.dispose();
    },
  );
}
