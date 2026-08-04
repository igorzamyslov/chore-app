/// Shared local-typed-row <-> server-row (snake_case/ISO) mapping, per-table,
/// read off `supabase/migrations/20260731120000_initial_schema.sql`.
///
/// Extracted out of `SupabaseHouseholdGateway`
/// (`lib/application/household_gateway.dart`, spec
/// `docs/specs/sync-backend.md` §7.2) so the P3 sync engine
/// (`lib/application/sync_engine.dart`, spec §8) can reuse the exact same
/// mapping for its own per-table push/pull instead of duplicating it -- both
/// callers need identical column mapping, just at different granularities
/// (a full-household bulk transfer there; per-table dirty rows here).
///
/// The `*FromRow` functions (server row -> local typed row) always set
/// `syncDirty: false`: a row just read FROM the server is, by definition,
/// not locally dirty -- this is what makes both
/// `HouseholdGateway.downloadHousehold` (a fresh household this device has
/// never held before) and the sync engine's pull-apply (spec §8.3: "the
/// pull's row-replace" is one of only two places allowed to clear the flag)
/// correct without either caller having to remember to clear it themselves.
///
/// The `*Row` functions (local typed row -> server row) never include a
/// `sync_dirty` key: the server schema has no such column -- it's a
/// purely local, client-side bookkeeping concept.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/converters.dart';

/// Maps a local [Member] to the server's `members` row shape (push).
///
/// Includes `deleted_at` (schema v9, spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1): the server column has
/// existed since P1 and is already UPDATE-granted alongside `name`/
/// `color`/`role` (spec `docs/specs/sync-backend.md` §8.3) -- carrying it
/// on push is what lets a local soft-delete (`MemberService.deleteMember`)
/// actually propagate as a tombstone.
Map<String, Object?> memberRow(Member member) => {
  'id': member.id,
  'household_id': member.householdId,
  'name': member.name,
  'color': member.color,
  'role': member.role.name,
  'user_id': member.userId,
  'created_at': member.createdAt,
  'updated_at': member.updatedAt,
  'deleted_at': member.deletedAt,
};

/// Maps a server `members` row to a local [Member] (pull), always
/// `syncDirty: false` -- see this library's doc comment.
Member memberFromRow(Map<String, Object?> row) => Member(
  id: row['id']! as String,
  householdId: row['household_id']! as String,
  name: row['name']! as String,
  color: (row['color']! as num).toInt(),
  role: MemberRole.values.byName(row['role']! as String),
  userId: row['user_id'] as String?,
  createdAt: row['created_at']! as String,
  updatedAt: row['updated_at']! as String,
  deletedAt: row['deleted_at'] as String?,
  syncDirty: false,
);

/// Maps a local [Category] to the server's `categories` row shape (push).
Map<String, Object?> categoryRow(Category category) => {
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

/// Maps a server `categories` row to a local [Category] (pull), always
/// `syncDirty: false` -- see this library's doc comment.
Category categoryFromRow(Map<String, Object?> row) => Category(
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
  syncDirty: false,
);

/// Maps a local [Chore] to the server's `chores` row shape (push).
Map<String, Object?> choreRow(Chore chore) => {
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

/// Maps a server `chores` row to a local [Chore] (pull), always
/// `syncDirty: false` -- see this library's doc comment.
Chore choreFromRow(Map<String, Object?> row) => Chore(
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
  syncDirty: false,
);

/// Maps a local [ChoreAssignee] to the server's `chore_assignees` row shape
/// (push), denormalizing `household_id` off [choreHouseholdIds] (spec §2:
/// "the client fills it on push").
Map<String, Object?> choreAssigneeRow(
  ChoreAssignee assignee,
  Map<String, String> choreHouseholdIds,
) => {
  'chore_id': assignee.choreId,
  'member_id': assignee.memberId,
  'household_id': choreHouseholdIds[assignee.choreId],
  'position': assignee.position,
};

/// Maps a server `chore_assignees` row to a local [ChoreAssignee] (pull),
/// always `syncDirty: false` -- see this library's doc comment.
ChoreAssignee choreAssigneeFromRow(Map<String, Object?> row) => ChoreAssignee(
  choreId: row['chore_id']! as String,
  memberId: row['member_id']! as String,
  position: (row['position']! as num).toInt(),
  syncDirty: false,
);

/// Maps a local [ChoreOccurrence] to the server's `chore_occurrences` row
/// shape (push), denormalizing `household_id` off [choreHouseholdIds] (spec
/// §2: "the client fills it on push").
Map<String, Object?> choreOccurrenceRow(
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

/// Maps a server `chore_occurrences` row to a local [ChoreOccurrence]
/// (pull), always `syncDirty: false` -- see this library's doc comment.
ChoreOccurrence choreOccurrenceFromRow(Map<String, Object?> row) =>
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
      syncDirty: false,
    );

/// Maps a local [ShoppingItem] to the server's `shopping_items` row shape
/// (push).
Map<String, Object?> shoppingItemRow(ShoppingItem item) => {
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

/// Maps a server `shopping_items` row to a local [ShoppingItem] (pull),
/// always `syncDirty: false` -- see this library's doc comment.
ShoppingItem shoppingItemFromRow(Map<String, Object?> row) => ShoppingItem(
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
  syncDirty: false,
);

/// Push mapper for `households` -- new for the P3 sync engine (spec §8.3):
/// `HouseholdGateway.uploadHouseholdData` never uploads the household row
/// itself (it's created by the `create_household` RPC instead), but the
/// engine's `pushDirty` treats `households` like any other synced table.
/// Deliberately carries no `deleted_at` (the local `Households` table has no
/// such column -- households are never locally soft-deleted in this slice)
/// so a push never clobbers the server's value for a column local data
/// can't represent.
Map<String, Object?> householdRow(Household household) => {
  'id': household.id,
  'name': household.name,
  'created_at': household.createdAt,
  'updated_at': household.updatedAt,
};

/// Maps a server `households` row to a local [Household] (pull), always
/// `syncDirty: false` -- see this library's doc comment.
Household householdFromRow(Map<String, Object?> row) => Household(
  id: row['id']! as String,
  name: row['name']! as String,
  createdAt: row['created_at']! as String,
  updatedAt: row['updated_at']! as String,
  syncDirty: false,
);
