/// An in-memory [SyncTransport] fake (spec `docs/specs/sync-backend.md`
/// §8.4): stands in for a real Supabase project so `SupabaseSyncEngine`'s
/// push/pull/LWW/flag-clearing/cursor logic can be exercised against a real
/// in-memory `AppDatabase` with no live network involved.
///
/// `serverRows` models the server's tables as plain snake_case maps, keyed
/// exactly like the real schema (`households` by `id`; every other table by
/// `id`, or `chore_id`+`member_id` for `chore_assignees`). Every write here
/// mimics the server's `set_updated_at()` trigger (spec §1: "client-sent
/// values are overwritten") by stamping `now` onto `updated_at`, regardless
/// of what the engine sent.
library;

import 'dart:async';

import 'package:chore_app/application/sync_engine.dart';

class FakeSyncTransport implements SyncTransport {
  /// The fake server's current clock -- returned by [serverNow] and
  /// stamped onto every written row's `updated_at`. Tests advance this
  /// directly to simulate the passage of server time between pulls.
  DateTime now = DateTime.utc(2026);

  /// The fake server's tables, keyed by table name.
  final Map<String, List<Map<String, Object?>>> serverRows = {
    for (final table in syncedTablesInFkOrder) table: <Map<String, Object?>>[],
  };

  /// Every table name [upsertRows]/[insertMembersIgnoringConflicts]/
  /// [updateHousehold] was called for, in call order -- lets tests assert
  /// push happened in FK order (spec §8.3).
  final List<String> pushedTables = [];

  /// Runs (and is awaited) at the START of [upsertRows], before this fake
  /// touches [serverRows] -- lets a test simulate a local write arriving
  /// WHILE a push's "network round trip" is still in flight (spec §8.4:
  /// "mid-push re-dirty stays dirty").
  Future<void> Function()? beforeUpsert;

  /// How many times [serverNow] has been called -- i.e. how many pulls the
  /// engine has STARTED, since every `pullSince` reads the server clock
  /// first. Lets a test count pulls without inspecting the database (spec
  /// `docs/specs/sync-freshness.md` §2.2's foreground poll).
  int serverNowCalls = 0;

  /// What [hasMembership] returns. `false` models a revoked membership --
  /// the server-side removal this device has not noticed yet.
  bool membershipPresent = true;

  @override
  Future<bool> hasMembership(String householdId) async => membershipPresent;

  @override
  Future<DateTime> serverNow() async {
    serverNowCalls++;
    return now;
  }

  @override
  Future<List<Map<String, Object?>>> pullTable(
    String table, {
    required String householdId,
    required DateTime? since,
  }) async {
    final scopeColumn = table == 'households' ? 'id' : 'household_id';
    return [
      for (final row in serverRows[table]!)
        if (row[scopeColumn] == householdId &&
            (since == null ||
                DateTime.parse(row['updated_at']! as String).isAfter(since)))
          Map<String, Object?>.from(row),
    ];
  }

  @override
  Future<void> upsertRows(
    String table,
    List<Map<String, Object?>> rows, {
    String? onConflict,
  }) async {
    if (rows.isEmpty) {
      return;
    }
    final hook = beforeUpsert;
    if (hook != null) {
      await hook();
    }
    pushedTables.add(table);
    final keyColumns = onConflict?.split(',') ?? const ['id'];
    for (final row in rows) {
      _upsert(table, row, keyColumns: keyColumns);
    }
  }

  @override
  Future<void> insertMembersIgnoringConflicts(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return;
    }
    pushedTables.add('members');
    final list = serverRows['members']!;
    for (final row in rows) {
      final exists = list.any((existing) => existing['id'] == row['id']);
      if (!exists) {
        list.add({...row, 'updated_at': now.toIso8601String()});
      }
    }
  }

  @override
  Future<void> updateMemberGrantedColumns(
    String id,
    Map<String, Object?> columns,
  ) async {
    _upsert('members', {'id': id, ...columns}, keyColumns: const ['id']);
  }

  @override
  Future<void> updateHousehold(String id, Map<String, Object?> columns) async {
    pushedTables.add('households');
    _upsert('households', {'id': id, ...columns}, keyColumns: const ['id']);
  }

  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Emits a realtime change event (spec §8.3d: payload ignored, it only
  /// short-circuits the pull timer) to whoever is currently listening via
  /// [householdChanges].
  void emitChange() => _changesController.add(null);

  @override
  Stream<void> householdChanges(String householdId) =>
      _changesController.stream;

  void _upsert(
    String table,
    Map<String, Object?> row, {
    required List<String> keyColumns,
  }) {
    final list = serverRows[table]!;
    final index = list.indexWhere(
      (existing) => keyColumns.every((key) => existing[key] == row[key]),
    );
    final stamped = {...row, 'updated_at': now.toIso8601String()};
    if (index == -1) {
      list.add(stamped);
    } else {
      list[index] = {...list[index], ...stamped};
    }
  }
}
