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

/// Uploads the local household to Supabase and marks this device linked.
///
/// [adopt] runs the spec's 4 steps in order and is safe to call again after
/// a failure at any point: every step is either idempotent (the upsert-based
/// step 2) or explicitly tolerant of having already run (step 1 -- see its
/// doc comment).
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
    } on Exception {
      // Resuming after a half-success: if the household already exists
      // WITH the caller as a member (this exact retry already ran step 1
      // successfully before failing later), treat it as success and
      // continue to step 2. A genuine first-time failure instead finds no
      // household yet (RLS hides rows from non-members, and this
      // client-generated id can't collide with anyone else's), so it
      // rethrows.
      final existing = await gateway.downloadHousehold(householdId);
      if (existing.household == null) {
        rethrow;
      }
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
