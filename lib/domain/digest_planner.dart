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
/// `null` (returned by [planDigest] instead of an instance) means "don't
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
/// Exposed separately from [planDigest] so callers can determine which
/// calendar date's occurrence counts to fetch *before* calling [planDigest]
/// (see that function's doc comment) — both use this exact same rule, so
/// there's no duplicated "which slot" logic to keep in sync.
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

/// Decides whether/when to (re)schedule the daily digest notification.
///
/// Returns `null` (don't schedule) when [enabled] is `false`, or when both
/// [dueTodayCount] and [overdueCount] are zero — silence is a feature: a
/// notification with nothing to say would make the signal meaningless, and
/// this holds even when overdue-only (an overdue-only day still notifies,
/// via a non-zero [overdueCount] with [dueTodayCount] at zero).
///
/// Otherwise returns a [DigestPlan] firing at [nextDigestSlot].
///
/// [dueTodayCount] and [overdueCount] must already be computed by the
/// caller for the correct date: whichever calendar date [nextDigestSlot]
/// resolves to (today or tomorrow), not necessarily *now*'s calendar date.
/// This function is pure and can't fetch that data itself — call
/// [nextDigestSlot] first (with the same [now]/[digestMinutes]) to know
/// which date to count occurrences for.
///
/// [digestMinutes] must be in `0..1439` (minutes since local midnight);
/// throws [ArgumentError] otherwise.
DigestPlan? planDigest({
  required DateTime now,
  required int digestMinutes,
  required bool enabled,
  required int dueTodayCount,
  required int overdueCount,
}) {
  _validateDigestMinutes(digestMinutes);
  if (!enabled) {
    return null;
  }
  if (dueTodayCount == 0 && overdueCount == 0) {
    return null;
  }
  return DigestPlan(
    fireAt: nextDigestSlot(now: now, digestMinutes: digestMinutes),
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
