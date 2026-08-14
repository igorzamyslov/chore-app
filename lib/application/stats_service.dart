/// Assembles the chore-history overview (spec `docs/specs/stats.md` §2.2,
/// §3.1, §3.3) from [StatsRepository]'s raw aggregates: the share window and
/// its household-start clamp, the roster-order member share, and the
/// active/deleted chore split.
///
/// Application layer, like `ChoreService`: it may import the domain, the
/// data layer and `package:clock` -- never Flutter.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

/// The length of the fairness window, in days, inclusive of today (spec
/// §2.2). Bounded on purpose: an all-time total would be a standing score.
const int statsWindowDays = 30;

/// One entry of the household share: a member (or the unattributed bucket)
/// and how many chores they completed in the window.
class MemberShare {
  /// Creates a share entry.
  const MemberShare({required this.member, required this.doneCount});

  /// The member, or `null` for the unattributed "Someone else" bucket.
  final Member? member;

  /// Completions credited to [member] in the window. May be 0 for a current
  /// roster member -- hiding a zero would make the card dishonest.
  final int doneCount;
}

/// Everything the chore-history overview screen renders.
class StatsOverview {
  /// Creates an overview.
  const StatsOverview({
    required this.windowStart,
    required this.windowEnd,
    required this.windowClampedToHouseholdStart,
    required this.shares,
    required this.totalDone,
    required this.activeChores,
    required this.deletedChores,
  });

  /// First day of the share window, inclusive.
  final PlainDate windowStart;

  /// Last day of the share window, inclusive (always today).
  final PlainDate windowEnd;

  /// Whether [windowStart] was moved forward because the household is
  /// younger than [statsWindowDays] -- the UI says so instead of implying a
  /// full month of data (spec §3.1).
  final bool windowClampedToHouseholdStart;

  /// Share entries in household roster order (member creation order), with
  /// any departed contributor appended and the unattributed bucket last
  /// (spec §3.1). NEVER sorted by count.
  final List<MemberShare> shares;

  /// Total completions in the window, across every entry in [shares].
  final int totalDone;

  /// Chores with completion history that are not deleted, alphabetical.
  final List<ChoreDoneRollup> activeChores;

  /// Soft-deleted chores with completion history, alphabetical. These are
  /// the reason this screen exists (triage D2).
  final List<ChoreDoneRollup> deletedChores;
}

/// Builds a [StatsOverview] for a household.
class StatsService {
  /// Creates a service reading through [stats] and [database].
  StatsService({
    required this.database,
    required this.stats,
    this.clock = const Clock(),
  });

  /// Used for the household row (its `created_at` drives the window clamp)
  /// and the member roster.
  final AppDatabase database;

  /// The aggregate queries.
  final StatsRepository stats;

  /// The app's injected clock; "today" is derived from it exactly once per
  /// [overview] call.
  final Clock clock;

  /// Reads everything the overview screen needs for [householdId].
  Future<StatsOverview> overview(String householdId) async {
    final today = PlainDate.fromDateTime(clock.now());
    final naturalStart = today.addDays(-(statsWindowDays - 1));

    final household = await (database.select(
      database.households,
    )..where((tbl) => tbl.id.equals(householdId))).getSingle();
    final rawHouseholdStart = PlainDate.fromDateTime(
      DateTime.parse(household.createdAt).toLocal(),
    );
    // Floor the household's own start at today so the window can never
    // invert. A `created_at` in the future relative to the clock is not
    // hypothetical -- a restored backup, a device whose clock was wrong and
    // then corrected, or a synced row written by a device running ahead all
    // produce one. Without this, `windowStart` could exceed `windowEnd`,
    // which matches no rows at all and labels the card "Since you started"
    // with a date that has not happened yet.
    final householdStart = rawHouseholdStart.isAfter(today)
        ? today
        : rawHouseholdStart;
    final clamped = householdStart.isAfter(naturalStart);
    final windowStart = clamped ? householdStart : naturalStart;

    final counts = await stats.doneCountsByMember(
      householdId,
      windowStart: windowStart,
      windowEnd: today,
    );
    final countById = <String?, int>{
      for (final count in counts) count.memberId: count.doneCount,
    };

    // Roster order = member creation order, and deliberately unfiltered on
    // `deleted_at`: a member who has since left still shows the work they
    // did (spec §2.1). Current members appear even with a count of 0;
    // departed ones only when they contributed.
    //
    // This ordering is a product rule, not a default (spec §0 rule 2): a
    // fairness view describes work, a leaderboard ranks people, and sorting
    // these entries by `doneCount` is precisely the line between the two.
    // Do not "improve" it into a sort.
    final roster =
        await (database.select(database.members)
              ..where((tbl) => tbl.householdId.equals(householdId))
              ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]))
            .get();

    final shares = <MemberShare>[
      for (final member in roster)
        if (member.deletedAt == null || (countById[member.id] ?? 0) > 0)
          MemberShare(member: member, doneCount: countById[member.id] ?? 0),
    ];
    final unattributed = countById[null] ?? 0;
    if (unattributed > 0) {
      shares.add(MemberShare(member: null, doneCount: unattributed));
    }

    final rollups = await stats.choreRollups(householdId);

    return StatsOverview(
      windowStart: windowStart,
      windowEnd: today,
      windowClampedToHouseholdStart: clamped,
      shares: shares,
      totalDone: counts.fold(0, (sum, count) => sum + count.doneCount),
      activeChores: [
        for (final rollup in rollups)
          if (rollup.chore.deletedAt == null) rollup,
      ],
      deletedChores: [
        for (final rollup in rollups)
          if (rollup.chore.deletedAt != null) rollup,
      ],
    );
  }
}
