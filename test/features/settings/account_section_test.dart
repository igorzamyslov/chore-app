import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/household_archive.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_utils/pump_app.dart';
import 'fake_archive_file_writer.dart';
import 'fake_auth_gateway.dart';
import 'fake_household_gateway.dart';
import 'fake_path_provider_platform.dart';
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

  // The P2d reconnect flow's happy-path test below runs the shared join
  // machinery (`HouseholdJoinService.join`), which -- like the P2c join
  // sheet tests (`join_household_sheet_test.dart`) -- writes an automatic
  // archive first. Harmless for every other test in this file (none of
  // them touch the archive path).
  late FakeArchiveFileWriter archiveWriter;

  setUp(() {
    PathProviderPlatform.instance = FakePathProviderPlatform('/fake-docs');
    archiveWriter = FakeArchiveFileWriter();
    ArchiveFileWriter.instance = archiveWriter;
  });

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
    'unlinked+signed-out: shows no adopt row and no join row, and no A5 '
    'linked hint',
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
      expect(
        find.bySemanticsIdentifier('settings.account.signedOutLinked'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out+LINKED (spec docs/feedback/2026-08-07-field-feedback.md '
    'A1.1): shows the honest paused-notice state -- NOT the plain sign-in '
    'form on its own -- naming the linked household, still offering the '
    "reused sign-in form as 'sign in to resume', plus the old A5 hint "
    '(kept, unmodified) and a reachable Disconnect action',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openSettingsTab(tester);

      // The new, prominent paused notice -- this is what makes the state
      // distinct from a device that was never linked at all.
      expect(
        find.bySemanticsIdentifier('settings.account.pausedNotice'),
        findsOneWidget,
      );
      expect(
        find.text(
          'This device is still connected to My household, but syncing is '
          'paused. Changes you make now will be sent once you sign in '
          'again.',
        ),
        findsOneWidget,
      );

      // The sign-in form itself is reused verbatim -- "sign in to resume"
      // IS this same email field + send-link button, never forked.
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsOneWidget,
      );

      // The pre-existing A5 hint still renders too (unmodified, un-removed
      // semantic id) -- this section reuses `_SignedOutForm` as-is.
      expect(
        find.bySemanticsIdentifier('settings.account.signedOutLinked'),
        findsOneWidget,
      );
      expect(
        find.text(
          'This phone is linked to My household — sign in to keep syncing.',
        ),
        findsOneWidget,
      );

      // And the new secondary Disconnect action is reachable from here.
      expect(
        find.bySemanticsIdentifier('settings.account.disconnect'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out+LINKED: cancelling the disconnect confirm dialog is a '
    'no-op -- stays linked, paused notice still shown',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openSettingsTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.disconnect'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.disconnect.confirm'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.disconnect.cancel'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.pausedNotice'),
        findsOneWidget,
      );
      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, householdId);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out+LINKED: confirming Disconnect clears the local linked '
    'state and flips the section back to the plain (never-linked-looking) '
    'sign-in form -- local household/member rows are left untouched',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(database).setSyncLinked(
        householdId: householdId,
        linkedAt: DateTime.utc(2026),
      );
      await SettingsRepository(
        database,
      ).setSyncLastPulledAt(DateTime.utc(2026, 2));
      final membersBefore = await database.select(database.members).get();

      await openSettingsTab(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.disconnect'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.disconnect.confirm'),
      );
      await tester.pumpAndSettle();

      // No more paused notice, no more disconnect row -- indistinguishable
      // from a device that was never linked, which is exactly the point.
      expect(
        find.bySemanticsIdentifier('settings.account.pausedNotice'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.disconnect'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsOneWidget,
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, isNull);
      expect(settings.syncLinkedAt, isNull);
      expect(settings.syncLastPulledAt, isNull);

      // Not a delete: the household and its members are exactly as before.
      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), [householdId]);
      final membersAfter = await database.select(database.members).get();
      expect(membersAfter, membersBefore);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in+unlinked: shows both the adopt row and the join row, and no '
    'reconnect row under the default (Noop) household gateway',
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
      expect(
        find.bySemanticsIdentifier('settings.account.reconnect'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  final signedOutProbeGateway = FakeHouseholdGateway();
  testChoreApp(
    'signed-out: myMembershipProvider never calls findMyMembership at all '
    '(no signed-in user to probe with)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(FakeAuthGateway()),
      householdGatewayProvider.overrideWithValue(signedOutProbeGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.reconnect'),
        findsNothing,
      );
      expect(signedOutProbeGateway.findMyMembershipCallCount, 0);

      handle.dispose();
    },
  );

  final noMembershipGateway = FakeHouseholdGateway();
  testChoreApp(
    'signed-in+unlinked, no membership found: probes findMyMembership, '
    'shows no reconnect row, and leaves the adopt/join rows unchanged',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(noMembershipGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.reconnect'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join'),
        findsOneWidget,
      );
      expect(noMembershipGateway.findMyMembershipCallCount, 1);

      handle.dispose();
    },
  );

  final linkedMembershipGateway = FakeHouseholdGateway()
    ..membership = const MyMembership(
      householdId: 'other-hh',
      memberId: 'm-other',
      memberName: 'Other',
      householdName: 'Other household',
    );
  testChoreApp(
    'linked: hides the adopt row, the join row, AND the reconnect row -- '
    'even when findMyMembership WOULD report a membership -- and shows the '
    'linked subtitle on the signed-in tile',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(linkedMembershipGateway),
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
      // The reconnect row only ever renders from AccountSectionBody's
      // UNLINKED branch -- once linked, myMembershipProvider's resolved
      // value (if it settles at all before this device's settled linked
      // state) has no code path left to surface it through.
      expect(
        find.bySemanticsIdentifier('settings.account.reconnect'),
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
      expect(updatedMe.userId, 'u1');

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

  // Finding 3 (plan `docs/plans/2026-08-14-reconnect-adopt-hardening.md`
  // Task 6): after a revocation, `clearSyncLink()` keeps every local row --
  // household id included -- so adopt re-sends an id the server already has,
  // while RLS makes that household unreadable to this account. The old
  // resume heuristic keys on "can I still read this household", which is
  // false for exactly the one caller who can never succeed, so it produced a
  // generic error plus "Try again" forever.
  final revokedAdoptGateway = FakeHouseholdGateway()
    ..createHouseholdError = const HouseholdIdTakenFailure();

  testChoreApp(
    'adopt after a revocation: the id is taken AND the household is '
    'unreadable, so the row goes to a terminal blocked state naming the '
    'join row as the recourse -- no retry, no tap, nothing linked',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(revokedAdoptGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.adopt'));
      await tester.pumpAndSettle();

      expect(find.text('This household is already online'), findsOneWidget);
      expect(
        find.text(
          'It is already on the server, and this device is no longer part '
          'of it. Ask someone in the household for an invite code, then use '
          '"Join an existing household" below.',
        ),
        findsOneWidget,
      );

      // The one thing this state exists to stop: an invitation to retry
      // something that cannot ever succeed on this device.
      expect(find.text('Try again'), findsNothing);
      expect(
        find.text("Couldn't put your household online. Please try again."),
        findsNothing,
      );

      final adoptTile = tester.widget<ListTile>(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.account.adopt'),
          matching: find.byType(ListTile),
        ),
      );
      expect(adoptTile.onTap, isNull);
      expect(adoptTile.enabled, isFalse);

      // The recourse the copy names must actually be on screen.
      expect(
        find.bySemanticsIdentifier('settings.account.join'),
        findsOneWidget,
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, isNull);
      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), [householdId]);

      handle.dispose();
    },
  );

  final resumeAdoptGateway = FakeHouseholdGateway()
    ..createHouseholdError = const HouseholdIdTakenFailure();

  testChoreApp(
    'adopt after a Disconnect: the id is taken but the household is still '
    'READABLE, so the resume heuristic still fires and adopt completes -- '
    'the blocked state must not swallow this case',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(resumeAdoptGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      // Disconnect leaves the caller's user_id on the server member row, so
      // `is_household_member` still passes and the household reads back.
      resumeAdoptGateway.downloadSnapshotOverride = HouseholdSnapshot(
        household: Household(
          id: householdId,
          name: 'My household',
          createdAt: 't0',
          updatedAt: 't0',
          syncDirty: false,
        ),
      );

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.adopt'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsNothing,
      );
      expect(find.text('This household is already online'), findsNothing);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, householdId);

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

  testChoreApp(
    'reconnect happy path (spec §7.6): the reconnect row appears FIRST '
    '(above the adopt row), tapping it skips straight to the import-offer '
    'step (no code entry, no chooser), and completes the replace with NO '
    'claim/join RPC -- archive written, old household replaced with the '
    "downloaded snapshot, acting member = the membership's member, linked "
    'subtitle shown',
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
      final oldHouseholdId = await currentHouseholdId(database);

      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.reconnect'),
        findsOneWidget,
      );
      expect(find.text('Reconnect to Joined household'), findsOneWidget);

      // The reconnect row sits ABOVE the adopt row (spec: "shown FIRST").
      final reconnectTop = tester.getTopLeft(
        find.bySemanticsIdentifier('settings.account.reconnect'),
      );
      final adoptTop = tester.getTopLeft(
        find.bySemanticsIdentifier('settings.account.adopt'),
      );
      expect(reconnectTop.dy, lessThan(adoptTop.dy));

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.reconnect'),
      );
      await tester.pumpAndSettle();

      // Straight to the import-offer step -- no code field, no chooser.
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join.import.decline'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.import.decline'),
      );
      await tester.pumpAndSettle();

      // Sheet closed; success snackbar names the archive file.
      expect(
        find.bySemanticsIdentifier('settings.account.reconnect.sheet'),
        findsNothing,
      );
      expect(
        find.textContaining('famdo-archive-2026-07-24.json'),
        findsOneWidget,
      );

      // No claim/join RPC at all -- reconnect already knows its household
      // and member ids.
      expect(reconnectGateway.claimMemberCalls, isEmpty);
      expect(reconnectGateway.joinAsNewMemberCalls, isEmpty);
      expect(reconnectGateway.downloadHouseholdCalls, ['joined-hh']);
      expect(
        archiveWriter.writtenFiles.keys,
        contains('/fake-docs/famdo-archive-2026-07-24.json'),
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, 'm-anna');

      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), ['joined-hh']);

      final oldHouseholdRows = await (database.select(
        database.households,
      )..where((tbl) => tbl.id.equals(oldHouseholdId))).get();
      expect(oldHouseholdRows, isEmpty);

      // Invalidation-sensitive assert (see the identical comment in
      // join_household_sheet_test.dart): the linked subtitle flows through
      // currentHouseholdProvider, which watches bootstrapProvider's
      // resolved household id -- without _ReconnectRow's post-sheet
      // ref.invalidate(bootstrapProvider) this would still point at the
      // deleted old household.
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();
      expect(find.text('Synced with Joined household'), findsOneWidget);

      handle.dispose();
    },
  );

  final accountInviteGateway = FakeHouseholdGateway();
  testChoreApp(
    'B3 (spec docs/feedback/2026-08-01-ux-audit.md): linked shows the '
    "Account section's 'Invite a member' row; tapping it revokes any "
    'previous invite THEN creates a new one (spec A3), and shows the '
    "invite sheet with the fake's code",
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(accountInviteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.invite'),
        findsOneWidget,
      );
      expect(find.text('Invite a member'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('settings.account.invite'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.members.invite.sheet'),
        findsOneWidget,
      );
      expect(find.text('AB3D7XQ9'), findsOneWidget);
      expect(accountInviteGateway.createInviteCalls, [householdId]);
      expect(accountInviteGateway.revokeActiveInvitesCalls, [householdId]);
      expect(accountInviteGateway.inviteCallOrder, ['revoke', 'create']);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in+linked (spec docs/feedback/2026-08-07-field-feedback.md '
    'A1.2): the Disconnect row is reachable below Invite; confirming it '
    'clears the local linked state and flips the section back to the '
    'signed-in+unlinked adopt/join rows, without signing the user out',
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
        find.bySemanticsIdentifier('settings.account.disconnect'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.disconnect'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.disconnect.confirm'),
      );
      await tester.pumpAndSettle();

      // Still signed in -- only the LINKED state was cleared.
      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsOneWidget,
      );
      expect(find.text('me@example.com'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.adopt'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.disconnect'),
        findsNothing,
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, isNull);

      handle.dispose();
    },
  );
}
