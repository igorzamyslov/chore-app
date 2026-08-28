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
library;

import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';

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

  /// The auth seam -- used only by `deleteAccount`, whose session is dead
  /// the moment the auth row is gone.
  final AuthGateway auth;

  /// This device's link state.
  final SettingsRepository settings;

  /// The local database, for the opt-in [resetAppData].
  final AppDatabase database;

  /// Leaves [householdId] (spec §2.2, F9).
  ///
  /// The server unclaims this account's member row and keeps the profile
  /// active, so the family still sees the person and their history and the
  /// profile can be claimed again later through an invite. If this account
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
  Future<void> leaveHousehold({
    required String householdId,
    required bool alsoDeleteLocalData,
  }) async {
    await gateway.leaveHousehold(householdId);
    await _finishLocally(alsoDeleteLocalData: alsoDeleteLocalData);
  }

  /// Deletes the signed-in account (spec §2.2, F11, D-L4).
  ///
  /// TEMPORARY, INCOMPLETE (slice 6's TDD red): the server call only, with
  /// neither the sign-out nor the local tail. The next commit finishes it.
  Future<void> deleteAccount({required bool alsoDeleteLocalData}) async {
    await gateway.deleteAccount();
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
