/// Client-side household-sync abstraction (spec
/// `docs/specs/sync-backend.md` §7.2) -- the second and last Supabase seam,
/// exactly parallel to `AuthGateway`/`lib/application/auth_gateway.dart` in
/// shape and laziness.
///
/// Widgets and the application-layer services built on this (e.g.
/// `HouseholdLinkService`, `lib/application/household_link_service.dart`)
/// depend on this interface, never on `Supabase.instance` directly -- see
/// [NoopHouseholdGateway], which `householdGatewayProvider`
/// (`lib/app/providers.dart`) returns whenever Supabase isn't configured.
/// Tests substitute their own fake (see
/// `test/features/settings/fake_household_gateway.dart`) rather than
/// exercising either implementation in this file directly.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/converters.dart';
import 'package:chore_app/data/repositories/household_repository.dart'
    show HouseholdSnapshot;
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
        for (final member in snapshot.members) _memberRow(member),
      ], ignoreDuplicates: true);
    }
    if (snapshot.categories.isNotEmpty) {
      await _client.from('categories').upsert([
        for (final category in snapshot.categories) _categoryRow(category),
      ]);
    }
    if (snapshot.chores.isNotEmpty) {
      await _client.from('chores').upsert([
        for (final chore in snapshot.chores) _choreRow(chore),
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
            _choreAssigneeRow(assignee, choreHouseholdIds),
        ],
        onConflict: 'chore_id,member_id',
      );
    }
    if (snapshot.choreOccurrences.isNotEmpty) {
      await _client.from('chore_occurrences').upsert([
        for (final occurrence in snapshot.choreOccurrences)
          _choreOccurrenceRow(occurrence, choreHouseholdIds),
      ]);
    }
    if (snapshot.shoppingItems.isNotEmpty) {
      await _client.from('shopping_items').upsert([
        for (final item in snapshot.shoppingItems) _shoppingItemRow(item),
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
          : _householdFromRow(householdRows.first),
      members: [for (final row in members) _memberFromRow(row)],
      categories: [for (final row in categories) _categoryFromRow(row)],
      chores: [for (final row in chores) _choreFromRow(row)],
      choreAssignees: [
        for (final row in choreAssignees) _choreAssigneeFromRow(row),
      ],
      choreOccurrences: [
        for (final row in choreOccurrences) _choreOccurrenceFromRow(row),
      ],
      shoppingItems: [
        for (final row in shoppingItems) _shoppingItemFromRow(row),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Row mapping: local typed drift rows <-> the server's snake_case/ISO
  // shape (per-table mapping read off
  // supabase/migrations/20260731120000_initial_schema.sql).

  Map<String, Object?> _memberRow(Member member) => {
    'id': member.id,
    'household_id': member.householdId,
    'name': member.name,
    'color': member.color,
    'role': member.role.name,
    'user_id': member.userId,
    'created_at': member.createdAt,
    'updated_at': member.updatedAt,
  };

  Member _memberFromRow(Map<String, Object?> row) => Member(
    id: row['id']! as String,
    householdId: row['household_id']! as String,
    name: row['name']! as String,
    color: (row['color']! as num).toInt(),
    role: MemberRole.values.byName(row['role']! as String),
    userId: row['user_id'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
  );

  Map<String, Object?> _categoryRow(Category category) => {
    'id': category.id,
    'household_id': category.householdId,
    'kind': category.kind.name,
    'name': category.name,
    'icon': category.icon,
    'color': category.color,
    'sort_order': category.sortOrder,
    'created_at': category.createdAt,
    'updated_at': category.updatedAt,
    'deleted_at': category.deletedAt,
  };

  Category _categoryFromRow(Map<String, Object?> row) => Category(
    id: row['id']! as String,
    householdId: row['household_id']! as String,
    kind: CategoryKind.values.byName(row['kind']! as String),
    name: row['name']! as String,
    icon: row['icon']! as String,
    color: (row['color']! as num).toInt(),
    sortOrder: (row['sort_order']! as num).toInt(),
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
    deletedAt: row['deleted_at'] as String?,
  );

  Map<String, Object?> _choreRow(Chore chore) => {
    'id': chore.id,
    'household_id': chore.householdId,
    'title': chore.title,
    'notes': chore.notes,
    'category_id': chore.categoryId,
    'recurrence': chore.recurrence == null
        ? null
        : const RecurrenceConverter().toSql(chore.recurrence!),
    'start_date': chore.startDate.toIso8601(),
    'assignment_mode': chore.assignmentMode.name,
    'paused_at': chore.pausedAt,
    'created_by': chore.createdBy,
    'created_at': chore.createdAt,
    'updated_at': chore.updatedAt,
    'deleted_at': chore.deletedAt,
  };

  Chore _choreFromRow(Map<String, Object?> row) => Chore(
    id: row['id']! as String,
    householdId: row['household_id']! as String,
    title: row['title']! as String,
    notes: row['notes'] as String?,
    categoryId: row['category_id'] as String?,
    recurrence: row['recurrence'] == null
        ? null
        : const RecurrenceConverter().fromSql(row['recurrence']! as String),
    startDate: const PlainDateConverter().fromSql(row['start_date']! as String),
    assignmentMode: AssignmentMode.values.byName(
      row['assignment_mode']! as String,
    ),
    pausedAt: row['paused_at'] as String?,
    createdBy: row['created_by'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
    deletedAt: row['deleted_at'] as String?,
  );

  Map<String, Object?> _choreAssigneeRow(
    ChoreAssignee assignee,
    Map<String, String> choreHouseholdIds,
  ) => {
    'chore_id': assignee.choreId,
    'member_id': assignee.memberId,
    'household_id': choreHouseholdIds[assignee.choreId],
    'position': assignee.position,
  };

  ChoreAssignee _choreAssigneeFromRow(Map<String, Object?> row) =>
      ChoreAssignee(
        choreId: row['chore_id']! as String,
        memberId: row['member_id']! as String,
        position: (row['position']! as num).toInt(),
      );

  Map<String, Object?> _choreOccurrenceRow(
    ChoreOccurrence occurrence,
    Map<String, String> choreHouseholdIds,
  ) => {
    'id': occurrence.id,
    'chore_id': occurrence.choreId,
    'household_id': choreHouseholdIds[occurrence.choreId],
    'due_date': occurrence.dueDate.toIso8601(),
    'status': occurrence.status.name,
    'assigned_member_id': occurrence.assignedMemberId,
    'completed_by': occurrence.completedBy,
    'closed_on': occurrence.closedOn?.toIso8601(),
    'created_at': occurrence.createdAt,
    'updated_at': occurrence.updatedAt,
  };

  ChoreOccurrence _choreOccurrenceFromRow(Map<String, Object?> row) =>
      ChoreOccurrence(
        id: row['id']! as String,
        choreId: row['chore_id']! as String,
        dueDate: const PlainDateConverter().fromSql(row['due_date']! as String),
        status: OccurrenceStatus.values.byName(row['status']! as String),
        assignedMemberId: row['assigned_member_id'] as String?,
        completedBy: row['completed_by'] as String?,
        closedOn: row['closed_on'] == null
            ? null
            : const PlainDateConverter().fromSql(row['closed_on']! as String),
        createdAt: row['created_at']! as String,
        updatedAt: row['updated_at']! as String,
      );

  Map<String, Object?> _shoppingItemRow(ShoppingItem item) => {
    'id': item.id,
    'household_id': item.householdId,
    'name': item.name,
    'quantity_note': item.quantityNote,
    'category_id': item.categoryId,
    'added_by': item.addedBy,
    'checked_at': item.checkedAt,
    'created_at': item.createdAt,
    'updated_at': item.updatedAt,
    'deleted_at': item.deletedAt,
  };

  ShoppingItem _shoppingItemFromRow(Map<String, Object?> row) => ShoppingItem(
    id: row['id']! as String,
    householdId: row['household_id']! as String,
    name: row['name']! as String,
    quantityNote: row['quantity_note'] as String?,
    categoryId: row['category_id'] as String?,
    addedBy: row['added_by'] as String?,
    checkedAt: row['checked_at'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
    deletedAt: row['deleted_at'] as String?,
  );

  Household _householdFromRow(Map<String, Object?> row) => Household(
    id: row['id']! as String,
    name: row['name']! as String,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
  );
}
