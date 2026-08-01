/// Low-level, per-table data access for the P3 sync engine
/// (`lib/application/sync_engine.dart`, spec `docs/specs/sync-backend.md`
/// §8): selecting dirty rows to push, clearing the flag on exactly the rows
/// that were pushed, and applying a pulled row under the LWW rule (§8.3:
/// "replace the local row UNLESS its `syncDirty` is true").
///
/// Deliberately a thin, mechanical layer -- the actual push/pull
/// orchestration (FK ordering, network calls, cursor bookkeeping, failure
/// swallowing) lives in `SupabaseSyncEngine` itself, mirroring how
/// `ChoreService` orchestrates `ChoreRepository` rather than folding that
/// logic into the repository.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// Data access backing `SupabaseSyncEngine`'s push (dirty-select,
/// guarded-clear) and pull (LWW-apply) steps, one method pair per synced
/// table.
class SyncRepository {
  /// Creates a repository backed by [db].
  SyncRepository(this.db);

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  // ---------------------------------------------------------------------
  // Dirty select (push, step 1) -- ordered by `id` purely for deterministic
  // test output; push order across ROWS of the same table has no FK
  // implications (only the order the 7 TABLES are pushed in does).

  /// Every `households` row with `syncDirty == true`.
  Future<List<Household>> dirtyHouseholds() => (db.select(
    db.households,
  )..where((tbl) => tbl.syncDirty.equals(true))).get();

  /// Every `members` row with `syncDirty == true`.
  Future<List<Member>> dirtyMembers() => (db.select(
    db.members,
  )..where((tbl) => tbl.syncDirty.equals(true))).get();

  /// Every `categories` row with `syncDirty == true`.
  Future<List<Category>> dirtyCategories() => (db.select(
    db.categories,
  )..where((tbl) => tbl.syncDirty.equals(true))).get();

  /// Every `chores` row with `syncDirty == true`.
  Future<List<Chore>> dirtyChores() =>
      (db.select(db.chores)..where((tbl) => tbl.syncDirty.equals(true))).get();

  /// Every `chore_assignees` row with `syncDirty == true`.
  Future<List<ChoreAssignee>> dirtyChoreAssignees() => (db.select(
    db.choreAssignees,
  )..where((tbl) => tbl.syncDirty.equals(true))).get();

  /// Every `chore_occurrences` row with `syncDirty == true`.
  Future<List<ChoreOccurrence>> dirtyChoreOccurrences() => (db.select(
    db.choreOccurrences,
  )..where((tbl) => tbl.syncDirty.equals(true))).get();

  /// Every `shopping_items` row with `syncDirty == true`.
  Future<List<ShoppingItem>> dirtyShoppingItems() => (db.select(
    db.shoppingItems,
  )..where((tbl) => tbl.syncDirty.equals(true))).get();

  // ---------------------------------------------------------------------
  // Guarded clear (push, step 2) -- spec §8.3: "clear with `WHERE id IN
  // (...) AND updated_at == <the value read>`" so a row dirtied again
  // DURING the push's network round trip (a genuine concurrent write, not
  // a hypothetical) keeps its flag: the guard only matches the exact
  // snapshot that was actually pushed, so a fresh write (which bumps
  // `updatedAt` again before the clear runs) simply doesn't match and stays
  // dirty for the next push cycle.
  //
  // `chore_assignees` has no `updatedAt` column locally (see
  // `ChoreAssignees` in `lib/data/db/tables.dart`), so its guard uses
  // `position` instead -- the only mutable, comparable field a
  // delete-then-reinsert (`ChoreRepository._insertAssignees`) would
  // realistically change. In the (harmless) edge case where a reinsert
  // happens to carry the exact same position, clearing the flag anyway
  // loses nothing: the row's pushed content and its current content are
  // identical, so the server already reflects what's now locally current.

