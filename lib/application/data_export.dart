/// Pure builder for the B1 data-export JSON document (spec
/// `docs/specs/polish-round-1.md` B1).
///
/// Deliberately split from the actual sharing: [buildExportDocument] only
/// needs a database and a clock, so it's fully testable without ever
/// touching the OS share sheet -- `lib/features/settings/export_row.dart`
/// is the thin `share_plus` wrapper on top of it.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';

/// The export envelope's own format version (the `format` field). Bump this
/// only if the JSON *shape* of the export changes -- unrelated to
/// [AppDatabase.schemaVersion], which already travels in the document's
/// `schema_version` field.
const int dataExportFormat = 1;

/// Every exported table, in FK-parent-first order -- also the order they
/// appear under the document's `tables` key -- using their raw SQL names
/// (spec `docs/specs/polish-round-1.md` B1 lists this exact key set).
///
/// `reminder_snoozes` (schema v13) is deliberately NOT here, decided
/// 2026-08-30: a snooze is device-scoped, transient NOTIFICATION
/// bookkeeping -- "I pushed this notification to tomorrow" -- not household
/// data. This document exists so a user keeps the things they created, and
/// restoring a snooze would resurrect a deferral against an occurrence that
/// may no longer exist, or that another device completed in the meantime,
/// which is worse than losing it. Its absence costs the user nothing they
/// would notice. See "Closed product decisions" in
/// `docs/plans/2026-08-30-n2-foundation.md` before adding it.
const List<String> exportedTableNames = [
  'households',
  'members',
  'categories',
  'chores',
  'chore_assignees',
  'chore_occurrences',
  'shopping_items',
  'settings',
];

/// Builds the full backup document (spec `docs/specs/polish-round-1.md` B1):
/// `format`, `schema_version`, `exported_at` (an ISO-8601 UTC string), and
/// `tables` (one array per table name in [exportedTableNames]).
///
/// Every table is read with a plain `SELECT * FROM` its name -- no `WHERE`,
/// so soft-deleted rows are included -- and each row's raw column map is
/// used verbatim. This is deliberately NOT built from the typed
/// repositories/data classes: those decode converter-mapped columns (e.g.
/// `chores.recurrence` into a `Recurrence`, `chores.start_date` into a
/// `PlainDate`) into Dart objects that would then have to be re-encoded to
/// end up back in the database's own on-disk shape. Reading raw SQL rows
/// sidesteps that entirely: `recurrence` comes back exactly as the JSON
/// text already stored, dates as their `yyyy-mm-dd` text, enums as their
/// stored name, booleans as the `0`/`1` SQLite actually holds -- matching
/// the spec's "raw column names/values as stored" to the letter.
///
/// The document's `exported_at` is derived from [clock] (never
/// `DateTime.now()`) so it's deterministic under a fixed test/E2E clock.
Future<Map<String, Object?>> buildExportDocument({
  required AppDatabase database,
  required Clock clock,
}) async {
  final tables = <String, Object?>{};
  for (final table in exportedTableNames) {
    final rows = await database.customSelect('SELECT * FROM $table').get();
    tables[table] = [for (final row in rows) row.data];
  }
  return {
    'format': dataExportFormat,
    'schema_version': database.schemaVersion,
    'exported_at': clock.now().toUtc().toIso8601String(),
    'tables': tables,
  };
}

/// The export file's name (spec `docs/specs/polish-round-1.md` B1):
/// `famdo-export-<yyyy-mm-dd>.json`, dated from [clock] (never
/// `DateTime.now()`) so it's deterministic under a fixed test/E2E clock.
String exportFileName(Clock clock) {
  final today = PlainDate.fromDateTime(clock.now());
  return 'famdo-export-${today.toIso8601()}.json';
}
