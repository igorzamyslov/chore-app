/// The live-backend smoke for the three household exits (F9/F10/F11), run
/// against a REAL Supabase stack rather than a fake gateway.
///
/// ## Why this file exists, and why it is not under `test/`
///
/// Wave 5 shipped remove-member, leave-household and delete-account, and every
/// one of them merged CI-green while **nothing anywhere exercised the client's
/// use of the RPCs**. Two things looked like they covered it and do not:
///
/// - **pgTAP** (`supabase/tests/`, `db.yml`) verifies the SQL contract by
///   calling the functions directly from psql. It never runs a line of Dart, so
///   it cannot catch a gateway that names the wrong RPC, passes the wrong
///   parameter name, or mis-reads the result.
/// - **The widget/unit suite** drives `FakeHouseholdGateway`. A fake agrees
///   with whatever the code under test believes, so the two can be wrong
///   together and stay green forever.
/// - **Maestro E2E** runs permanently signed-out and unlinked, by design, so it
///   never reaches sync at all.
///
/// This file closes exactly that gap: the REAL [SupabaseHouseholdGateway],
/// against a real Postgres with the real migrations and the real RLS policies.
///
/// It lives in `test_live/`, NOT `test/`, on purpose: bare `flutter test`
/// discovers only `test/`, so the ordinary suite stays hermetic and offline
/// (which `supabase_config.dart` and `lefthook.yml` both depend on). Run it
/// explicitly — see `tool/live_smoke.sh`, which is also what `db.yml` runs.
///
/// ## Safety
///
/// `supabase_config.dart` defaults to the **production** project when no
/// `--dart-define` is passed. This file therefore refuses to run against
/// anything but a loopback host, and that guard is the first thing in `main()`
/// rather than a comment asking you to be careful. These tests create and
/// delete accounts and soft-delete households; pointed at production they would
/// do exactly that to real data.
library;

import 'package:chore_app/application/household_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local stack URL. Defaults to the CLI's own default so a developer who ran
/// `supabase start` needs no arguments.
const String _url = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);

/// The local anon/publishable key.
const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// The local service-role key. Used ONLY by this test's own assertions and
/// user fixtures — never by the gateway under test, which sees the anon key
/// exactly as the shipped app does.
const String _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

/// A second client bound to the service role, so assertions can see past RLS.
/// Deliberately separate from `Supabase.instance`: if an assertion could only
/// see what the acting user can see, a policy that hides a row would be
/// indistinguishable from a row that was actually deleted.
late final SupabaseClient _admin;

int _uniqueSuffix = 0;

/// Creates a confirmed account and returns (email, password).
Future<({String email, String password})> _createUser() async {
  _uniqueSuffix++;
  final email =
      'smoke$_uniqueSuffix.${DateTime.now().microsecondsSinceEpoch}'
      '@example.com';
  const password = 'smoke-password-123';
  await _admin.auth.admin.createUser(
    AdminUserAttributes(
      email: email,
      password: password,
      emailConfirm: true,
    ),
  );
  return (email: email, password: password);
}

/// Signs the shared app client in as the given user. The gateway under test
/// reads `Supabase.instance.client`, so this is how a "device" is switched.
Future<String> _signInAs(({String email, String password}) user) async {
  final client = Supabase.instance.client;
  await client.auth.signOut();
  final response = await client.auth.signInWithPassword(
    email: user.email,
    password: user.password,
  );
  return response.user!.id;
}