  /// Clears `syncDirty` on the `households` row [id], but only if it's
  /// still exactly the [updatedAt] snapshot that was pushed.
  Future<void> clearHouseholdDirty(String id, String updatedAt) =>
      (db.update(db.households)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.updatedAt.equals(updatedAt) &
                tbl.syncDirty.equals(true),
          ))
          .write(const HouseholdsCompanion(syncDirty: Value(false)));

  /// Clears `syncDirty` on the `members` row [id], but only if it's still
  /// exactly the [updatedAt] snapshot that was pushed.
  Future<void> clearMemberDirty(String id, String updatedAt) =>
      (db.update(db.members)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.updatedAt.equals(updatedAt) &
                tbl.syncDirty.equals(true),
          ))
          .write(const MembersCompanion(syncDirty: Value(false)));

  /// Clears `syncDirty` on the `categories` row [id], but only if it's
  /// still exactly the [updatedAt] snapshot that was pushed.
  Future<void> clearCategoryDirty(String id, String updatedAt) =>
      (db.update(db.categories)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.updatedAt.equals(updatedAt) &
                tbl.syncDirty.equals(true),
          ))
          .write(const CategoriesCompanion(syncDirty: Value(false)));

  /// Clears `syncDirty` on the `chores` row [id], but only if it's still
  /// exactly the [updatedAt] snapshot that was pushed.
  Future<void> clearChoreDirty(String id, String updatedAt) =>
      (db.update(db.chores)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.updatedAt.equals(updatedAt) &
                tbl.syncDirty.equals(true),
          ))
          .write(const ChoresCompanion(syncDirty: Value(false)));

  /// Clears `syncDirty` on the `chore_assignees` row keyed by [choreId] +
  /// [memberId], but only if it's still exactly the [position] snapshot
  /// that was pushed (see this section's doc comment for why `position`
  /// substitutes for `updatedAt` here).
  Future<void> clearChoreAssigneeDirty(
    String choreId,
    String memberId,
    int position,
  ) =>
      (db.update(db.choreAssignees)..where(
            (tbl) =>
                tbl.choreId.equals(choreId) &
                tbl.memberId.equals(memberId) &
                tbl.position.equals(position) &
                tbl.syncDirty.equals(true),
          ))
          .write(const ChoreAssigneesCompanion(syncDirty: Value(false)));

  /// Clears `syncDirty` on the `chore_occurrences` row [id], but only if
  /// it's still exactly the [updatedAt] snapshot that was pushed.
  Future<void> clearChoreOccurrenceDirty(String id, String updatedAt) =>
      (db.update(db.choreOccurrences)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.updatedAt.equals(updatedAt) &
                tbl.syncDirty.equals(true),
          ))
          .write(const ChoreOccurrencesCompanion(syncDirty: Value(false)));

  /// Clears `syncDirty` on the `shopping_items` row [id], but only if it's
  /// still exactly the [updatedAt] snapshot that was pushed.
  Future<void> clearShoppingItemDirty(String id, String updatedAt) =>
      (db.update(db.shoppingItems)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.updatedAt.equals(updatedAt) &
                tbl.syncDirty.equals(true),
          ))
          .write(const ShoppingItemsCompanion(syncDirty: Value(false)));

  // ---------------------------------------------------------------------
  // LWW apply (pull) -- spec §8.3: replace the local row UNLESS it's
  // currently dirty (dirty-local-wins; the next push settles it). [pulled]
  // always carries `syncDirty: false` (see
  // `lib/data/sync/row_mappers.dart`'s `*FromRow` functions), so a replace
  // always leaves the row clean.

  /// Applies a pulled `households` row, unless the local row is dirty.
  Future<void> applyPulledHousehold(Household pulled) => _applyPulled(
    existing: (db.select(
      db.households,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.households).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `members` row, unless the local row is dirty.
  Future<void> applyPulledMember(Member pulled) => _applyPulled(
    existing: (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.members).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `categories` row, unless the local row is dirty.
  Future<void> applyPulledCategory(Category pulled) => _applyPulled(
    existing: (db.select(
      db.categories,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.categories).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `chores` row, unless the local row is dirty.
  Future<void> applyPulledChore(Chore pulled) => _applyPulled(
    existing: (db.select(
      db.chores,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.chores).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `chore_assignees` row (keyed by `choreId` +
  /// `memberId`), unless the local row is dirty.
  Future<void> applyPulledChoreAssignee(ChoreAssignee pulled) => _applyPulled(
    existing:
        (db.select(db.choreAssignees)..where(
              (tbl) =>
                  tbl.choreId.equals(pulled.choreId) &
                  tbl.memberId.equals(pulled.memberId),
            ))
            .getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.choreAssignees).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `chore_occurrences` row, unless the local row is
  /// dirty.
  Future<void> applyPulledChoreOccurrence(ChoreOccurrence pulled) =>
      _applyPulled(
        existing: (db.select(
          db.choreOccurrences,
        )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
        isDirty: (row) => row.syncDirty,
        write: () =>
            db.into(db.choreOccurrences).insertOnConflictUpdate(pulled),
      );

  /// Applies a pulled `shopping_items` row, unless the local row is dirty.
  Future<void> applyPulledShoppingItem(ShoppingItem pulled) => _applyPulled(
    existing: (db.select(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.shoppingItems).insertOnConflictUpdate(pulled),
  );

  /// Shared "replace unless locally dirty" shape for every `applyPulled*`
  /// method above: reads the current local row (if any) via [existing];
  /// if it exists and [isDirty] says it's dirty, does nothing (local dirty
  /// wins); otherwise runs [write] (an insert-or-replace keyed on the
  /// table's primary key).
  Future<void> _applyPulled<D>({
    required Future<D?> existing,
    required bool Function(D) isDirty,
    required Future<void> Function() write,
  }) async {
    final row = await existing;
    if (row != null && isDirty(row)) {
      return;
    }
    await write();
  }
}
