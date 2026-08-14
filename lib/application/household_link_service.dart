/// The P2b adopt flow ("Put my household online" -- spec
/// `docs/specs/sync-backend.md` §7.3), run from the Settings Account
/// section's adopt row (`lib/features/settings/account_section.dart`), and
/// its inverse, the A1.2 disconnect action (spec
/// `docs/feedback/2026-08-07-field-feedback.md`).
library;

import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// [HouseholdLinkService.adopt] cannot put this household online, ever, from
/// this device: its id already exists on the server AND this account cannot
/// read it, so it is not a half-finished adopt to resume but a household
/// this account has been removed from.
///
/// Terminal by construction, not by policy: household ids are preserved
/// verbatim by `create_household`, and `SettingsRepository.clearSyncLink`
/// (which the sync engine's revocation handling calls) keeps every local
/// row, so every retry re-sends the same taken id and hits the same unique
/// violation. The recourse is a fresh invite code redeemed through the P2c
/// join flow, which is what the Account section's blocked adopt row names.
///
/// Turning the local copy into an INDEPENDENT online household instead
/// ("fork") was considered and deliberately not built -- see OPD-1 in
/// `docs/plans/2026-08-14-reconnect-adopt-hardening.md` and its backlog row,
/// which records why a household-id-only re-key is insufficient.
@immutable
class HouseholdAlreadyOnlineFailure implements Exception {
  /// Creates the failure.
  const HouseholdAlreadyOnlineFailure();

  @override
  String toString() =>
      'HouseholdAlreadyOnlineFailure: this household is already on the '
      'server and this account is not a member of it, so adopting it from '
      'this device can never succeed.';
}

/// Uploads the local household to Supabase and marks this device linked.
///
/// [adopt] runs the spec's 4 steps in order and is safe to call again after
/// a failure at any point: every step is either idempotent (the upsert-based
/// step 2) or explicitly tolerant of having already run (step 1 -- see its
/// doc comment). The one exception is
/// [HouseholdAlreadyOnlineFailure], which is terminal rather than
/// retryable -- see that type.
class HouseholdLinkService {
  /// Creates the service.
  HouseholdLinkService({
    required this.gateway,
    required this.households,
    required this.settings,
    required this.clock,
  });

  /// The Supabase seam this service uploads through.
  final HouseholdGateway gateway;

  /// The local household repository -- source of the snapshot to upload,
  /// and of the acting member's post-adopt role flip.
  final HouseholdRepository households;

  /// The local settings repository -- records the linked state once
  /// adoption completes.
  final SettingsRepository settings;

  /// Used for [SettingsRepository.setSyncLinked]'s `linkedAt` timestamp.
  final Clock clock;