Future<Map<String, dynamic>?> _householdRow(String id) async {
  final rows = await _admin
      .from('households')
      .select('id, deleted_at')
      .eq('id', id);
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, dynamic>?> _memberRow(String id) async {
  final rows = await _admin
      .from('members')
      .select('id, name, user_id, deleted_at')
      .eq('id', id);
  return rows.isEmpty ? null : rows.first;
}

Future<bool> _authUserExists(String userId) async {
  try {
    await _admin.auth.admin.getUserById(userId);
    return true;
  } on Object {
    return false;
  }
}

/// A household id and its owner's member id.
typedef _Household = ({String householdId, String memberId});

/// Creates a household owned by the currently signed-in user.
Future<_Household> _createHousehold(HouseholdGateway gateway) async {
  _uniqueSuffix++;
  final householdId = 'hh-${DateTime.now().microsecondsSinceEpoch}';
  final memberId = 'm-owner-${DateTime.now().microsecondsSinceEpoch}';
  await gateway.createHousehold(
    householdId: householdId,
    name: 'Smoke household',
    memberId: memberId,
    memberName: 'Owner',
    memberColor: 0xFF2196F3,
  );
  return (householdId: householdId, memberId: memberId);
}

void main() {
  // FAIL CLOSED. `supabase_config.dart` defaults to the production project,
  // and these tests delete accounts and soft-delete households. A typo in a
  // --dart-define must stop the run, not redirect it at real data.
  final host = Uri.parse(_url).host;
  if (host != '127.0.0.1' && host != 'localhost') {
    throw StateError(
      'REFUSING TO RUN: SUPABASE_URL is "$_url", whose host is "$host". '
      'This suite creates and deletes accounts and soft-deletes households, '
      'so it only ever runs against a loopback stack. Start one with '
      '`supabase start` and re-run via tool/live_smoke.sh.',
    );
  }
  if (_anonKey.isEmpty || _serviceKey.isEmpty) {
    throw StateError(
      'REFUSING TO RUN: SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY must '
      'both be passed as --dart-define. `supabase status` prints both.',
    );
  }

  const gateway = SupabaseHouseholdGateway();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: _url,
      publishableKey: _anonKey,
      // EmptyLocalStorage: no shared_preferences platform channel, and no
      // session leaking between tests. detectSessionInUri off: there is no
      // deep-link observer to run in a test binding.
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
    _admin = SupabaseClient(
      _url,
      _serviceKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  group('F10 — remove a claimed member (spec §3.2)', () {
    test(
      'the owner removes a joined member: the profile survives, unclaimed, '
      'and the removed account loses its membership',
      () async {
        final owner = await _createUser();
        final other = await _createUser();

        await _signInAs(owner);
        final household = await _createHousehold(gateway);
        final code = await gateway.createInvite(household.householdId);

        final otherUserId = await _signInAs(other);
        final joinedMemberId =
            'm-joined-${DateTime.now().microsecondsSinceEpoch}';
        await gateway.joinAsNewMember(
          code: code,
          memberId: joinedMemberId,
          memberName: 'Joiner',
          memberColor: 0xFF4CAF50,
        );

        // Claimed by the second account, as the app would leave it.
        expect((await _memberRow(joinedMemberId))!['user_id'], otherUserId);

        await _signInAs(owner);
        await gateway.removeMember(joinedMemberId);

        // D-L: the PROFILE and its history stay with the household; only the
        // claim is severed. This is the assertion that would catch a server
        // change to a hard delete.
        final row = (await _memberRow(joinedMemberId))!;
        expect(row['user_id'], isNull, reason: 'the claim must be released');
        expect(row['name'], 'Joiner', reason: 'the profile must survive');

        // And the removed account really has lost the household.
        await _signInAs(other);
        expect(await gateway.findMyMembership(), isNull);
      },
    );

    test('removing your own row is rejected by the server (§2.2)', () async {
      final owner = await _createUser();
      await _signInAs(owner);
      final household = await _createHousehold(gateway);

      // The UI hides this (_DeleteGate.ownClaimedRow) and points at Leave.
      // The server is the backstop, and this proves the backstop is real
      // rather than assumed by the UI.
      await expectLater(
        gateway.removeMember(household.memberId),
        throwsA(isA<Object>()),
      );
      expect((await _memberRow(household.memberId))!['user_id'], isNotNull);
    });
  });

  group('F9 — leave the household (spec §2.2, D-L5)', () {
    test(
      'leaving with another claimed member present: the household survives '
      "and the leaver's profile stays claimable",
      () async {
        final owner = await _createUser();
        final other = await _createUser();

        await _signInAs(owner);
        final household = await _createHousehold(gateway);
        final code = await gateway.createInvite(household.householdId);

        await _signInAs(other);
        final joinedMemberId =
            'm-leaver-${DateTime.now().microsecondsSinceEpoch}';
        await gateway.joinAsNewMember(
          code: code,
          memberId: joinedMemberId,
          memberName: 'Leaver',
          memberColor: 0xFFFF9800,
        );

        await gateway.leaveHousehold(household.householdId);

        // The household is NOT cascaded: another claimed member remains.
        final hh = (await _householdRow(household.householdId))!;
        expect(hh['deleted_at'], isNull, reason: 'the household must survive');

        // The leaver's profile stays, unclaimed, so it is claimable again.
        final row = (await _memberRow(joinedMemberId))!;
        expect(row['user_id'], isNull);
        expect(row['deleted_at'], isNull);
        expect(row['name'], 'Leaver');

        // And the leaver no longer has a membership.
        expect(await gateway.findMyMembership(), isNull);
      },
    );

    test(
      'the LAST claimed member leaving cascades the household, and a '
      'previously issued invite code stops working (D-L5)',
      () async {
        final owner = await _createUser();
        await _signInAs(owner);
        final household = await _createHousehold(gateway);
        final code = await gateway.createInvite(household.householdId);

        await gateway.leaveHousehold(household.householdId);

        // The cascade the D-L5 warning promises the user.
        final hh = (await _householdRow(household.householdId))!;
        expect(
          hh['deleted_at'],
          isNotNull,
          reason: 'the last claimed member leaving must cascade (§2.4)',
        );

        // The invite issued before the cascade must not still let someone in.
        final joiner = await _createUser();
        await _signInAs(joiner);
        await expectLater(
          gateway.listClaimableMembers(code),
          throwsA(isA<Object>()),
          reason: 'an invite into a cascaded household must be rejected',
        );
      },
    );
  });

  group('F11 — delete the account (spec §2.2, D-L4)', () {
    test(
      'one RPC erases the auth row, with no edge function and no service key '
      'anywhere near the client',
      () async {
        final owner = await _createUser();
        final userId = await _signInAs(owner);
        final household = await _createHousehold(gateway);

        expect(await _authUserExists(userId), isTrue);

        await gateway.deleteAccount();

        // D-L4's whole claim: the single RPC really does reach auth.users.
        expect(
          await _authUserExists(userId),
          isFalse,
          reason: 'delete_account must erase the auth.users row itself',
        );

        // Sole claimed member, so the household cascades with it.
        expect(
          (await _householdRow(household.householdId))!['deleted_at'],
          isNotNull,
        );
      },
    );

    test(
      'deleting an account leaves the household and other members intact '
      'when somebody else is still claimed',
      () async {
        final owner = await _createUser();
        final leaver = await _createUser();

        await _signInAs(owner);
        final household = await _createHousehold(gateway);
        final code = await gateway.createInvite(household.householdId);

        final leaverUserId = await _signInAs(leaver);
        final joinedMemberId =
            'm-deleter-${DateTime.now().microsecondsSinceEpoch}';
        await gateway.joinAsNewMember(
          code: code,
          memberId: joinedMemberId,
          memberName: 'Deleter',
          memberColor: 0xFF9C27B0,
        );

        await gateway.deleteAccount();

        expect(await _authUserExists(leaverUserId), isFalse);
        // Profile and history stay with the household (D-L3/§2.2).
        final row = (await _memberRow(joinedMemberId))!;
        expect(row['user_id'], isNull);
        expect(row['name'], 'Deleter');
        expect(
          (await _householdRow(household.householdId))!['deleted_at'],
          isNull,
          reason: 'another claimed member remains, so no cascade',
        );
      },
    );

    test(
      'the session outlives the deleted account, which is exactly why the '
      'client must sign out itself',
      () async {
        final owner = await _createUser();
        final userId = await _signInAs(owner);
        await _createHousehold(gateway);

        await gateway.deleteAccount();

        // The finding that made HouseholdExitService.deleteAccount's local
        // sign-out load-bearing rather than cosmetic: GoTrue JWTs are
        // stateless, so the access token still works after the row is gone.
        // If this ever starts failing, the sign-out could be relaxed -- but
        // while it passes, dropping the sign-out would show a user who
        // deleted their own account the "you were removed" notice (§3.5).
        expect(await _authUserExists(userId), isFalse);
        expect(
          Supabase.instance.client.auth.currentSession,
          isNotNull,
          reason: 'the client still holds a session for a deleted account',
        );
        expect(
          await gateway.findMyMembership(),
          isNull,
          reason:
              'and it resolves, answering "no membership" -- '
              'indistinguishable from having been removed by somebody else',
        );
      },
    );
  });
}
