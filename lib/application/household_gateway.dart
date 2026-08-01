/// Client-side household-sync abstraction (spec
/// `docs/specs/sync-backend.md` §7.2) -- the second Supabase seam (P2),
/// exactly parallel to `AuthGateway`/`lib/application/auth_gateway.dart` in
/// shape and laziness. P3 (spec §8) adds a third, narrower one --
/// `SyncTransport` (`lib/application/sync_engine.dart`) -- for the ongoing
/// ENGINE's ROW-level push/pull; this file's two bulk paths
/// (`uploadHouseholdData`/`downloadHousehold`) stay P2b/P2c-only (adopt's
/// initial upload, join's initial download).
///
/// Widgets and the application-layer services built on this (e.g.
/// `HouseholdLinkService`, `lib/application/household_link_service.dart`)
/// depend on this interface, never on `Supabase.instance` directly -- see
/// [NoopHouseholdGateway], which `householdGatewayProvider`
/// (`lib/app/providers.dart`) returns whenever Supabase isn't configured.
/// Tests substitute their own fake (see
/// `test/features/settings/fake_household_gateway.dart`) rather than
/// exercising either implementation in this file directly.
///
/// Row mapping (local typed drift rows <-> the server's snake_case/ISO
/// shape) lives in `lib/data/sync/row_mappers.dart`, shared with the P3
/// engine rather than duplicated here.
library;

import 'package:chore_app/data/repositories/household_repository.dart'
    show HouseholdSnapshot;
import 'package:chore_app/data/sync/row_mappers.dart' as row_mappers;
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// One unclaimed member profile offered by `list_claimable_members` during
/// the P2c join flow ("Are you Anna?").
@immutable
class ClaimableMember {
  /// Creates a claimable-member entry.
  const ClaimableMember({
    required this.memberId,
    required this.name,
    required this.color,
  });

  /// The unclaimed member row's id.
  final String memberId;

  /// The unclaimed member's display name.
  final String name;

  /// The unclaimed member's ARGB color.
  final int color;

  @override
  bool operator ==(Object other) =>
      other is ClaimableMember &&
      other.memberId == memberId &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(memberId, name, color);

  @override
  String toString() => 'ClaimableMember($memberId, $name, $color)';
}

/// The caller's own already-claimed member profile, as found by
/// `HouseholdGateway.findMyMembership` (spec §7.6, P2d reconnect): a
/// returning device (phone reset, new phone) whose signed-in account is
/// already a member of a household this DEVICE isn't currently linked to.
@immutable
class MyMembership {
  /// Creates a membership result.
  const MyMembership({
    required this.householdId,
    required this.memberId,
    required this.memberName,
    required this.householdName,
  });

  /// The household the caller's account is already a member of.
  final String householdId;

  /// The caller's already-claimed member profile id in [householdId].
  final String memberId;

  /// The already-claimed member's display name.
  final String memberName;

  /// [householdId]'s name, for the reconnect row's "Reconnect to
  /// {householdName}" copy.
  final String householdName;

  @override
  bool operator ==(Object other) =>
      other is MyMembership &&
      other.householdId == householdId &&
      other.memberId == memberId &&
      other.memberName == memberName &&
      other.householdName == householdName;

  @override
  int get hashCode =>
      Object.hash(householdId, memberId, memberName, householdName);

  @override
  String toString() =>
      'MyMembership($householdId, $memberId, $memberName, $householdName)';
}

/// The narrow seam between the app's household data and the Supabase
/// backend (spec `docs/specs/sync-backend.md` §7.2): household/invite
/// bootstrap RPCs, plus the two bulk data-transfer paths.
abstract class HouseholdGateway {
  /// RPC `create_household`: creates the household (with the LOCAL
  /// [householdId] and [name], preserved verbatim -- the RPC takes client
  /// UUIDs) and the acting member's claimed profile ([memberId],
  /// [memberName], [memberColor]); the server makes that member `admin`
  /// and links its `user_id` to the caller.
  Future<void> createHousehold({
    required String householdId,
    required String name,
    required String memberId,
    required String memberName,
    required int memberColor,
  });

  /// PostgREST upserts of everything else in [snapshot] -- members (the
  /// non-caller ones; `user_id` stays `null`), categories, chores,
  /// chore-assignees, chore-occurrences, then shopping items, in that FK
  /// order. Rows travel verbatim, tombstones included. Idempotent, so a
  /// failed upload is re-runnable as-is (members via insert-with-ignore
  /// rather than upsert -- see the implementation for the grants reason).
  Future<void> uploadHouseholdData(HouseholdSnapshot snapshot);

  /// RPC `create_invite`: creates an 8-character invite code for
  /// [householdId] (member-only).
  Future<String> createInvite(String householdId);

  /// RPC `list_claimable_members`: the unclaimed member profiles [code]'s
  /// household offers for the P2c "Are you Anna?" claiming step.
  Future<List<ClaimableMember>> listClaimableMembers(String code);