  /// Runs the adopt flow for [householdId] (the local household -- its id
  /// is preserved verbatim on the server) and [actingMemberId] (the
  /// caller's own member profile within it), claimed locally by
  /// [authUserId] (the signed-in auth user driving the flow).
  ///
  /// Throws [HouseholdAlreadyOnlineFailure] when step 1 reports the id is
  /// already taken AND the household is unreadable to this account -- a
  /// permanent dead end for this device, not a failure to retry.
  Future<void> adopt({
    required String householdId,
    required String actingMemberId,
    required String authUserId,
  }) async {
    final snapshot = await households.loadSnapshot(householdId);
    final household = snapshot.household;
    if (household == null) {
      throw StateError('No local household with id "$householdId".');
    }
    final actingMember = snapshot.members.firstWhere(
      (member) => member.id == actingMemberId,
      orElse: () =>
          throw StateError('Acting member "$actingMemberId" not found.'),
    );

    // Step 1: create the household + the acting member's claimed profile
    // (server makes it admin, links its user_id).
    try {
      await gateway.createHousehold(
        householdId: householdId,
        name: household.name,
        memberId: actingMember.id,
        memberName: actingMember.name,
        memberColor: actingMember.color,
      );
    } on Exception catch (error) {
      // Classify the step-1 failure. The readability probe is the same one
      // this method has always used; what changed is that its FALSE branch
      // is no longer assumed to be a retryable first-time failure.
      //
      // A network failure inside `downloadHousehold` itself propagates from
      // here before any classification happens, and that is correct: an
      // unreachable server is retryable, not terminal.
      final existing = await gateway.downloadHousehold(householdId);
      if (existing.household == null) {
        // NOT READABLE, and the id is TAKEN => terminal for this device and
        // this household id, forever. The household is on the server and
        // this account is not a member of it -- the state a removed member
        // reaches, because `SupabaseSyncEngine._pullSinceInner`'s
        // revocation handling calls `clearSyncLink()`, which keeps every
        // local row including the household's server id. Retrying re-sends
        // the same id and hits the same unique violation, so offering a
        // retry would be a lie.
        //
        // The comment this replaced claimed "a genuine first-time failure
        // instead finds no household yet ... so it rethrows", reading the
        // unreadable case as always-retryable. That is exactly what
        // Finding 3 disproved: the one caller for whom the resume probe
        // cannot fire is precisely the caller for whom retrying is
        // hopeless.
        if (error is HouseholdIdTakenFailure) {
          throw const HouseholdAlreadyOnlineFailure();
        }
        // NOT READABLE, id NOT taken => retryable, unchanged. Step 1 can
        // still succeed on a later attempt.
        rethrow;
      }
      // READABLE => resume, unchanged. A previous attempt already completed
      // step 1 and failed later, or this device disconnected (A1.2) and is
      // re-adopting: Disconnect leaves the caller's `user_id` on the server
      // member row, so `is_household_member` still passes and the household
      // reads back. Fall through to step 2.
    }

    // Step 2: upload everything else. The acting member is excluded --
    // step 1 already created it (with its user_id), so re-uploading the
    // local row (whose userId is always null -- see `tables.dart`) would
    // clobber that.
    await gateway.uploadHouseholdData(
      HouseholdSnapshot(
        members: [
          for (final member in snapshot.members)
            if (member.id != actingMemberId) member,
        ],
        categories: snapshot.categories,
        chores: snapshot.chores,
        choreAssignees: snapshot.choreAssignees,
        choreOccurrences: snapshot.choreOccurrences,
        shoppingItems: snapshot.shoppingItems,
      ),
    );

    // Step 3: mirror the server's role AND claim rules locally. Without
    // the claim, the row is dirty-and-unclaimed and `_applyPulled` skips
    // it, so this device would read its own profile as unclaimed until a
    // full push/pull round trip (spec §3.1 G-B).
    await households.setMemberRole(actingMemberId, MemberRole.admin);
    await households.setMemberUserId(actingMemberId, authUserId);

    // Step 3b: also record this device's own member as the stored acting
    // member, matching what both `HouseholdJoinService.join`/`joinFresh`
    // already do (spec `docs/specs/members-management.md` §4.2). While
    // pinned, `actingMemberProvider` prefers the claim
    // (`claimedMemberProvider`) the moment it resolves -- but that claim
    // only reaches THIS device once the sync engine's first pull applies
    // it (`applyPulledMember`), and there is a window right after adopting
    // (offline, or simply before that first pull) where it hasn't yet.
    // Without this write, `settings.actingMemberId` is still null in that
    // window and the acting member resolves to `null` rather than "this
    // device's own member" -- a silently inert completion tap
    // (`ChoresListScreen._complete`) for the one person who should least
    // ever see that.
    await settings.setActingMember(actingMemberId);

    // Step 4: mark this device linked -- only now that 1-2 have succeeded.
    await settings.setSyncLinked(
      householdId: householdId,
      linkedAt: clock.now(),
    );
  }

  /// Disconnects this device from its currently linked household (spec
  /// `docs/feedback/2026-08-07-field-feedback.md` A1.2): the missing exit
  /// from a stuck "signed out but still linked" state. Purely local and
  /// synchronous with [SettingsRepository.clearSyncLink] -- there is no
  /// server call, by design: the household stays exactly as it is on this
  /// device, the other members keep their household on the server, and
  /// this device's member row keeps its `user_id` there (so rejoining
  /// later via the P2d reconnect path, spec §7.6, still works).
  Future<void> disconnect() async {
    await settings.clearSyncLink();
  }
}
