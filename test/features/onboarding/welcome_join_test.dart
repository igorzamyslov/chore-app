import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart'
    show HouseholdSnapshot;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';
import '../settings/fake_household_gateway.dart';

Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

/// Widget-level tests for the welcome screen's "Join my family's
/// household" subpage (spec `docs/specs/onboarding-v2.md` §1): the sign-in
/// step reacting to the auth-state watch (not the OS deep link, per the
/// spec's own testing note), the P2d reconnect offer, and the no-archive/
/// no-import join happy path via `HouseholdJoinService.joinFresh`.
///
/// Unlike the Settings join sheet's tests
/// (`test/features/settings/join_household_sheet_test.dart`), NONE of these
/// need `FakeArchiveFileWriter`/`FakePathProviderPlatform` -- the welcome
/// path never writes an archive (spec: "no archive step, no import offer:
/// with no local household both are meaningless").
void main() {
  final today = DateTime(2026, 7, 24, 9);

  final fakeAuth = FakeAuthGateway();
  final claimGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
    ]
    ..claimResultHouseholdId = 'joined-hh'
    ..downloadSnapshotOverride = const HouseholdSnapshot(
      household: Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
        syncDirty: false,
      ),
      members: [
        Member(
          id: 'm-anna',
          householdId: 'joined-hh',
          name: 'Anna',
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
          syncDirty: false,
        ),
      ],
    );

  testFreshChoreApp(
    'join happy path: email sign-in -> membership null -> code entry -> '
    'claim -> household downloaded, acting member + linked state set, no '
    'archive/import step anywhere in the flow',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(fakeAuth),
      householdGatewayProvider.overrideWithValue(claimGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      expect(await database.select(database.households).get(), isEmpty);

      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('welcome.join.email'),
        findsOneWidget,
      );
      await tester.enterText(
        _fieldFor('welcome.join.email'),
        'me@example.com',
      );
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('welcome.join.send'));
      await tester.pumpAndSettle();
      expect(
        find.text('Check your email at me@example.com for your sign-in link.'),
        findsOneWidget,
      );

      // The magic-link "returns": the deep link itself is out of scope for
      // a widget test (spec: "test the auth-state watch, not the OS deep
      // link") -- this simulates exactly what it produces, a new value on
      // the auth gateway's watchUser() stream.
      fakeAuth.signIn(const AuthUser(id: 'u1', email: 'me@example.com'));
      await tester.pumpAndSettle();

      // Signed in, no membership found (claimGateway.membership defaults
      // to null) -- straight to code entry, no reconnect offer.
      expect(
        find.bySemanticsIdentifier('welcome.join.reconnect'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsOneWidget,
      );

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'abc12345',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Are you Anna?'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.claim.m-anna'),
      );
      await tester.pumpAndSettle();

      // No import-offer step at all -- straight to the shell.
      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      expect(find.bySemanticsIdentifier('welcome.join'), findsNothing);

      expect(claimGateway.listClaimableMembersCalls, ['ABC12345']);
      expect(claimGateway.claimMemberCalls, [
        (code: 'ABC12345', memberId: 'm-anna'),
      ]);
      expect(claimGateway.downloadHouseholdCalls, ['joined-hh']);

      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), ['joined-hh']);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, 'm-anna');

      handle.dispose();
    },
  );

  final reconnectGateway = FakeHouseholdGateway()
    ..membership = const MyMembership(
      householdId: 'joined-hh',
      memberId: 'm-anna',
      memberName: 'Anna',
      householdName: 'Joined household',
    )
    ..downloadSnapshotOverride = const HouseholdSnapshot(
      household: Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
        syncDirty: false,
      ),
      members: [
        Member(
          id: 'm-anna',
          householdId: 'joined-hh',
          name: 'Anna',
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
          syncDirty: false,
        ),
      ],
    );

  testFreshChoreApp(
    'reconnect offer: an already signed-in account with an existing '
    'membership skips code entry and the chooser entirely -- tapping it '
    'joins straight away',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(reconnectGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('welcome.join.reconnect'),
        findsOneWidget,
      );
      expect(find.text('Reconnect to Joined household'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('welcome.join.email'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsNothing,
      );

      await tester.tap(find.bySemanticsIdentifier('welcome.join.reconnect'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);

      expect(reconnectGateway.claimMemberCalls, isEmpty);
      expect(reconnectGateway.joinAsNewMemberCalls, isEmpty);
      expect(reconnectGateway.downloadHouseholdCalls, ['joined-hh']);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, 'm-anna');

      handle.dispose();
    },
  );

  testFreshChoreApp(
    'the privacy disclosure sits above the email field here too, not only '
    'in Settings (backlog E-3): this is the FIRST place a new user is asked '
    'to sign in, so it is the one that most needs to say what leaves the '
    'device -- and that nothing has to',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('welcome.join.email'), findsOneWidget);
      expect(
        find.text(
          "Signing in stores your email and your household's data — chores, "
          'shopping list, members — on the sync server, so your devices stay '
          'in step. Without an account, everything stays on this device.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