  /// RPC `claim_member`: links the caller's `user_id` to the unclaimed
  /// [memberId] profile redeemed via [code]; returns the household id.
  Future<String> claimMember(String code, String memberId);

  /// RPC `join_as_new_member`: inserts a fresh member row ([memberId],
  /// [memberName], [memberColor]) linked to the caller, via [code]; returns
  /// the household id.
  Future<String> joinAsNewMember({
    required String code,
    required String memberId,
    required String memberName,
    required int memberColor,
  });

  /// Plain selects (RLS-scoped) of every row belonging to [householdId],
  /// as a [HouseholdSnapshot].
  Future<HouseholdSnapshot> downloadHousehold(String householdId);

  /// Spec §7.6 (P2d reconnect): PostgREST select on `members` where
  /// `user_id = auth.uid()` (RLS-scoped anyway), limit 1, plus a second
  /// select on `households` for that row's name -- looks up whether the
  /// caller's signed-in account is ALREADY a claimed member of some
  /// household (a returning device: phone reset, new phone). Returns
  /// `null` when the caller has no membership anywhere.
  Future<MyMembership?> findMyMembership();
}

/// The always-throwing [HouseholdGateway] returned by
/// `householdGatewayProvider` whenever Supabase isn't configured.
///
/// Every method throws [StateError]: unlike `NoopAuthGateway`'s
/// `sendMagicLink`, none of these calls is reachable in practice -- every
/// call site (the adopt flow, the Members screen's invite row) is gated on
/// a signed-in user, which `NoopAuthGateway` never produces.
class NoopHouseholdGateway implements HouseholdGateway {
  /// Creates the no-op gateway.
  const NoopHouseholdGateway();

  @override
  Future<void> createHousehold({
    required String householdId,
    required String name,
    required String memberId,
    required String memberName,
    required int memberColor,
  }) => _unreachable();

  @override
  Future<void> uploadHouseholdData(HouseholdSnapshot snapshot) =>
      _unreachable();

  @override
  Future<String> createInvite(String householdId) => _unreachable();

  @override
  Future<List<ClaimableMember>> listClaimableMembers(String code) =>
      _unreachable();

  @override
  Future<String> claimMember(String code, String memberId) => _unreachable();

  @override
  Future<String> joinAsNewMember({
    required String code,
    required String memberId,
    required String memberName,
    required int memberColor,
  }) => _unreachable();

  @override
  Future<HouseholdSnapshot> downloadHousehold(String householdId) =>
      _unreachable();

  @override
  Future<MyMembership?> findMyMembership() => _unreachable();

  Never _unreachable() => throw StateError(
    'Supabase is not configured; HouseholdGateway is unreachable -- every '
    'call site is gated on a signed-in user, which NoopAuthGateway never '
    'produces.',
  );
}

/// The production [HouseholdGateway]: a thin wrapper over
/// `Supabase.instance.client`'s RPCs and PostgREST table access.
///
/// `Supabase.instance` is only ever touched lazily, inside each method call
/// below -- never from this class's constructor -- mirroring
/// `SupabaseAuthGateway`.
class SupabaseHouseholdGateway implements HouseholdGateway {
  /// Creates a gateway over the app's Supabase client. `Supabase.
  /// initialize()` must have already run (see `main.dart`) before any
  /// method on this class is called.
  const SupabaseHouseholdGateway();

  supabase.SupabaseClient get _client => supabase.Supabase.instance.client;

  @override
  Future<void> createHousehold({
    required String householdId,
    required String name,
    required String memberId,
    required String memberName,
    required int memberColor,
  }) async {
    await _client.rpc<dynamic>(
      'create_household',
      params: {
        'p_household_id': householdId,
        'p_name': name,
        'p_member_id': memberId,
        'p_member_name': memberName,
        'p_color': memberColor,
      },
    );
  }

