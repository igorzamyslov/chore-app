/// The two account-scoped household exits (spec
/// `docs/specs/household-lifecycle.md` §2.2): leaving a household (F9) and
/// deleting the account (F11). Member removal (F10) is not here -- it acts
/// on somebody ELSE's row and belongs with the rest of the member
/// referential cleanup in `MemberService`.
///
/// Both exits share one shape, in this order:
///
/// 1. the server RPC, which is the authoritative part;
/// 2. this device's local link state (`clearSyncLink`, which also nulls
///    every local `members.userId` -- §3.1 G-A);
/// 3. optionally, and ONLY when the caller explicitly asked
///    (`alsoDeleteLocalData`, unchecked by default -- D-L3), `resetAppData`.
///
/// The server call goes FIRST on purpose: if it fails, nothing local has
/// changed and a retry is an ordinary retry rather than a repair.
///
/// They differ in exactly one place: `deleteAccount` signs out between
/// steps 1 and 2, `leaveHousehold` deliberately does not (D-L8 -- leaving a
/// household is not leaving the app).
library;

import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';

/// A rename-on-exit request (persona review D8): the caller's own member row
/// `memberId` should carry `name` in the household's history from now on.
typedef ExitRename = ({String memberId, String name});

/// Runs the leave-household and delete-account exits.
class HouseholdExitService {
  /// Creates the service.
  HouseholdExitService({
    required this.gateway,
    required this.auth,
    required this.settings,
    required this.database,
  });

  /// The Supabase seam the exit RPCs go through.
  final HouseholdGateway gateway;

  /// The auth seam -- used only by `deleteAccount`, which signs this device
  /// out as part of the erasure. NOT because the session dies with the auth
  /// row: it does not, and assuming so is the mistake
  /// [HouseholdGateway.deleteAccount] documents at length. See
  /// [deleteAccount].
  final AuthGateway auth;

  /// This device's link state.
  final SettingsRepository settings;

  /// The local database, for the opt-in [resetAppData].
  final AppDatabase database;

  /// Leaves [householdId] (spec §2.2, F9).
  ///
  /// The server unclaims AND soft-deletes this account's member row
  /// (amendment 2026-10-06): the family stops seeing the person in
  /// rotations, while their history keeps the name. If this account
  /// was the LAST claimed member, the server also cascades the household
  /// (§2.4, D-L5) -- the caller is responsible for having said so in the
  /// confirm (§3.4); this method does not decide, it reports nothing back,
  /// and the cascade is recomputed server-side either way.
  ///
  /// Does NOT sign the account out (D-L8): leaving a household is not
  /// leaving the app, and the Account section immediately offers
  /// reconnect/adopt/join.
  ///
  /// [alsoDeleteLocalData] is the D-L3 opt-in and is `false` in every
  /// default path. Callers must invalidate `settingsProvider` afterwards
  /// when it was `true` (the documented `resetAppData` contract).
  ///
  /// [rename], when set, renames the leaver's profile FIRST (see
  /// [_renameBeforeExit]). Unless [lastClaimedMember] (the cascade case) or
  /// [alsoDeleteLocalData], a successful leave stamps `settings.syncLeftAt`:
  /// this phone's copy is now the leaver's own, so the Account section stops
  /// offering to put it online again (persona review D8).
  Future<void> leaveHousehold({
    required String householdId,
    required bool alsoDeleteLocalData,
    ExitRename? rename,
    bool lastClaimedMember = false,
  }) async {
    await _renameBeforeExit(rename);
    await gateway.leaveHousehold(householdId);
    await _finishLocally(alsoDeleteLocalData: alsoDeleteLocalData);
    if (!lastClaimedMember && !alsoDeleteLocalData) {
      await settings.setSyncLeftAt(settings.nowUtc());
    }
  }

