/// Read-only aggregate queries backing the chore-history screens (spec
/// `docs/specs/stats.md`).
///
/// Deliberately separate from `ChoreRepository`: nothing here writes, and
/// every method aggregates in SQL rather than materializing history rows
/// (spec §2.3 -- occurrence history grows unbounded by design).
///
/// The one rule that governs all of it (spec §2.1): an occurrence counts
/// **iff** `status == done`. `skipped` and `missed` are excluded everywhere,
/// deliberately -- see the spec's §0 for why that is a product rule and not
/// an implementation detail.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart';

/// How many chores one member completed inside a window.
class MemberDoneCount {
  /// Creates a per-member done count.
  const MemberDoneCount({required this.memberId, required this.doneCount});

  /// The completing member's id, or `null` for the unattributed bucket (a
  /// `done` row whose `completed_by` is NULL -- possible via sync or an
  /// imported archive; spec §2.1).
  final String? memberId;

  /// The number of `done` occurrences credited to [memberId] in the window.
  final int doneCount;
}

/// One chore's all-time completion rollup.
class ChoreDoneRollup {
  /// Creates a rollup for [chore].
  const ChoreDoneRollup({
    required this.chore,
    required this.doneAllTime,
    required this.lastDoneOn,
    this.category,
  });

  /// The chore itself. May be soft-deleted and/or paused -- both are
  /// deliberately included (spec §2.1).
  final Chore chore;

  /// The chore's category, or `null` if uncategorized.
  final Category? category;

  /// How many times this chore has ever been completed. Always >= 1: chores
  /// with no completions are not returned at all.
  final int doneAllTime;

  /// The most recent date this chore was completed on.
  final PlainDate lastDoneOn;
}

/// One completion of a chore, with the member who did it resolved.
class ChoreCompletion {
  /// Creates a completion record.
  const ChoreCompletion({required this.occurrence, this.completedByMember});

  /// The `done` occurrence row.
  final ChoreOccurrence occurrence;

  /// The completing member, or `null` when unattributed. Resolved through a
  /// DISPLAY join that does NOT filter `deleted_at`, so a since-removed
  /// member is still named (spec §2.1).
  final Member? completedByMember;
}

/// Read-only reporting queries over `chore_occurrences` (spec
/// `docs/specs/stats.md`).
class StatsRepository {
  /// Creates a repository backed by [db].
  StatsRepository(this.db);

  /// The database this repository reads from. It never writes.
  final AppDatabase db;

  /// Counts `done` occurrences in [householdId] closed between
  /// [windowStart] and [windowEnd] (both inclusive), grouped by the
  /// completing member.
  ///
  /// `closed_on` is a `yyyy-mm-dd` TEXT column, so the window is a plain
  /// lexicographic string range -- no date parsing in SQL (spec §2.2).
  /// Deleted and paused chores are included on purpose (spec §2.1).
  Future<List<MemberDoneCount>> doneCountsByMember(
    String householdId, {
    required PlainDate windowStart,
    required PlainDate windowEnd,
  }) async {
    final doneCount = db.choreOccurrences.id.count();
    final query = db.selectOnly(db.choreOccurrences)
      ..addColumns([db.choreOccurrences.completedBy, doneCount])
      ..join([
        innerJoin(
          db.chores,
          db.chores.id.equalsExp(db.choreOccurrences.choreId),
          useColumns: false,
        ),
      ])
      ..where(
        db.chores.householdId.equals(householdId) &
            db.choreOccurrences.status.equalsValue(OccurrenceStatus.done) &
            db.choreOccurrences.closedOn.isBiggerOrEqualValue(
              windowStart.toIso8601(),
            ) &
            db.choreOccurrences.closedOn.isSmallerOrEqualValue(
              windowEnd.toIso8601(),
            ),
      )
      ..groupBy([db.choreOccurrences.completedBy]);

    final rows = await query.get();
    return [
      for (final row in rows)
        MemberDoneCount(
          memberId: row.read(db.choreOccurrences.completedBy),
          doneCount: row.read(doneCount) ?? 0,
        ),
    ];
  }

