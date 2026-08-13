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

  @override
  bool operator ==(Object other) =>
      other is DigestPlan &&
      other.fireAt == fireAt &&
      other.dueTodayCount == dueTodayCount &&
      other.overdueCount == overdueCount;

  @override
  int get hashCode => Object.hash(fireAt, dueTodayCount, overdueCount);

  @override
  String toString() =>
      'DigestPlan(fireAt: $fireAt, dueTodayCount: $dueTodayCount, '
      'overdueCount: $overdueCount)';
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

/// How many consecutive daily digest slots are armed with the OS at once
/// (spec `docs/specs/notifications.md` architecture #2).
///
/// The digest is a *one-shot* OS notification per day, and nothing re-arms
/// it while the app is closed — so a single slot goes silent the morning
/// after it fires, for exactly the users a reminder exists to serve
/// (`docs/feedback/2026-08-08-prerelease-audit.md` P0). Arming a whole
/// horizon means the digest only degrades after this many consecutive
/// unopened days, and degrades into silence rather than into wrong counts.
///
/// Seven is comfortably inside iOS's 64-pending-notification cap and needs
/// no new platform capability.
const int digestHorizonDays = 7;

/// The next [horizonDays] digest slots after [now]: [nextDigestSlot], then
/// the same local wall-clock time on each following calendar day.
///
/// Built from calendar components rather than `add(Duration(days: 1))` for
/// the same DST reason [nextDigestSlot] documents — and the hour/minute are
/// re-derived from [digestMinutes] rather than read off the first slot,
/// because a spring-forward day can normalize a nonexistent wall-clock time
/// into a different hour, which would then propagate to every later slot.
///
/// [digestMinutes] must be in `0..1439`; [horizonDays] must be >= 1. Throws
/// [ArgumentError] otherwise.
List<DateTime> digestSlots({
  required DateTime now,
  required int digestMinutes,
  int horizonDays = digestHorizonDays,
}) {
  _validateDigestMinutes(digestMinutes);
  if (horizonDays < 1) {
    throw ArgumentError.value(horizonDays, 'horizonDays', 'Must be >= 1');
  }
  final hour = digestMinutes ~/ 60;
  final minute = digestMinutes % 60;
  final first = nextDigestSlot(now: now, digestMinutes: digestMinutes);
  return [
    for (var k = 0; k < horizonDays; k++)
      DateTime(first.year, first.month, first.day + k, hour, minute),
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
DigestPlan? planDigestSlot({
  required DateTime fireAt,
  required bool enabled,
  required int dueTodayCount,
  required int overdueCount,
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
