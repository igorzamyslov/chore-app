/// Manages `ui_state` -- the device-local, unsynced UI memory, currently just
/// the last-visible top-level tab and the Chores list filters (spec
/// `docs/specs/last-tab-restore.md`).
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// Repository for the single-row `ui_state` table.
///
/// Device-scoped: no household scoping and no `syncDirty` bookkeeping, and
/// nothing here ever leaves the device. Exposes no stream on purpose -- the
/// value is written blind on every tab change and read once at startup, so
/// nothing may rebuild off it.
class UiStateRepository {
  /// Creates a repository backed by [db].
  UiStateRepository(this.db);

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  static const _rowId = 'device';

  /// The whole stored row, or `null` when nothing has been written yet
  /// (fresh install, or after a data reset).
  ///
  /// Values are returned verbatim: mapping an unrecognized tab name or a
  /// stale filter id to a default is the caller's job, since only it knows
  /// the current tabs, members and categories.
  Future<UiStateRow?> readUiState() {
    return (db.select(
      db.uiState,
    )..where((tbl) => tbl.id.equals(_rowId))).getSingleOrNull();
  }

  /// Records [tab] as the last-visible tab, replacing any previous value.
  Future<void> setLastTab(String tab) async {
    await db
        .into(db.uiState)
        .insertOnConflictUpdate(
          UiStateCompanion.insert(id: _rowId, lastTab: Value(tab)),
        );
  }

  /// Records the Chores list's member and category filters (`null` = "All"),
  /// replacing both previous values. Leaves `last_tab` untouched: the upsert
  /// companion only carries the columns this method owns.
  Future<void> setChoresFilters({
    required String? memberId,
    required String? categoryId,
  }) async {
    await db
        .into(db.uiState)
        .insertOnConflictUpdate(
          UiStateCompanion(
            id: const Value(_rowId),
            choresMemberFilter: Value(memberId),
            choresCategoryFilter: Value(categoryId),
          ),
        );
  }
}