  /// Deletes the signed-in account (spec §2.2, F11, D-L4).
  ///
  /// The server unclaims this account's member row in EVERY household it
  /// belongs to, cascades any household left with no claimed members
  /// (§2.4), and erases the `auth.users` row. Then this device signs out.
  ///
  /// **The sign-out is load-bearing, not bookkeeping** -- see
  /// [HouseholdGateway.deleteAccount], which spells out why callers must not
  /// assume the session dies with the auth row. GoTrue JWTs are stateless:
  /// deleting the row cascades refresh tokens and server-side sessions, but
  /// an already-issued access token keeps working until its `exp`. For the
  /// rest of that window `auth.uid()` still resolves while every claim is
  /// already nulled, so a pull's `hasMembership` probe SUCCEEDS and answers
  /// false -- indistinguishable from having been removed by somebody else,
  /// which would hand the user §3.5's "you were removed" notice for
  /// something they did themselves. Signing out here, before any pull can
  /// observe that state, is what prevents it.
  ///
  /// A FAILING sign-out is nevertheless tolerated, and that is not a
  /// contradiction. The erasure has already happened; [_finishLocally] runs
  /// immediately afterwards, and `syncEngineProvider` is gated on
  /// `settings.syncHouseholdId`, so the unlink closes the same window from
  /// the other side. Aborting here would instead leave this device LINKED to
  /// a server side that no longer exists -- the §0.1 silent-stale trap slice
  /// 3 exists to prevent.
  ///
  /// [alsoDeleteLocalData] is the D-L3 opt-in, `false` by default here
  /// exactly as in the other two exits: GDPR erasure covers the server copy
  /// and the account, not the user's own device. Callers must invalidate
  /// `settingsProvider` afterwards when it was `true` (the documented
  /// [resetAppData] contract).
  ///
  /// [rename], when set, renames the account's profile in the linked
  /// household FIRST (see [_renameBeforeExit]) -- `delete_account` keeps the
  /// profile and its display name, so this is the one chance to change it.
  Future<void> deleteAccount({
    required bool alsoDeleteLocalData,
    ExitRename? rename,
  }) async {
    await _renameBeforeExit(rename);
    await gateway.deleteAccount();
    try {
      await auth.signOut();
    } on Object catch (e, s) {
      AppLog.error('app.deleteAccountSignOut', e, s);
      // `on Object`, not `on Exception`, and best-effort. The account is
      // already erased, so the one outcome this may never produce is
      // abandoning the unlink below: an `Error` -- a `StateError` out of a
      // closed client, a `LateInitializationError` out of an uninitialised
      // Supabase client -- escapes an `on Exception` clause and would strand
      // this device linked to a server side that is gone. The realistic
      // failure is mundane, too: the sign-out round trip can legitimately
      // fail precisely BECAUSE the account it names no longer exists.
    }
    await _finishLocally(alsoDeleteLocalData: alsoDeleteLocalData);
  }

  /// Rename-on-exit (persona review D8, Priya): runs BEFORE the exit RPC,
  /// while this account is still a member and RLS still admits the write --
  /// afterwards it could not. Server first, through the gateway rather than
  /// the sync engine, because the exit unlinks this device right after and
  /// a dirty row would never be pushed; then the local row, through the
  /// ordinary member update path, so this phone's history agrees.
  ///
  /// A failed server rename throws before anything else has happened, so
  /// the caller's "nothing was changed" error copy stays accurate.
  Future<void> _renameBeforeExit(ExitRename? rename) async {
    if (rename == null) {
      return;
    }
    await gateway.renameMember(rename.memberId, rename.name);
    await HouseholdRepository(
      database,
    ).renameMember(rename.memberId, rename.name);
  }

  /// Shared local tail of both exits, reached only once the server RPC has
  /// already succeeded.
  ///
  /// The two settings writes are in this order deliberately, and swapping
  /// them is a regression on two counts:
  ///
  /// - **Unlinking closes the race the flag-clear exists for.**
  ///   `syncEngineProvider` is gated on `settings.syncHouseholdId`, so a
  ///   pull can only run while the device is still linked. Clearing the
  ///   link first means no later pull can set the revocation flag at all;
  ///   clearing the flag first leaves a window in which a pull already in
  ///   flight sets it straight back.
  /// - **The load-bearing write goes first.** A throw between the two would
  ///   otherwise leave this device LINKED while the server has already
  ///   unclaimed it -- the §0.1 silent-stale trap that slice 3 exists to
  ///   prevent.
  Future<void> _finishLocally({required bool alsoDeleteLocalData}) async {
    await settings.clearSyncLink();
    // Defensive: a pull in flight while the user was reading the confirm
    // could have set slice 3's revocation flag (§3.5). Somebody who chose
    // to leave must not then be told they were removed.
    try {
      await settings.clearMembershipRevoked();
    } on Object {
      // `on Object`, not `on Exception`, and best-effort: clearing this flag
      // is cosmetic, while the wipe below is something the user explicitly
      // confirmed. An `Error` -- a `StateError` out of a closed drift
      // connection, say -- escapes an `on Exception` clause and would take
      // that wipe down with it, which is the one outcome this flow may
      // never produce. Same reasoning as `reset_flow.dart`'s `_signOut`.
    }
    if (alsoDeleteLocalData) {
      await resetAppData(database);
    }
  }
}
