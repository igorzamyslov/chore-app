import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart'
    show HouseholdSnapshot;
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  final prefillFakeAuth = FakeAuthGateway();
  final prefillGateway = FakeHouseholdGateway()
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
    'a pre-existing pendingJoinCode prefills the code field as soon as the '
    'join subpage reaches code entry, and a successful submit persists a '
    'fresh one in its place',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(prefillFakeAuth),
      householdGatewayProvider.overrideWithValue(prefillGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).setPendingJoinCode('OLD12345');

      // Signed OUT at pump time, so the two-card chooser is showing and
      // this is a plain manual tap -- the auto-resume of
      // `welcome_screen_test.dart`'s cold-start test cannot fire here.
      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();
      prefillFakeAuth.signIn(
        const AuthUser(id: 'u1', email: 'me@example.com'),
      );
      await tester.pumpAndSettle();

      // Reached code entry (no membership -> no reconnect offer), and the
      // pre-existing code is already sitting in the field.
      final codeField = tester.widget<TextField>(
        _fieldFor('settings.account.join.code'),
      );
      expect(codeField.controller!.text, 'OLD12345');

      // Submitting a DIFFERENT code overwrites the persisted value.
      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'new67890',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Are you Anna?'), findsOneWidget);

      final row = await database.select(database.settings).getSingle();
      expect(row.pendingJoinCode, 'NEW67890');

      handle.dispose();
    },
  );

  final killFakeAuth = FakeAuthGateway();
  final killGateway = FakeHouseholdGateway()
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
    'mid-flow kill after submitting a code but before the claim RPC resumes '
    'on the join subpage with the code prefilled, not on the two-card '
    'chooser, and completes normally from there -- the '
    'point-of-maximum-anxiety scenario this ticket exists to fix, end to end',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(killFakeAuth),
      householdGatewayProvider.overrideWithValue(killGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.join'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _fieldFor('welcome.join.email'),
        'me@example.com',
      );
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('welcome.join.send'));
      await tester.pumpAndSettle();

      killFakeAuth.signIn(const AuthUser(id: 'u1', email: 'me@example.com'));
      await tester.pumpAndSettle();

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

      // Simulated kill+relaunch: a brand-new widget tree/ProviderScope over
      // the exact same, still-open in-memory database and the exact same
      // fake gateway instances. A real kill preserves neither Dart object --
      // what it DOES preserve is this device's Supabase session, which
      // `killFakeAuth.currentUser` stands in for here, and the database. A
      // fresh `Key` forces a real rebuild from scratch rather than an
      // in-place, hot-reload-style rebuild (see `welcome_screen_test.dart`'s
      // "mid-flow kill" test for the same reasoning).
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock.fixed(today)),
            authGatewayProvider.overrideWithValue(killFakeAuth),
            householdGatewayProvider.overrideWithValue(killGateway),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Landed straight back on the join subpage's code step -- not the
      // two-card chooser -- with the previously-submitted code prefilled.
      expect(find.bySemanticsIdentifier('welcome.create'), findsNothing);
      expect(find.bySemanticsIdentifier('welcome.join'), findsNothing);
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsOneWidget,
      );
      final codeField = tester.widget<TextField>(
        _fieldFor('settings.account.join.code'),
      );
      expect(codeField.controller!.text, 'ABC12345');

      // Continuing from here works exactly as before the kill.
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Are you Anna?'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.claim.m-anna'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, 'm-anna');
      expect(settings.pendingJoinCode, isNull);

      handle.dispose();
    },
  );
}
