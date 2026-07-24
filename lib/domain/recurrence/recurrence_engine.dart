/// Free functions implementing [Recurrence] semantics.
///
/// No function here reads a clock: "today" (or any other reference date) is
/// always passed in explicitly, which keeps this whole module pure and
/// deterministic.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';

/// Returns the lazy, **infinite**, strictly increasing series of occurrence
/// dates for [rule] anchored at [startDate]. Every element is >= [startDate].
///
/// Callers must bound consumption with `.take(k)`, `.takeWhile(...)`, or
/// similar. The series is defined per [RecurrenceUnit]:
///
/// - **day**: `startDate + k * interval` days, for k = 0, 1, 2, ...
/// - **week**: weeks are ISO weeks (Monday..Sunday). The week containing
///   [startDate] is week offset 0; active weeks are those whose offset is
///   `0 (mod interval)`. The effective weekday set is [Recurrence.weekdays]
///   if non-empty, else `{startDate.weekday}`. Occurrences are every date in
///   an active week whose weekday is in that set, filtered to >= startDate.
/// - **month**: months at offset `k * interval` from startDate's month, for
///   k = 0, 1, 2, ..., filtered to >= startDate. In [MonthlyMode.dayOfMonth]
///   the target day is startDate.day, clamped to the month's length. In
///   [MonthlyMode.nthWeekday] it is the `monthlyOrdinal`-th `monthlyWeekday`
///   of the month (`-1` = last), which always exists for ordinals 1..4 and
///   -1.
Iterable<PlainDate> scheduleOccurrences(Recurrence rule, PlainDate startDate) {
  switch (rule.unit) {
    case RecurrenceUnit.day:
      return _dayOccurrences(rule, startDate);
    case RecurrenceUnit.week:
      return _weekOccurrences(rule, startDate);
    case RecurrenceUnit.month:
      return _monthOccurrences(rule, startDate);
  }
}

/// Returns the first element of [scheduleOccurrences] that is >= [date].
///
/// **Performance contract**: efficient for [date] up to ~50 years past
/// [startDate]. This jumps to the right neighbourhood by closed-form
/// arithmetic on the occurrence index and then scans only a small bounded
/// window (at most a couple of candidate weeks/months) — it never walks the
/// series day-by-day or occurrence-by-occurrence across the whole span.
PlainDate nextScheduledOnOrAfter(
  Recurrence rule,
  PlainDate startDate,
  PlainDate date,
) {
  switch (rule.unit) {
    case RecurrenceUnit.day:
      return _nextDayOnOrAfter(rule, startDate, date);
    case RecurrenceUnit.week:
      return _nextWeekOnOrAfter(rule, startDate, date);
    case RecurrenceUnit.month:
      return _nextMonthOnOrAfter(rule, startDate, date);
  }
}

/// Returns the next due date for a completion-anchored [rule], given the
/// actual date the previous occurrence was completed ([completedOn]):
///
/// - **day**: `completedOn + interval` days.
/// - **week**, empty weekdays: `completedOn + interval * 7` days.
/// - **week**, non-empty weekdays: candidate = `completedOn + interval * 7`
///   days, then rolled **forward** 0..6 days to the nearest matching
///   weekday.
/// - **month** ([MonthlyMode.dayOfMonth] only — [Recurrence.validated]
///   forbids [MonthlyMode.nthWeekday] with a completion anchor):
///   `completedOn.addMonths(interval)`.
PlainDate nextAfterCompletion(Recurrence rule, PlainDate completedOn) {
  switch (rule.unit) {
    case RecurrenceUnit.day:
      return completedOn.addDays(rule.interval);
    case RecurrenceUnit.week:
      final candidate = completedOn.addDays(rule.interval * 7);
      if (rule.weekdays.isEmpty) {
        return candidate;
      }
      for (var offset = 0; offset < 7; offset++) {
        final rolled = candidate.addDays(offset);
        if (rule.weekdays.contains(rolled.weekday)) {
          return rolled;
        }
      }
      // Unreachable: weekdays is validated to be a non-empty subset of
      // 1..7, so every 7-day window contains a match.
      throw StateError('Unreachable: no matching weekday found in a full week');
    case RecurrenceUnit.month:
      return completedOn.addMonths(rule.interval);
  }
}

