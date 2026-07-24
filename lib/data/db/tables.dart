/// Drift table definitions for the local data layer, plus the Dart enums
/// stored in their `TEXT` columns.
///
/// Conventions applied throughout (see `docs/specs/data-layer.md`):
/// - `id` columns are client-generated UUIDv4 `TEXT` primary keys.
/// - `createdAt` / `updatedAt` are `TEXT` ISO-8601 UTC timestamps with
///   milliseconds, set by the repository layer (not the database).
/// - `deletedAt` (where present) is a nullable `TEXT` timestamp; `NULL`
///   means the row is active.
library;

import 'package:chore_app/data/db/converters.dart';
import 'package:drift/drift.dart';

/// A member's permission level within a household.
enum MemberRole {
  /// Can manage household-wide settings (categories, other members).
  admin,

  /// A regular household member.
  member,
}

/// Which part of the app a category organizes.
enum CategoryKind {
  /// A category used to group chores.
  chore,

  /// A category used to group shopping list items.
  shopping,
}

/// How a chore's occurrences are assigned to members.
enum AssignmentMode {
  /// Always assigned to the same single member.
  fixed,

  /// Assigned to members in turn, following [ChoreAssignees.position].
  rotation,

  /// Not assigned to anyone in particular.
  anyone,
}

/// The lifecycle state of a single chore occurrence.
enum OccurrenceStatus {
  /// Not yet acted upon; the currently-active occurrence of its chore.
  pending,

  /// Completed by a member.
  done,

  /// Explicitly skipped.
  skipped,

  /// Not completed in time.
  missed,
}

/// The household that owns every other row in the database.
///
/// v1 note: there is exactly one local household per device (see
/// `HouseholdRepository.ensureLocalHousehold`); the table exists as its own
/// entity so a future multi-household / sync design doesn't require a
/// schema rewrite.
@DataClassName('Household')
class Households extends Table {
  /// UUIDv4 primary key.
  TextColumn get id => text()();

  /// Display name of the household.
  TextColumn get name => text()();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A local (no-account) profile within a household.
///
/// v1 note: members are local profiles only — a family shares one
/// device-local household until a sync layer lands.
@DataClassName('Member')
class Members extends Table {
  /// UUIDv4 primary key.
  TextColumn get id => text()();

