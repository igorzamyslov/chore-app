/// Pure helpers turning chore-form recurrence state into a [Recurrence], and
/// generating the monthly-mode chips' descriptive labels.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';

/// Full weekday names, Monday (index 0) .. Sunday (index 6).
const List<String> weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Short weekday labels, Monday (index 0) .. Sunday (index 6), for the
/// weekday chip row.
const List<String> weekdayShortNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Builds the [Recurrence] described by the chore form's current repeat
/// field values. Only call this when the repeat toggle is on; a one-off
/// chore simply passes `recurrence: null` to the service instead of calling
/// this at all.
///
/// For a month unit with [MonthlyMode.nthWeekday] (only reachable with a
/// schedule anchor; see `docs/specs/ui-foundation-chores.md`), the ordinal
/// and weekday are derived from [startDate] via [nthWeekdayOrdinalOf].
Recurrence buildRecurrence({
  required int interval,
  required RecurrenceUnit unit,
  required RecurrenceAnchor anchor,
  required Set<int> weekdays,
  required MonthlyMode monthlyMode,
  required PlainDate startDate,
}) {
  switch (unit) {
    case RecurrenceUnit.day:
      return Recurrence.everyNDays(interval, anchor: anchor);
    case RecurrenceUnit.week:
      return Recurrence.weekly(
        interval: interval,
        weekdays: weekdays,
        anchor: anchor,
      );
    case RecurrenceUnit.month:
      if (anchor == RecurrenceAnchor.schedule &&
          monthlyMode == MonthlyMode.nthWeekday) {
        final ordinal = nthWeekdayOrdinalOf(startDate);
        return Recurrence.monthlyOnNthWeekday(
          ordinal,
          startDate.weekday,
          interval: interval,
        );
      }
      return Recurrence.monthlyOnDay(interval: interval, anchor: anchor);
  }
}

/// Which occurrence of its own weekday [date] is within its month: 1..4, or
/// `-1` for the 5th (i.e. the last) occurrence.
///
/// Every month has at least 4 occurrences of every weekday, so only the 5th
/// needs the `-1` ("last") encoding [Recurrence] uses.
int nthWeekdayOrdinalOf(PlainDate date) {
  final ordinal = (date.day - 1) ~/ 7 + 1;
  return ordinal > 4 ? -1 : ordinal;
}

/// The snake_case semantic-id qualifier for [mode], per
/// `chore_form.repeat.monthly_mode.<day_of_month|nth_weekday>`.
String monthlyModeId(MonthlyMode mode) {
  return mode == MonthlyMode.dayOfMonth ? 'day_of_month' : 'nth_weekday';
}

/// The monthly day-of-month chip's label, e.g. `'On the 15th'`.
String monthlyDayOfMonthLabel(PlainDate date) {
  return 'On the ${_ordinal(date.day)}';
}

/// The monthly nth-weekday chip's label, e.g. `'On the 3rd Tuesday'` or
/// `'On the last Tuesday'`.
String monthlyNthWeekdayLabel(PlainDate date) {
  final ordinal = nthWeekdayOrdinalOf(date);
  final weekdayName = weekdayNames[date.weekday - 1];
  final ordinalText = ordinal == -1 ? 'last' : _ordinal(ordinal);
  return 'On the $ordinalText $weekdayName';
}

/// Renders [n] with its English ordinal suffix, e.g. `'1st'`, `'22nd'`.
String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) {
    return '${n}th';
  }
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}