/// Due date of the very first occurrence when a chore governed by [rule] is
/// created with the given [startDate]:
///
/// - schedule anchor: the first element of [scheduleOccurrences].
/// - completion anchor: [startDate] itself (the user picks when it starts).
PlainDate firstDueDate(Recurrence rule, PlainDate startDate) {
  switch (rule.anchor) {
    case RecurrenceAnchor.schedule:
      return scheduleOccurrences(rule, startDate).first;
    case RecurrenceAnchor.completion:
      return startDate;
  }
}

/// Due date of the next occurrence after closing one, whether it was
/// completed ("done") or explicitly skipped — the engine treats both
/// identically as "closing" an occurrence. (For completion-anchored chores
/// the app is expected to pass the skip date as [closedOn]; there is no
/// special casing here.)
///
/// - completion anchor: [nextAfterCompletion] applied to [closedOn].
/// - schedule anchor: the first series element **strictly after**
///   `max(closedDueDate, closedOn)`. Completing very late therefore skips
///   the missed slots instead of surfacing an instantly-overdue next
///   occurrence — this is a deliberate product decision, not a bug.
PlainDate nextDueDateAfterClosing({
  required Recurrence rule,
  required PlainDate startDate,
  required PlainDate closedDueDate,
  required PlainDate closedOn,
}) {
  switch (rule.anchor) {
    case RecurrenceAnchor.completion:
      return nextAfterCompletion(rule, closedOn);
    case RecurrenceAnchor.schedule:
      final threshold = closedDueDate.isAfter(closedOn)
          ? closedDueDate
          : closedOn;
      return nextScheduledOnOrAfter(rule, startDate, threshold.addDays(1));
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// The Monday of the ISO week containing [date].
PlainDate _mondayOf(PlainDate date) => date.addDays(1 - date.weekday);

Iterable<PlainDate> _dayOccurrences(
  Recurrence rule,
  PlainDate startDate,
) sync* {
  var k = 0;
  while (true) {
    yield startDate.addDays(k * rule.interval);
    k++;
  }
}

Iterable<PlainDate> _weekOccurrences(
  Recurrence rule,
  PlainDate startDate,
) sync* {
  final startMonday = _mondayOf(startDate);
  final sortedWeekdays = _effectiveWeekdays(rule, startDate);
  var k = 0;
  while (true) {
    final weekMonday = startMonday.addDays(7 * k * rule.interval);
    for (final weekday in sortedWeekdays) {
      final candidate = weekMonday.addDays(weekday - 1);
      if (candidate.isOnOrAfter(startDate)) {
        yield candidate;
      }
    }
    k++;
  }
}

/// The effective weekday set for a week-unit [rule] (falling back to
/// [startDate]'s own weekday when [Recurrence.weekdays] is empty), sorted
/// ascending so iteration order matches chronological order within a week.
List<int> _effectiveWeekdays(Recurrence rule, PlainDate startDate) {
  final weekdaySet = rule.weekdays.isNotEmpty
      ? rule.weekdays
      : {startDate.weekday};
  return weekdaySet.toList()..sort();
}

/// The date of the [ordinal]-th [weekday] in [year]-[month] (`-1` = last).
/// Always well-defined for ordinals 1..4 and -1: every month has at least 4
/// occurrences of each weekday.
PlainDate _nthWeekdayOfMonth(int year, int month, int ordinal, int weekday) {
  if (ordinal == -1) {
    final lastDay = PlainDate(year, month, PlainDate.daysInMonth(year, month));
    final backOffset = (lastDay.weekday - weekday) % 7;
    return lastDay.addDays(-backOffset);
  }
  final firstOfMonth = PlainDate(year, month, 1);
  final forwardOffset = (weekday - firstOfMonth.weekday) % 7;
  final firstMatch = firstOfMonth.addDays(forwardOffset);
  return firstMatch.addDays(7 * (ordinal - 1));
}

/// The occurrence date within [year]-[month] for a month-unit [rule], mode
/// aware. Ignores [startDate]'s year/month, using only its day (for
/// [MonthlyMode.dayOfMonth]) or the rule's nth-weekday fields.
PlainDate _monthCandidate(
  Recurrence rule,
  PlainDate startDate,
  int year,
  int month,
) {
  if (rule.monthlyMode == MonthlyMode.nthWeekday) {
    return _nthWeekdayOfMonth(
      year,
      month,
      rule.monthlyOrdinal!,
      rule.monthlyWeekday!,
    );
  }
  final maxDay = PlainDate.daysInMonth(year, month);
  final targetDay = startDate.day < maxDay ? startDate.day : maxDay;
  return PlainDate(year, month, targetDay);
}

Iterable<PlainDate> _monthOccurrences(
  Recurrence rule,
  PlainDate startDate,
) sync* {
  var k = 0;
  while (true) {
    final targetMonth = startDate.addMonths(k * rule.interval);
    final candidate = _monthCandidate(
      rule,
      startDate,
      targetMonth.year,
      targetMonth.month,
    );
    if (candidate.isOnOrAfter(startDate)) {
      yield candidate;
    }
    k++;
  }
}

PlainDate _nextDayOnOrAfter(
  Recurrence rule,
  PlainDate startDate,
  PlainDate date,
) {
  if (!date.isAfter(startDate)) {
    return startDate;
  }
  final elapsed = startDate.daysUntil(date);
  var k = elapsed ~/ rule.interval;
  var candidate = startDate.addDays(k * rule.interval);
  while (candidate.isBefore(date)) {
    k++;
    candidate = startDate.addDays(k * rule.interval);
  }
  return candidate;
}

PlainDate _nextWeekOnOrAfter(
  Recurrence rule,
  PlainDate startDate,
  PlainDate date,
) {
  if (!date.isAfter(startDate)) {
    return scheduleOccurrences(rule, startDate).first;
  }
  final startMonday = _mondayOf(startDate);
  final dateMonday = _mondayOf(date);
  final weeksDiff = startMonday.daysUntil(dateMonday) ~/ 7;
  final sortedWeekdays = _effectiveWeekdays(rule, startDate);

  // Jump to the active week at/just before date's week, then scan forward.
  // Provably terminates within at most two active weeks (see spec's
  // performance contract): either date's own week is active and contains a
  // match, or the next active week is entirely after date and its first
  // pinned weekday is the answer.
  var k = weeksDiff ~/ rule.interval;
  while (true) {
    final weekMonday = startMonday.addDays(7 * k * rule.interval);
    for (final weekday in sortedWeekdays) {
      final candidate = weekMonday.addDays(weekday - 1);
      if (!candidate.isBefore(date)) {
        return candidate;
      }
    }
    k++;
  }
}

PlainDate _nextMonthOnOrAfter(
  Recurrence rule,
  PlainDate startDate,
  PlainDate date,
) {
  if (!date.isAfter(startDate)) {
    return scheduleOccurrences(rule, startDate).first;
  }
  final startMonthIndex = startDate.year * 12 + (startDate.month - 1);
  final dateMonthIndex = date.year * 12 + (date.month - 1);
  final rawDiff = dateMonthIndex - startMonthIndex;

  // Same two-step bounded scan as the weekly case, one month-slot at a time.
  var k = rawDiff ~/ rule.interval;
  while (true) {
    final targetMonthIndex = startMonthIndex + k * rule.interval;
    final targetYear = targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final candidate = _monthCandidate(rule, startDate, targetYear, targetMonth);
    if (!candidate.isBefore(date)) {
      return candidate;
    }
    k++;
  }
}
