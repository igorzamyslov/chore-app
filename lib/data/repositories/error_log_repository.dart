/// Manages `client_errors` -- the device-local error ring buffer (spec
/// `docs/specs/client-error-reporting.md` §3).
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Repository for the `client_errors` table.
///
/// Device-scoped: no household scoping, no `syncDirty`, never read by the
/// sync engine. Uploading is `ErrorReporter`'s job; this class only records,
/// serves the pending rows, and marks them uploaded.
class ErrorLogRepository {
  /// Creates a repository backed by [db].
  ///
  /// [nowUtc] and [newId] are injectable so tests get a fixed clock and
  /// deterministic ids.
  ErrorLogRepository(
    this.db, {
    this.nowUtc = _defaultNowUtc,
    this.newId = _defaultNewId,
  });

  /// How many rows the table is capped at (spec §3.2).
  static const int capacity = 200;

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Returns the current UTC time.
  final DateTime Function() nowUtc;

  /// Generates a new row id (UUIDv4); also the server row's primary key.
  final String Function() newId;

  /// Records one occurrence of [error] from [source], in one transaction
  /// (spec §3.2).
  ///
  /// If a not-yet-uploaded row already has the same (`source`, `errorType`,
  /// `message`), that row's `count` is bumped, `lastSeenAt` moved forward and
  /// `stack`/`context`/`appVersion` refreshed to the latest values; an
  /// UPLOADED row is never merged into, so a repeat of it starts a fresh row
  /// (which is what keeps "uploaded rows are never re-sent" true). Otherwise
  /// a new row is inserted. Afterwards everything but the newest [capacity]
  /// rows by `lastSeenAt` (ties by `id`) is deleted -- uploaded rows stay as
  /// local history but count toward the cap.
  Future<void> record({
    required String source,
    required ScrubbedError error,
    required String appVersion,
    required String platform,
    String? householdId,
  }) {
    return db.transaction(() async {
      final now = nowUtc().toIso8601String();
      final existing =
          await (db.select(db.clientErrors)
                ..where(
                  (tbl) =>
                      tbl.uploadedAt.isNull() &
                      tbl.source.equals(source) &
                      tbl.errorType.equals(error.errorType) &
                      tbl.message.equals(error.message),
                )
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) {
        await (db.update(
          db.clientErrors,
        )..where((tbl) => tbl.id.equals(existing.id))).write(
          ClientErrorsCompanion(
            count: Value(existing.count + 1),
            lastSeenAt: Value(now),
            stack: Value(error.stack),
            context: Value(error.contextJson),
            appVersion: Value(appVersion),
          ),
        );
      } else {
        await db
            .into(db.clientErrors)
            .insert(
              ClientErrorsCompanion.insert(
                id: newId(),
                source: source,
                errorType: error.errorType,
                message: error.message,
                stack: Value(error.stack),
                context: Value(error.contextJson),
                firstSeenAt: now,
                lastSeenAt: now,
                appVersion: appVersion,
                platform: platform,
                householdId: Value(householdId),
              ),
            );
      }
      final keep =
          await (db.selectOnly(db.clientErrors)
                ..addColumns([db.clientErrors.id])
                ..orderBy([
                  OrderingTerm.desc(db.clientErrors.lastSeenAt),
                  OrderingTerm.asc(db.clientErrors.id),
                ])
                ..limit(capacity))
              .map((row) => row.read(db.clientErrors.id)!)
              .get();
      await (db.delete(
        db.clientErrors,
      )..where((tbl) => tbl.id.isNotIn(keep))).go();
    });
  }

  /// The rows still waiting to be uploaded, oldest `firstSeenAt` first, at
  /// most [limit].
  Future<List<ClientError>> pending({int limit = 50}) {
    return (db.select(db.clientErrors)
          ..where((tbl) => tbl.uploadedAt.isNull())
          ..orderBy([
            (tbl) => OrderingTerm.asc(tbl.firstSeenAt),
            (tbl) => OrderingTerm.asc(tbl.id),
          ])
          ..limit(limit))
        .get();
  }

  /// Marks the rows named by [ids] as uploaded at [at].
  Future<void> markUploaded(List<String> ids, DateTime at) async {
    if (ids.isEmpty) {
      return;
    }
    await (db.update(
      db.clientErrors,
    )..where((tbl) => tbl.id.isIn(ids))).write(
      ClientErrorsCompanion(uploadedAt: Value(at.toUtc().toIso8601String())),
    );
  }

  /// Deletes every row.
  Future<void> deleteAll() => db.delete(db.clientErrors).go();
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();

String _defaultNewId() => const Uuid().v4();
