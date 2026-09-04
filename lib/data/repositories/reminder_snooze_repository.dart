/// Manages `reminder_snoozes` -- the device-local, unsynced deferrals of
/// individual chore reminders (spec `docs/specs/notifications-n2.md` §4.2).
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// Repository for the device-scoped reminder-snooze rows.
///
/// Unlike the synced repositories in this layer there is no `syncDirty`
/// bookkeeping and no household scoping: snoozing is a personal act about a
/// personal notification (spec `docs/specs/notifications-n2.md` §4.2), so
/// nothing here ever leaves the device. One partner pressing Snooze must
/// not silence the other's reminder.
class ReminderSnoozeRepository {
  /// Creates a repository backed by [db].
  ///
  /// [nowUtc] is injectable so tests can supply a controllable clock; it
  /// defaults to the real UTC clock.
  ReminderSnoozeRepository(this.db, {this.nowUtc = _defaultNowUtc});

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Records that [occurrenceId]'s reminder is deferred until
  /// [snoozedUntilUtc], replacing any existing row for that occurrence.
  ///
  /// Idempotent by construction ([InsertMode.insertOrReplace] on the
  /// occurrence-id primary key), which is what makes a double tap on the
  /// notification's Snooze action a no-op rather than a constraint error
  /// (spec §13.2). [snoozedUntilUtc] is stored as an ISO-8601 UTC string --
  /// converted with `toUtc()` first, so a local `DateTime` is stored as its
  /// instant rather than as its wall-clock digits -- and it carries INTENT
  /// only: the quiet-hours shift is applied at plan time (§2.3 step 4),
  /// never here, so exactly one code path decides when a reminder may fire.
  Future<void> upsertSnooze({
    required String occurrenceId,
    required DateTime snoozedUntilUtc,
  }) async {
    final now = _isoNow();
    await db
        .into(db.reminderSnoozes)
        .insert(
          ReminderSnoozesCompanion.insert(
            occurrenceId: occurrenceId,
            snoozedUntil: snoozedUntilUtc.toUtc().toIso8601String(),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Every stored snooze, as `occurrenceId -> snoozed-until instant` (UTC).
  ///
  /// Returned as a plain map because its one consumer is the pure planning
  /// pass (`buildNotificationPlans`, spec §9.1), which may not touch drift.
  ///
  /// Deliberately returns ALL rows rather than filtering by time: §2.3 step
  /// 5 is the single place a past moment is dropped, and a second copy of
  /// that rule here is exactly the drift §0.1's partition exists to
  /// prevent. [collectGarbage] is what keeps the set small.
  Future<Map<String, DateTime>> activeSnoozes() async {
    final rows = await db.select(db.reminderSnoozes).get();
    return {
      for (final row in rows)
        row.occurrenceId: DateTime.parse(row.snoozedUntil).toUtc(),
    };
  }

  /// Deletes every row whose occurrence is not in [pendingOccurrenceIds] or
  /// whose `snoozed_until` is at or before [nowUtc] (spec §4.2).
  ///
  /// Called on every plan pass. Cheap, and it means the table never grows.
  ///
  /// The `snoozed_until` comparison is lexicographic rather than date
  /// arithmetic, and that is correct rather than merely tolerable: every
  /// writer goes through [upsertSnooze], which stores a fixed-width
  /// ISO-8601 UTC string with milliseconds, so a lexicographic `<=` IS a
  /// chronological `<=` -- the same property `closedOn`'s range scan
  /// already relies on (see `ChoreOccurrences`' doc comment). Do not "fix"
  /// it into `DateTime` parsing per row.
  Future<void> collectGarbage({
    required Set<String> pendingOccurrenceIds,
    required DateTime nowUtc,
  }) async {
    final cutoff = nowUtc.toUtc().toIso8601String();
    await (db.delete(db.reminderSnoozes)..where(
          (tbl) =>
              tbl.occurrenceId.isNotIn(pendingOccurrenceIds) |
              tbl.snoozedUntil.isSmallerOrEqualValue(cutoff),
        ))
        .go();
  }

  String _isoNow() => nowUtc().toUtc().toIso8601String();
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();
