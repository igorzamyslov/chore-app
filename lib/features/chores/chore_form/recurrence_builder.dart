/// Pure helpers turning chore-form recurrence state into a [Recurrence], and
/// computing the data behind the monthly-mode chips' descriptive labels.
///
/// The labels themselves are ARB messages (see `MonthlyModeRow`); this file
/// only supplies their already-localized ingredients — weekday names via
/// `package:intl` (never a hardcoded weekday list) and ordinal text via
/// [localizedOrdinal].
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:intl/intl.dart';

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

// An arbitrary Monday (2024-01-01), used purely as an anchor so an ISO
// weekday number can be resolved to a real [DateTime] for
// `package:intl`'s locale-aware weekday formatting below.
final DateTime _referenceMonday = DateTime.utc(2024);

/// The full display name of ISO [weekday] (1 = Monday .. 7 = Sunday) in
/// [localeName], e.g. `'Tuesday'` (en) or `'Dienstag'` (de) — sourced from
/// `package:intl`, never a hardcoded weekday list.
String weekdayName(int weekday, String localeName) {
  return DateFormat.EEEE(
    localeName,
  ).format(_referenceMonday.add(Duration(days: weekday - 1)));
}

/// The abbreviated display name of ISO [weekday] (1 = Monday .. 7 = Sunday)
/// in [localeName], e.g. `'Tue'` (en) or `'Di'` (de), for the weekday chip
/// row — sourced from `package:intl`, never a hardcoded weekday list.
String weekdayShortName(int weekday, String localeName) {
  return DateFormat.E(
    localeName,
  ).format(_referenceMonday.add(Duration(days: weekday - 1)));
}

/// The narrow (single- or double-letter) display name of ISO [weekday]
/// (1 = Monday .. 7 = Sunday) in [localeName], e.g. `'T'` (en) or `'D'` (de)
/// — sourced from `package:intl`, never a hardcoded weekday list. Used by
/// the weekday circular toggles (spec `docs/specs/theme-v2.md` §4.4 item 3),
/// which are too small for the abbreviated 3-letter form; the full weekday
/// name still carries the accessibility label, so the narrow glyph's
/// occasional ambiguity (e.g. 'T' for both Tuesday and Thursday) never
/// reaches a screen reader.
String weekdayNarrowName(int weekday, String localeName) {
  return DateFormat.EEEEE(
    localeName,
  ).format(_referenceMonday.add(Duration(days: weekday - 1)));
}

/// The already-localized ordinal text for [n] (e.g. `'15th'` in en,
/// `'15.'` in de), used by the monthly-mode chip labels.
///
/// English's irregular 1st/2nd/3rd/4th…/11th/12th/13th suffixes can't be
/// expressed as an ICU `plural`/`select` ARB message (`flutter gen-l10n`
/// doesn't support ICU's `selectordinal`), so this computes the
/// already-localized ordinal text here, gated on locale, and the ARB
/// templates just interpolate the result — the English suffix rule itself
/// never appears in (or leaks into) another locale's output.
String localizedOrdinal(int n, String localeName) {
  if (localeName.startsWith('de')) {
    return '$n.';
  }
  return _englishOrdinal(n);
}

/// Renders [n] with its English ordinal suffix, e.g. `'1st'`, `'22nd'`.
String _englishOrdinal(int n) {
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