  /// The household this member belongs to.
  TextColumn get householdId => text().references(Households, #id)();

  /// Display name.
  TextColumn get name => text()();

  /// ARGB color used to represent this member in the UI.
  IntColumn get color => integer()();

  /// This member's permission level.
  TextColumn get role =>
      text().map(const EnumNameConverter(MemberRole.values))();

  /// Future auth-provider user id mapping; unused in v1.
  TextColumn get userId => text().nullable()();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A user-defined grouping for chores or shopping items.
@DataClassName('Category')
class Categories extends Table {
  /// UUIDv4 primary key.
  TextColumn get id => text()();

  /// The household this category belongs to.
  TextColumn get householdId => text().references(Households, #id)();

  /// Whether this category organizes chores or shopping items.
  TextColumn get kind =>
      text().map(const EnumNameConverter(CategoryKind.values))();

  /// Display name.
  TextColumn get name => text()();

  /// Material Symbols icon identifier, e.g. `cleaning_services`.
  TextColumn get icon => text()();

  /// ARGB color used to represent this category in the UI.
  IntColumn get color => integer()();

  /// Manual ordering position among categories of the same [kind].
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Device-level app settings (spec `docs/specs/notifications.md`): a single
/// row (`id` is always `'device'`) holding the daily digest notification
/// preferences.
///
/// v1 note: settings are per-device, not per-household or per-member (there
/// is no notion of "per-member notification preferences" until accounts
/// exist) — this is why, unlike every other table in this file, this one
/// has no `householdId` foreign key. Added in schemaVersion 2; see
/// `AppDatabase.migration`.
@DataClassName('DeviceSettings')
class Settings extends Table {
  /// Constant primary key `'device'`; exactly one row ever exists.
  TextColumn get id => text()();

  /// Whether the daily digest notification is enabled.
  BoolColumn get digestEnabled => boolean().withDefault(const Constant(true))();

  /// The digest's fire time, as minutes since local midnight (default `480`
  /// = 08:00).
  IntColumn get digestMinutes => integer().withDefault(const Constant(480))();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A (possibly recurring) task assigned within a household.
@DataClassName('Chore')
class Chores extends Table {
  /// UUIDv4 primary key.
  TextColumn get id => text()();

  /// The household this chore belongs to.
  TextColumn get householdId => text().references(Households, #id)();

  /// Display title.
  TextColumn get title => text()();

  /// Optional free-text notes.
  TextColumn get notes => text().nullable()();

  /// Optional category.
  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  /// The recurrence rule, or `NULL` for a one-off chore.
  TextColumn get recurrence => text().nullable().map(
    const NullAwareTypeConverter.wrap(RecurrenceConverter()),
  )();

  /// The date of the first occurrence / the anchor date for recurrence
  /// math.
  TextColumn get startDate => text().map(const PlainDateConverter())();

  /// How occurrences of this chore are assigned to members.
  TextColumn get assignmentMode =>
      text().map(const EnumNameConverter(AssignmentMode.values))();

  /// Timestamp at which this chore was paused; `NULL` means unpaused.
  TextColumn get pausedAt => text().nullable()();

  /// The member who created this chore, if known.
  TextColumn get createdBy => text().nullable().references(Members, #id)();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Join table assigning members to a chore, in rotation order.
///
/// For [AssignmentMode.fixed]: exactly one row. For
/// [AssignmentMode.rotation]: 2 or more rows ordered by [position]. For
/// [AssignmentMode.anyone]: zero rows.
@DataClassName('ChoreAssignee')
class ChoreAssignees extends Table {
  /// The chore being assigned.
  TextColumn get choreId => text().references(Chores, #id)();

  /// The assigned member.
  TextColumn get memberId => text().references(Members, #id)();

  /// 0-based rotation order.
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {choreId, memberId};
}

/// A single due instance of a chore.
///
/// Hard-deleted only via a chore's soft-delete cleanup (its pending
/// occurrence, if any) — history rows (done/skipped/missed) are otherwise
/// retained forever.
@TableIndex(
  name: 'chore_occurrences_chore_status_idx',
  columns: {#choreId, #status},
)
@TableIndex(
  name: 'chore_occurrences_status_due_date_idx',
  columns: {#status, #dueDate},
)
@DataClassName('ChoreOccurrence')
class ChoreOccurrences extends Table {
  /// UUIDv4 primary key.
  TextColumn get id => text()();

  /// The chore this occurrence belongs to.
  TextColumn get choreId => text().references(Chores, #id)();

  /// The calendar date this occurrence is due.
  TextColumn get dueDate => text().map(const PlainDateConverter())();

  /// The current lifecycle state.
  TextColumn get status => text()
      .withDefault(Constant(OccurrenceStatus.pending.name))
      .map(const EnumNameConverter(OccurrenceStatus.values))();

  /// The member this occurrence is assigned to, if any.
  TextColumn get assignedMemberId =>
      text().nullable().references(Members, #id)();

  /// The member who completed this occurrence, if any.
  TextColumn get completedBy => text().nullable().references(Members, #id)();

  /// The calendar date the user closed this occurrence on, if closed.
  TextColumn get closedOn => text().nullable().map(
    const NullAwareTypeConverter.wrap(PlainDateConverter()),
  )();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A single entry on a household's shared shopping list.
@DataClassName('ShoppingItem')
class ShoppingItems extends Table {
  /// UUIDv4 primary key.
  TextColumn get id => text()();

  /// The household this item belongs to.
  TextColumn get householdId => text().references(Households, #id)();

  /// Display name.
  TextColumn get name => text()();

  /// Optional free-text quantity or note, e.g. `"2 bottles"`.
  TextColumn get quantityNote => text().nullable()();

  /// Optional category.
  TextColumn get categoryId => text().nullable().references(Categories, #id)();

  /// The member who added this item, if known.
  TextColumn get addedBy => text().nullable().references(Members, #id)();

  /// Timestamp at which this item was checked off; `NULL` means unchecked.
  TextColumn get checkedAt => text().nullable()();

  /// ISO-8601 UTC creation timestamp.
  TextColumn get createdAt => text()();

  /// ISO-8601 UTC timestamp of the last update.
  TextColumn get updatedAt => text()();

  /// ISO-8601 UTC soft-delete timestamp; `NULL` means active.
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