  @override
  Future<void> uploadHouseholdData(HouseholdSnapshot snapshot) async {
    if (snapshot.members.isNotEmpty) {
      // `ignoreDuplicates` (ON CONFLICT DO NOTHING), NOT a plain upsert:
      // the server's fail-closed grants give `authenticated` UPDATE on
      // members for (name, color, role, deleted_at) ONLY, and Postgres
      // checks UPDATE privilege on every column in an ON CONFLICT DO
      // UPDATE SET list at plan time — conflict or not — so a plain
      // upsert of full member rows is rejected outright (42501). DO
      // NOTHING needs no UPDATE privilege and keeps the retry semantics
      // this method promises: a re-run skips already-uploaded rows.
      await _client.from('members').upsert([
        for (final member in snapshot.members) row_mappers.memberRow(member),
      ], ignoreDuplicates: true);
    }
    if (snapshot.categories.isNotEmpty) {
      await _client.from('categories').upsert([
        for (final category in snapshot.categories)
          row_mappers.categoryRow(category),
      ]);
    }
    if (snapshot.chores.isNotEmpty) {
      await _client.from('chores').upsert([
        for (final chore in snapshot.chores) row_mappers.choreRow(chore),
      ]);
    }
    // chore_assignees/chore_occurrences denormalize household_id (spec §2:
    // "the client fills it on push") -- neither local row carries it
    // directly (see `tables.dart`), so it's looked up via each row's own
    // chore, which does carry `householdId`.
    final choreHouseholdIds = {
      for (final chore in snapshot.chores) chore.id: chore.householdId,
    };
    if (snapshot.choreAssignees.isNotEmpty) {
      await _client.from('chore_assignees').upsert(
        [
          for (final assignee in snapshot.choreAssignees)
            row_mappers.choreAssigneeRow(assignee, choreHouseholdIds),
        ],
        onConflict: 'chore_id,member_id',
      );
    }
    if (snapshot.choreOccurrences.isNotEmpty) {
      await _client.from('chore_occurrences').upsert([
        for (final occurrence in snapshot.choreOccurrences)
          row_mappers.choreOccurrenceRow(occurrence, choreHouseholdIds),
      ]);
    }
    if (snapshot.shoppingItems.isNotEmpty) {
      await _client.from('shopping_items').upsert([
        for (final item in snapshot.shoppingItems)
          row_mappers.shoppingItemRow(item),
      ]);
    }
  }

  @override
  Future<String> createInvite(String householdId) async {
    final result = await _client.rpc<dynamic>(
      'create_invite',
      params: {'p_household_id': householdId},
    );
    return result as String;
  }

  @override
  Future<List<ClaimableMember>> listClaimableMembers(String code) async {
    final rows = await _client.rpc<dynamic>(
      'list_claimable_members',
      params: {'p_code': code},
    );
    return [
      for (final row in rows as List)
        ClaimableMember(
          memberId: (row as Map<String, dynamic>)['member_id'] as String,
          name: row['member_name'] as String,
          color: (row['member_color'] as num).toInt(),
        ),
    ];
  }

  @override
  Future<String> claimMember(String code, String memberId) async {
    final result = await _client.rpc<dynamic>(
      'claim_member',
      params: {'p_code': code, 'p_member_id': memberId},
    );
    return result as String;
  }

  @override
  Future<String> joinAsNewMember({
    required String code,
    required String memberId,
    required String memberName,
    required int memberColor,
  }) async {
    final result = await _client.rpc<dynamic>(
      'join_as_new_member',
      params: {
        'p_code': code,
        'p_member_id': memberId,
        'p_member_name': memberName,
        'p_color': memberColor,
      },
    );
    return result as String;
  }

  @override
  Future<HouseholdSnapshot> downloadHousehold(String householdId) async {
    final householdRows = await _client
        .from('households')
        .select()
        .eq('id', householdId)
        .limit(1);
    final members = await _client
        .from('members')
        .select()
        .eq('household_id', householdId);
    final categories = await _client
        .from('categories')
        .select()
        .eq('household_id', householdId);
    final chores = await _client
        .from('chores')
        .select()
        .eq('household_id', householdId);
    final choreAssignees = await _client
        .from('chore_assignees')
        .select()
        .eq('household_id', householdId);
    final choreOccurrences = await _client
        .from('chore_occurrences')
        .select()
        .eq('household_id', householdId);
    final shoppingItems = await _client
        .from('shopping_items')
        .select()
        .eq('household_id', householdId);

    return HouseholdSnapshot(
      household: householdRows.isEmpty
          ? null
          : row_mappers.householdFromRow(householdRows.first),
      members: [for (final row in members) row_mappers.memberFromRow(row)],
      categories: [
        for (final row in categories) row_mappers.categoryFromRow(row),
      ],
      chores: [for (final row in chores) row_mappers.choreFromRow(row)],
      choreAssignees: [
        for (final row in choreAssignees) row_mappers.choreAssigneeFromRow(row),
      ],
      choreOccurrences: [
        for (final row in choreOccurrences)
          row_mappers.choreOccurrenceFromRow(row),
      ],
      shoppingItems: [
        for (final row in shoppingItems) row_mappers.shoppingItemFromRow(row),
      ],
    );
  }

  @override
  Future<MyMembership?> findMyMembership() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      // No signed-in session to look up -- unreachable in practice (see the
      // interface doc comment/`myMembershipProvider`, which never calls
      // this without one), but a `null` result is still the right answer.
      return null;
    }
    final memberRows = await _client
        .from('members')
        .select()
        .eq('user_id', userId)
        .limit(1);
    if (memberRows.isEmpty) {
      return null;
    }
    final memberRow = memberRows.first;
    final householdId = memberRow['household_id']! as String;
    final householdRows = await _client
        .from('households')
        .select()
        .eq('id', householdId)
        .limit(1);
    return MyMembership(
      householdId: householdId,
      memberId: memberRow['id']! as String,
      memberName: memberRow['name']! as String,
      householdName: householdRows.isEmpty
          ? ''
          : householdRows.first['name']! as String,
    );
  }
}