  /// Every chore of [householdId] with at least one `done` occurrence ever,
  /// with its all-time completion count and last completion date, ordered
  /// alphabetically by title (spec §3.2 -- never by count).
  ///
  /// Two queries rather than one: the aggregate returns at most one row per
  /// chore (dozens), and the follow-up fetch of those chores + categories is
  /// an ordinary join. This avoids relying on SQLite's bare-column-with-max
  /// behaviour, which is correct but non-obvious.
  Future<List<ChoreDoneRollup>> choreRollups(String householdId) async {
    final doneCount = db.choreOccurrences.id.count();
    final lastDone = db.choreOccurrences.closedOn.max();
    final aggregate = db.selectOnly(db.choreOccurrences)
      ..addColumns([db.choreOccurrences.choreId, doneCount, lastDone])
      ..join([
        innerJoin(
          db.chores,
          db.chores.id.equalsExp(db.choreOccurrences.choreId),
          useColumns: false,
        ),
      ])
      ..where(
        db.chores.householdId.equals(householdId) &
            db.choreOccurrences.status.equalsValue(OccurrenceStatus.done),
      )
      ..groupBy([db.choreOccurrences.choreId]);

    final aggregateRows = await aggregate.get();
    if (aggregateRows.isEmpty) {
      return const [];
    }

    final counts = <String, int>{};
    final lastDates = <String, PlainDate>{};
    for (final row in aggregateRows) {
      final choreId = row.read(db.choreOccurrences.choreId)!;
      counts[choreId] = row.read(doneCount) ?? 0;
      // `closedOn` is a `GeneratedColumnWithTypeConverter<PlainDate?,
      // String>`, so an aggregate over it is an `Expression<String>` and
      // reads back as the raw `yyyy-mm-dd` text, not a PlainDate.
      final iso = row.read(lastDone);
      if (iso != null) {
        lastDates[choreId] = PlainDate.parse(iso);
      }
    }

    final detail =
        db.select(db.chores).join([
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.chores.categoryId),
            ),
          ])
          ..where(db.chores.id.isIn(counts.keys))
          ..orderBy([OrderingTerm(expression: db.chores.title)]);

    final detailRows = await detail.get();
    return [
      for (final row in detailRows)
        if (lastDates[row.readTable(db.chores).id] case final PlainDate last)
          ChoreDoneRollup(
            chore: row.readTable(db.chores),
            category: row.readTableOrNull(db.categories),
            doneAllTime: counts[row.readTable(db.chores).id] ?? 0,
            lastDoneOn: last,
          ),
    ];
  }

  /// The all-time number of `done` occurrences of [choreId].
  Future<int> doneCountForChore(String choreId) async {
    final doneCount = db.choreOccurrences.id.count();
    final query = db.selectOnly(db.choreOccurrences)
      ..addColumns([doneCount])
      ..where(
        db.choreOccurrences.choreId.equals(choreId) &
            db.choreOccurrences.status.equalsValue(OccurrenceStatus.done),
      );
    final row = await query.getSingle();
    return row.read(doneCount) ?? 0;
  }

  /// The [limit] most recent `done` occurrences of [choreId], newest first
  /// (`closed_on` desc, then `updated_at` desc -- the same tiebreak
  /// `ChoreRepository.latestClosedOccurrence` uses).
  ///
  /// The `members` join is a DISPLAY join and deliberately does NOT filter
  /// `deleted_at`: a removed member's past work stays attributed (spec
  /// §2.1).
  ///
  /// [limit] is required rather than defaulted to 50: the cap is a product
  /// decision that belongs to one place (`choreHistoryLimit`, spec §5), and
  /// a default here would restate it -- two constants that must agree, and
  /// which `avoid_redundant_argument_values` would then flag at the one
  /// call site that passes it deliberately.
  Future<List<ChoreCompletion>> recentCompletions(
    String choreId, {
    required int limit,
  }) async {
    final query =
        db.select(db.choreOccurrences).join([
            leftOuterJoin(
              db.members,
              db.members.id.equalsExp(db.choreOccurrences.completedBy),
            ),
          ])
          ..where(
            db.choreOccurrences.choreId.equals(choreId) &
                db.choreOccurrences.status.equalsValue(OccurrenceStatus.done),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.choreOccurrences.closedOn,
              mode: OrderingMode.desc,
            ),
            OrderingTerm(
              expression: db.choreOccurrences.updatedAt,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit);

    final rows = await query.get();
    return [
      for (final row in rows)
        ChoreCompletion(
          occurrence: row.readTable(db.choreOccurrences),
          completedByMember: row.readTableOrNull(db.members),
        ),
    ];
  }
}
