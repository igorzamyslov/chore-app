// `DigestPlan` has only final fields and no mutating members, so it is
// effectively immutable; we deliberately don't import `package:meta` (lib
// code is dart:core only) to add the `@immutable` annotation the lint below
// wants (same convention as `plain_date.dart`).
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Pure scheduling logic for the daily digest notification (spec
/// `docs/specs/notifications.md`, architecture #1).
///
/// Same purity standard as `lib/domain/recurrence/` and `rotation.dart`:
/// zero imports beyond `dart:core`, so this is trivially testable and
/// reusable. Callers (the application layer, see
/// `lib/application/notification_scheduler.dart` and
/// `lib/app/providers.dart`) own reading "now", counting occurrences, and
/// turning a [DigestPlan] into an actual scheduled OS notification.
library;

/// A resolved decision to fire the digest notification at [fireAt] with the
/// given content counts.
///
/// `null` (returned by [planDigestSlot] instead of an instance) means "don't
/// schedule anything": the digest is disabled, or there is nothing to say.
class DigestPlan {
  /// Creates a plan.
  const DigestPlan({
    required this.fireAt,
    required this.dueTodayCount,
    required this.overdueCount,
    this.soleOccurrenceId,
  });

  /// The device-local moment the notification should fire.
  final DateTime fireAt;

  /// The number of pending occurrences due on [fireAt]'s calendar date.
  ///
  /// Despite the name (kept identical to the spec's contract), this is NOT
  /// always "due today" in the sense of *now*'s calendar date: for a
  /// tomorrow slot, it's the count of occurrences due on that tomorrow
  /// date. See [nextDigestSlot].
  final int dueTodayCount;

  /// The number of pending occurrences overdue as of [fireAt]'s calendar
  /// date (due strictly before it).
  final int overdueCount;

  /// The id of the single pending occurrence this slot is about, or `null`
  /// when the slot is about more than one (spec
  /// `docs/specs/notifications.md` N2).
  ///
  /// Non-null exactly when `dueTodayCount + overdueCount == 1` — the one
  /// case where the chore a notification ACTION names is unambiguous, so
  /// this is what gates the digest's "Done" button per slot.
  ///
  /// **This class does not enforce that invariant**, deliberately:
  /// [planDigestSlot] stays pure and carries whatever the caller determined,
  /// and `projectDigestCounts` (`lib/domain/digest_projection.dart`) is the
  /// single place that decides it — because it is the only place that
  /// applies the same recipient scoping and the same projected-due-date
  /// comparison the counts themselves do. Re-deriving the gate here would
  /// be a second copy of both rules.
  final String? soleOccurrenceId;

  @override
  bool operator ==(Object other) =>
      other is DigestPlan &&
      other.fireAt == fireAt &&
      other.dueTodayCount == dueTodayCount &&
      other.overdueCount == overdueCount &&
      other.soleOccurrenceId == soleOccurrenceId;

  @override
  int get hashCode =>
      Object.hash(fireAt, dueTodayCount, overdueCount, soleOccurrenceId);

  @override
  String toString() =>
      'DigestPlan(fireAt: $fireAt, dueTodayCount: $dueTodayCount, '
      'overdueCount: $overdueCount, soleOccurrenceId: $soleOccurrenceId)';
}

/// The next digest slot after [now]: today at the wall-clock time
/// [digestMinutes] represents, if that time is still ahead of [now];
/// otherwise the same wall-clock time tomorrow.
///
/// Deliberately built from calendar components (`DateTime(y, m, d, h, min)`)
/// rather than `now.add(const Duration(days: 1))`: adding a fixed 24-hour
/// duration would shift the wall-clock hour across a daylight-saving
/// transition (the local difference between two calendar days is not
/// always 24 hours), and would also fail to normalize month/year rollovers
/// the way callers expect. Reconstructing from calendar components instead
/// always lands on the same local hour:minute on the target calendar day —
/// which is what "digest at 8am" means to a user, DST or not — and Dart's
/// `DateTime` constructor already normalizes an out-of-range day into the
/// correct following month/year.
///
/// Exposed separately from [planDigestSlot] so callers can determine which
/// calendar date's occurrence counts to fetch *before* calling
/// [planDigestSlot] — both use this exact same rule, so there's no
/// duplicated "which slot" logic to keep in sync.
///
/// [digestMinutes] must be in `0..1439` (minutes since local midnight);
/// throws [ArgumentError] otherwise.
DateTime nextDigestSlot({required DateTime now, required int digestMinutes}) {
  _validateDigestMinutes(digestMinutes);
  final hour = digestMinutes ~/ 60;
  final minute = digestMinutes % 60;
  final todayCandidate = DateTime(now.year, now.month, now.day, hour, minute);
  if (todayCandidate.isAfter(now)) {
    return todayCandidate;
  }
  return DateTime(now.year, now.month, now.day + 1, hour, minute);
}

/// How many *consecutive daily* digest slots the horizon opens with (spec
/// `docs/specs/notifications.md` architecture #2).
///
/// The digest is a *one-shot* OS notification per slot, and nothing re-arms
/// it while the app is closed — so a single slot goes silent the morning
/// after it fires, for exactly the users a reminder exists to serve
/// (`docs/feedback/2026-08-08-prerelease-audit.md` P0). These are the days
/// on which the digest keeps its full daily cadence.
///
/// Fourteen: two weeks of unbroken daily cadence matches a plausible
/// holiday, which is the gap most likely to be survived without the user
/// ever noticing the horizon exists.
// INVERSION (Task 13 step 2 inversion 1). To be reverted.
const int digestDailyHorizonDays = 25;

/// How many *trailing* digest slots follow the daily segment, spaced
/// [digestHorizonTailStepDays] apart.
///
/// The tail trades cadence for reach: it costs one notification id per
/// [digestHorizonTailStepDays] days of coverage instead of one per day. It
/// loses no coverage, because work cannot disappear while the app is
/// closed, so a sampled slot still reports everything the skipped days
/// would have (see `docs/plans/2026-08-14-digest-horizon-ceiling.md` §2).
///
/// Ten, at weekly spacing, is what takes the horizon's reach from days to
/// months: the same 24 ids spent as consecutive days would reach only day
/// 23, where segmented they reach day 83. Someone who has not opened the
/// app in a fortnight is not
/// helped by a daily reminder they are already ignoring.
const int digestWeeklyHorizonSlots = 10;

/// The spacing, in days, between consecutive slots in the trailing segment.
const int digestHorizonTailStepDays = 7;

/// How many digest notification slots are armed with the OS at once: the
/// daily segment plus the trailing segment.
///
/// Note the unit is *slots*, not days — [digestSlots] no longer returns a
/// flat run of calendar days. The horizon's reach in days is
/// `digestDailyHorizonDays - 1 + digestHorizonTailStepDays *
/// digestWeeklyHorizonSlots` — 83 days at the shipped values. Arming a
/// whole horizon means the digest only degrades after that many unopened
/// days, and degrades into silence rather than into wrong counts.
///
/// **What this number actually trades: notification ids against
/// unopened-day coverage.** Horizon length buys no *accuracy* — the
/// projection assumes the local database does not change, which is exactly
/// true while the app is closed, so staleness is binary and applies equally
/// at day 2. What a longer horizon buys is the difference between a
/// possibly-stale count and no notification at all.
///
/// The budget it spends is iOS's 64-pending-notification cap, and since
/// schema v13 that cap is spent EXACTLY, three ways: 24 here, 33 for
/// per-chore reminders (`reminderCeiling`) and 7 for the evening
/// re-reminder (`eveningHorizonSlots`) -- see
/// `docs/specs/notifications-n2.md` §3.1's table, which is the
/// renegotiation the old `digestHorizonSlots <= 32` guard existed to force.
/// That guard is gone, REPLACED rather than deleted, by
/// `test/application/notification_scheduler_test.dart`'s pair: the three
/// counts sum to at most 64, and the three id ranges are pairwise disjoint,
/// both computed from the constants (§3.3).
///
/// **There is no slack left.** Raising this number now takes ids from one
/// of the other two ranges and must amend §3.1's table to say which. See
/// also "Notification id budget" in `docs/specs/notifications.md`, and
/// `docs/plans/2026-08-14-digest-horizon-ceiling.md` for the original
/// reasoning.
const int digestHorizonSlots =
    digestDailyHorizonDays + digestWeeklyHorizonSlots;

/// The next [digestHorizonSlots] digest slots after [now]: [nextDigestSlot],
/// then [dailyDays] - 1 further slots on each following calendar day, then
/// [weeklySlots] further slots at [digestHorizonTailStepDays] spacing.
///
/// Daily slot `k` (`0 <= k < dailyDays`) sits at day offset `k` from the
/// first slot; tail slot `j` (`0 <= j < weeklySlots`) sits at day offset
/// `(dailyDays - 1) + digestHorizonTailStepDays * (j + 1)`, so exactly one
/// tail step separates the last daily slot from the first tail one. The
/// result is always in ascending `fireAt` order.
///
/// Every slot — daily or tail — is built from calendar components rather
/// than `add(Duration(days: n))` for the same DST reason [nextDigestSlot]
/// documents, and the hour/minute are re-derived from [digestMinutes]
/// rather than read off the first slot, because a spring-forward day can
/// normalize a nonexistent wall-clock time into a different hour, which
/// would then propagate to every later slot.
///
/// [digestMinutes] must be in `0..1439`; [dailyDays] must be >= 1;
/// [weeklySlots] must be >= 0. Throws [ArgumentError] otherwise.
List<DateTime> digestSlots({
  required DateTime now,
  required int digestMinutes,
  int dailyDays = digestDailyHorizonDays,
  int weeklySlots = digestWeeklyHorizonSlots,
}) {
  _validateDigestMinutes(digestMinutes);
  if (dailyDays < 1) {
    throw ArgumentError.value(dailyDays, 'dailyDays', 'Must be >= 1');
  }
  if (weeklySlots < 0) {
    throw ArgumentError.value(weeklySlots, 'weeklySlots', 'Must be >= 0');
  }
  final hour = digestMinutes ~/ 60;
  final minute = digestMinutes % 60;
  final first = nextDigestSlot(now: now, digestMinutes: digestMinutes);
  return [
    for (var k = 0; k < dailyDays; k++)
      DateTime(first.year, first.month, first.day + k, hour, minute),
    for (var j = 0; j < weeklySlots; j++)
      DateTime(
        first.year,
        first.month,
        first.day + (dailyDays - 1) + digestHorizonTailStepDays * (j + 1),
        hour,
        minute,
      ),
  ];
}

/// Decides whether one already-chosen slot at [fireAt] should fire.
///
/// Returns `null` (don't schedule this day; the caller cancels that day's
/// notification id instead) when [enabled] is `false`, or when both counts
/// are zero — silence is a feature, and with a horizon it is now decided
/// per day rather than once. An overdue-only day still notifies.
///
/// [dueTodayCount] and [overdueCount] must already be computed for
/// [fireAt]'s own calendar date — see
/// `lib/domain/digest_projection.dart`.
///
/// [soleOccurrenceId] is threaded through untouched; this function does not
/// decide it and applies no invariant to it — see
/// [DigestPlan.soleOccurrenceId].
DigestPlan? planDigestSlot({
  required DateTime fireAt,
  required bool enabled,
  required int dueTodayCount,
  required int overdueCount,
  String? soleOccurrenceId,
}) {
  if (!enabled) {
    return null;
  }
  if (dueTodayCount == 0 && overdueCount == 0) {
    return null;
  }
  return DigestPlan(
    fireAt: fireAt,
    dueTodayCount: dueTodayCount,
    overdueCount: overdueCount,
    soleOccurrenceId: soleOccurrenceId,
  );
}

void _validateDigestMinutes(int digestMinutes) {
  if (digestMinutes < 0 || digestMinutes > 1439) {
    throw ArgumentError.value(
      digestMinutes,
      'digestMinutes',
      'Must be in 0..1439 (minutes since local midnight)',
    );
  }
}
