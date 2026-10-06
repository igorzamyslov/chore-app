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

  /// Watches whether ANY synced-table row is currently `syncDirty` --
  /// re-emits whenever a write touches any of the seven synced tables (the
  /// `readsFrom` wiring below), regardless of which table changed. Backs
  /// `dirtySinceProvider` (`lib/app/providers.dart`), the D-5 indicator's
  /// "this device has unsent changes" signal (spec
  /// `docs/specs/sync-freshness.md` §2.5).
  ///
  /// A single `EXISTS` over a `UNION ALL` rather than seven separate
  /// watches: SQLite short-circuits `EXISTS` on the first matching row, and
  /// one stream means one drift subscription for a boolean the caller only
  /// ever needs collapsed anyway.
  Stream<bool> watchAnyDirty() {
    return db
        .customSelect(
          'SELECT EXISTS( '
          'SELECT 1 FROM households WHERE sync_dirty = 1 '
          'UNION ALL SELECT 1 FROM members WHERE sync_dirty = 1 '
          'UNION ALL SELECT 1 FROM categories WHERE sync_dirty = 1 '
          'UNION ALL SELECT 1 FROM chores WHERE sync_dirty = 1 '
          'UNION ALL SELECT 1 FROM chore_assignees WHERE sync_dirty = 1 '
          'UNION ALL SELECT 1 FROM chore_occurrences WHERE sync_dirty = 1 '
          'UNION ALL SELECT 1 FROM shopping_items WHERE sync_dirty = 1 '
          ') AS any_dirty',
          readsFrom: {
            db.households,
            db.members,
            db.categories,
            db.chores,
            db.choreAssignees,
            db.choreOccurrences,
            db.shoppingItems,
          },
        )
        .watchSingle()
        .map((row) => row.read<int>('any_dirty') == 1);
  }

  /// Watches HOW MANY changes this device still owes the server: every
  /// `syncDirty` row across the seven synced tables plus every pending
  /// hard-delete tombstone (spec `docs/specs/sync-backend.md` §8.6 -- a
  /// deleted row has no dirty row of its own, the outbox entry IS the
  /// unsent change). Backs `syncPendingCountProvider`
  /// (`lib/app/providers.dart`) and the "N changes waiting to send" line in
  /// Settings -> Account (spec `docs/specs/sync-freshness.md` §2.4
  /// amendment 2026-10-06). Re-emits on a write to any of those eight
  /// tables.
  ///
  /// Kept separate from [watchAnyDirty]: that one is an `EXISTS` the health
  /// check only needs collapsed to a boolean, and SQLite short-circuits it;
  /// this one has to count.
  Stream<int> watchDirtyRowCount() {
    return db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM households WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM members WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM categories WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM chores WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM chore_assignees WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM chore_occurrences WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM shopping_items WHERE sync_dirty = 1) + '
          '(SELECT COUNT(*) FROM sync_tombstones) AS pending',
          readsFrom: {
            db.households,
            db.members,
            db.categories,
            db.chores,
            db.choreAssignees,
            db.choreOccurrences,
            db.shoppingItems,
            db.syncTombstones,
          },
        )
        .watchSingle()
        .map((row) => row.read<int>('pending'));
  }

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
    pulled: pulled,
    existing: (db.select(
      db.households,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.households).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `members` row, unless the local row is dirty.
  Future<void> applyPulledMember(Member pulled) => _applyPulled(
    pulled: pulled,
    existing: (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.members).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `categories` row, unless the local row is dirty.
  Future<void> applyPulledCategory(Category pulled) => _applyPulled(
    pulled: pulled,
    existing: (db.select(
      db.categories,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.categories).insertOnConflictUpdate(pulled),
  );

  /// Applies a pulled `chores` row, unless the local row is dirty.
  Future<void> applyPulledChore(Chore pulled) => _applyPulled(
    pulled: pulled,
    existing: (db.select(
      db.chores,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.chores).insertOnConflictUpdate(pulled),
  );

  /// Applies everything a pull fetched for ONE chore's `chore_assignees`
  /// (spec §8.3 amendment 2026-10-06, technical review #8): the assignee
  /// list is a single LWW value, not a set of independently merged rows.
  ///
  /// - If the local chore row is dirty, or any of its local assignee rows
  ///   is (an edit whose push has not completed), nothing is applied: local
  ///   dirty wins for the WHOLE list, and the next push settles it. Merging
  ///   row-by-row here is what produced a union of both devices' edits with
  ///   duplicate `position`s and a rotation order that differed per device.
  /// - Otherwise, if [live] is non-empty, the local set is replaced by it
  ///   (delete then insert, positions exactly as pulled). Every local edit
  ///   rewrites the full list (`ChoreRepository.updateChore`), so a pull
  ///   that sees any live row of a chore sees that chore's complete list.
  /// - Otherwise only [tombstonedMemberIds] are deleted: a pull can land
  ///   between the other device's live-row push and its tombstone push,
  ///   and treating "tombstones only" as "the new set is empty" would wipe
  ///   the chore's assignees.
  Future<void> applyPulledAssigneeSet(
    String choreId, {
    required List<ChoreAssignee> live,
    required List<String> tombstonedMemberIds,
  }) async {
    final chore = await (db.select(
      db.chores,
    )..where((tbl) => tbl.id.equals(choreId))).getSingleOrNull();
    if (chore != null && chore.syncDirty) {
      return;
    }
    final current = await (db.select(
      db.choreAssignees,
    )..where((tbl) => tbl.choreId.equals(choreId))).get();
    if (current.any((row) => row.syncDirty)) {
      return;
    }
    if (live.isNotEmpty) {
      // Same no-op rule as [_applyPulled]: an unchanged list (a re-fetch
      // inside the cursor overlap) must not be rewritten, or the write
      // listener would turn every pull into another push/pull.
      if (_sameAssigneeSet(current, live)) {
        return;
      }
      await (db.delete(
        db.choreAssignees,
      )..where((tbl) => tbl.choreId.equals(choreId))).go();
      for (final row in live) {
        await db.into(db.choreAssignees).insert(row);
      }
      return;
    }
    if (tombstonedMemberIds.isNotEmpty) {
      await (db.delete(db.choreAssignees)..where(
            (tbl) =>
                tbl.choreId.equals(choreId) &
                tbl.memberId.isIn(tombstonedMemberIds),
          ))
          .go();
    }
  }

  /// Applies a pulled `chore_occurrences` row, unless the local row is
  /// dirty.
  Future<void> applyPulledChoreOccurrence(ChoreOccurrence pulled) =>
      _applyPulled(
        pulled: pulled,
        existing: (db.select(
          db.choreOccurrences,
        )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
        isDirty: (row) => row.syncDirty,
        write: () =>
            db.into(db.choreOccurrences).insertOnConflictUpdate(pulled),
      );

  /// Applies a pulled `shopping_items` row, unless the local row is dirty.
  Future<void> applyPulledShoppingItem(ShoppingItem pulled) => _applyPulled(
    pulled: pulled,
    existing: (db.select(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(pulled.id))).getSingleOrNull(),
    isDirty: (row) => row.syncDirty,
    write: () => db.into(db.shoppingItems).insertOnConflictUpdate(pulled),
  );

  // ---------------------------------------------------------------------
  // Hard-delete tombstones (spec `docs/specs/sync-backend.md` §8.6).

  /// Hard-deletes [victims] (occurrences) and records one tombstone per
  /// row, stamped [deletedAt], in one transaction. THE single code path for
  /// "delete an occurrence and tell the server": the three repository
  /// sites and the pull-side ghost repair all go through it.
  Future<void> deleteOccurrencesRecordingTombstones(
    List<ChoreOccurrence> victims,
    String deletedAt,
  ) => db.transaction(() async {
    for (final victim in victims) {
      await db
          .into(db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              entity: 'chore_occurrences',
              rowId: victim.id,
              deletedAt: deletedAt,
            ),
          );
      await (db.delete(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(victim.id))).go();
    }
  });

  /// Every pending tombstone, oldest first (ascending `id`).
  Future<List<SyncTombstone>> pendingTombstones() => (db.select(
    db.syncTombstones,
  )..orderBy([(tbl) => OrderingTerm(expression: tbl.id)])).get();

  /// Removes the tombstone [id] -- exactly that row, so one recorded while a
  /// push was in flight survives.
  Future<void> deleteTombstone(int id) =>
      (db.delete(db.syncTombstones)..where((tbl) => tbl.id.equals(id))).go();

  /// Whether a local `chore_occurrences` row with [id] exists.
  Future<bool> occurrenceExists(String id) async =>
      await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(id))).getSingleOrNull() !=
      null;

  /// Whether a local `chore_assignees` row keyed [choreId] + [memberId]
  /// exists.
  Future<bool> assigneeExists(String choreId, String memberId) async =>
      await (db.select(db.choreAssignees)..where(
            (tbl) =>
                tbl.choreId.equals(choreId) & tbl.memberId.equals(memberId),
          ))
          .getSingleOrNull() !=
      null;

  /// Applies a pulled tombstone for the `chore_occurrences` row [id]: a
  /// local hard delete, unless the local row is `syncDirty` (local dirty
  /// wins, §8.3; its push sends `deleted_at: null`) OR is no longer
  /// pending (spec §8.6 amendment 2026-10-06, technical review #1: a
  /// tombstone means "the pending row is gone", and must never erase a
  /// completion this device recorded and already pushed). No tombstone is
  /// recorded -- the server already knows.
  Future<void> applyPulledOccurrenceDeletion(String id) =>
      (db.delete(db.choreOccurrences)..where(
            (tbl) =>
                tbl.id.equals(id) &
                tbl.syncDirty.equals(false) &
                tbl.status.equalsValue(OccurrenceStatus.pending),
          ))
          .go();

  /// Ghost repair (spec §8.6.6, survivor key amended 2026-10-06 -- §8.7):
  /// for every chore of [householdId] with MORE THAN ONE pending
  /// occurrence, keeps the one with the greatest `dueDate` (tie: greater
  /// `id`) and hard-deletes the rest through
  /// [deleteOccurrencesRecordingTombstones]. The product invariant is "at
  /// most one pending occurrence per chore", so any extra one is a ghost an
  /// older client failed to delete on the server, or the other device's
  /// copy of a catch-up both devices ran the same morning.
  ///
  /// `updatedAt` is deliberately NOT part of the key (technical review
  /// 2026-10-06 #4): a locally written stamp comes from this device's
  /// clock, a pulled one from the server's, so two devices comparing the
  /// same two rows could each pick a different survivor and tombstone the
  /// other's -- leaving the chore with no pending row anywhere. `dueDate`
  /// and `id` are the only fields both devices see identically, so both
  /// converge on the same survivor. Callable from anywhere, not only the
  /// pull transaction: it touches pending rows only and opens its own
  /// transaction for each deletion (`ChoreService.catchUpOverdue` runs it).
  Future<void> repairGhostOccurrences(
    String householdId,
    String deletedAt,
  ) async {
    final pending =
        await (db.select(db.choreOccurrences).join([
              innerJoin(
                db.chores,
                db.chores.id.equalsExp(db.choreOccurrences.choreId),
              ),
            ])..where(
              db.chores.householdId.equals(householdId) &
                  db.choreOccurrences.status.equalsValue(
                    OccurrenceStatus.pending,
                  ),
            ))
            .map((row) => row.readTable(db.choreOccurrences))
            .get();
    final byChore = <String, List<ChoreOccurrence>>{};
    for (final occurrence in pending) {
      byChore.putIfAbsent(occurrence.choreId, () => []).add(occurrence);
    }
    for (final group in byChore.values) {
      if (group.length < 2) {
        continue;
      }
      group.sort((a, b) {
        final byDue = b.dueDate.toIso8601().compareTo(a.dueDate.toIso8601());
        return byDue != 0 ? byDue : b.id.compareTo(a.id);
      });
      await deleteOccurrencesRecordingTombstones(group.sublist(1), deletedAt);
    }
  }

  /// Whether [current] and [pulled] describe the same assignee list
  /// (same members at the same positions, every row clean), in any order.
  static bool _sameAssigneeSet(
    List<ChoreAssignee> current,
    List<ChoreAssignee> pulled,
  ) {
    if (current.length != pulled.length) {
      return false;
    }
    String key(ChoreAssignee row) =>
        '${row.memberId}:${row.position}:${row.syncDirty}';
    final currentKeys = current.map(key).toSet();
    return pulled.every((row) => currentKeys.contains(key(row)));
  }

  /// Shared "replace unless locally dirty" shape for every `applyPulled*`
  /// method above: reads the current local row (if any) via [existing];
  /// if it exists and [isDirty] says it's dirty, does nothing (local dirty
  /// wins); if it exists and already EQUALS [pulled] (drift data classes
  /// compare by value, `syncDirty` included), also does nothing; otherwise
  /// runs [write] (an insert-or-replace keyed on the table's primary key).
  ///
  /// The equality short-circuit is load-bearing since the cursor overlap
  /// (`syncCursorOverlap`, spec §8.3 amendment 2026-10-06): every pull
  /// re-fetches the rows stamped in the last 30 s of server time, and
  /// rewriting an unchanged row would fire drift's table-update stream,
  /// which the engine's write listener turns into a debounced push, whose
  /// follow-up pull re-fetches the same rows again -- a push/pull loop for
  /// as long as the rows stay inside the window. A no-op write is not a
  /// write, so the listener never hears about a re-apply.
  Future<void> _applyPulled<D>({
    required D pulled,
    required Future<D?> existing,
    required bool Function(D) isDirty,
    required Future<void> Function() write,
  }) async {
    final row = await existing;
    if (row != null && (isDirty(row) || row == pulled)) {
      return;
    }
    await write();
  }
}
