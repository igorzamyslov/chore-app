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
/// Since G-2 every part of the pattern is passed in explicitly rather than
/// derived from the start date: [monthlyDayOfMonth] (1..31, or `-1` for the
/// last day), [monthlyOrdinal] (1..4, or `-1` for last) and
/// [monthlyWeekday]. Removing that hidden derivation is the whole point of
/// the ticket. The values that do not apply to the chosen shape are simply
/// not read, and `monthlyDayOfMonth` is passed as `null` for a
/// completion-anchored rule, where the engine ignores it and
/// [Recurrence.validated] rejects it.
///
/// **This is the single funnel to a persisted rule**, which is why the
/// OPD-2 invariant is asserted here: an nth-weekday pattern is a position in
/// the calendar, so it only makes sense with a schedule anchor, and
/// `Recurrence.validated` throws on the combination. The form makes that
/// combination unreachable by removing the completion card in weekday mode;
/// the assert is so a future refactor that reintroduces it fails in debug
/// here, rather than as an `ArgumentError` thrown out of a save the user
/// already tapped.
Recurrence buildRecurrence({
  required int interval,
  required RecurrenceUnit unit,
  required RecurrenceAnchor anchor,
  required Set<int> weekdays,
  required MonthlyMode monthlyMode,
  required int monthlyDayOfMonth,
  required int monthlyOrdinal,
  required int monthlyWeekday,
}) {
  assert(
    monthlyMode != MonthlyMode.nthWeekday ||
        anchor == RecurrenceAnchor.schedule,
    'OPD-2: an nth-weekday monthly pattern is a position in the calendar, '
    'so there is nothing for a completion date to count from, and '
    'Recurrence.validated throws on the pair. The form must not offer the '
    'completion anchor while the monthly mode is nthWeekday.',
  );
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
        return Recurrence.monthlyOnNthWeekday(
          monthlyOrdinal,
          monthlyWeekday,
          interval: interval,
        );
      }
      return Recurrence.monthlyOnDay(
        interval: interval,
        anchor: anchor,
        // `nextAfterCompletion` reads no monthly field, so a day on a
        // completion-anchored rule would silently do nothing; `validated`
        // rejects it for exactly that reason.
        monthlyDayOfMonth: anchor == RecurrenceAnchor.schedule
            ? monthlyDayOfMonth
            : null,
      );
  }
}

/// The interval to *render* with, for the raw text currently in the chore
/// form's interval field.
///
/// Always >= 1. `validateInterval` is what actually blocks save, but the
/// repeat block re-renders on every keystroke and has to show something
/// sensible in the meantime -- including while the field is empty or holds
/// a `0` the user is halfway through replacing.
///
/// The clamp is not cosmetic. Before G-2 this reading only pluralized a
/// noun, so a zero was harmless; the preview line now feeds it to the
/// recurrence engine, whose week and month branches divide by the interval.
/// `int.tryParse(text) ?? 1` alone covers an unparseable field but not a
/// parseable `0`, which reached `weeksDiff ~/ interval` and crashed the
/// form under the user as they typed.
int displayInterval(String raw) {
  final parsed = int.tryParse(raw.trim());
  return parsed == null || parsed < 1 ? 1 : parsed;
}

/// Moves [startDate] to the nearest date **on or after** it whose day of
/// month is [dayOfMonth], or -- for the `-1` "last day" sentinel -- to the
/// last day of [startDate]'s own month.
///
/// This is how the chore form maintains
/// [Recurrence.monthlyDayOfMonth]'s alignment contract: keeping
/// `startDate.day == monthlyDayOfMonth` makes a client predating that field
/// compute an identical series, because its derived branch
/// `min(startDate.day, daysInMonth)` is then the same expression as this
/// one's `min(monthlyDayOfMonth, daysInMonth)`. See that field's doc.
///
/// **Forwards only.** `scheduleOccurrences` filters to
/// `isOnOrAfter(startDate)` and `firstDueDate` reads the first element, so
/// moving the start date backwards would put the first occurrence in the
/// past. The move can be large -- picking the 31st on the 1st of February
/// lands on 31 March, because February has no 31st -- but it is visible in
/// the Start date field in the same form, on the same frame, and the user
/// can override it.
///
/// For `-1` this stays inside the start date's **own** month and accepts
/// the residual divergence documented on
/// [Recurrence.monthlyDayOfMonth]: at most 3 days, always with the older
/// client early. Jumping to a 31st in some later month would make an old
/// client agree exactly, but only by deleting every occurrence before that
/// month from the series and delaying the chore by up to 31 days -- paid by
/// every household, including the single-version ones that had no
/// divergence to fix.
PlainDate alignStartDateToMonthlyDay(PlainDate startDate, int dayOfMonth) {
  if (dayOfMonth == -1) {
    return PlainDate(
      startDate.year,
      startDate.month,
      PlainDate.daysInMonth(startDate.year, startDate.month),
    );
  }
  if (startDate.day == dayOfMonth) {
    return startDate;
  }
  var year = startDate.year;
  var month = startDate.month;
  // INVERSION (a): move backwards instead of forwards.
  if (startDate.day < dayOfMonth) {
    (year, month) = _nextMonth(year, month);
  }
  // ...and skip any month too short to contain it at all: the 31st simply
  // does not exist in February, so the nearest 31st after 1 Feb is in March.
  while (PlainDate.daysInMonth(year, month) < dayOfMonth) {
    (year, month) = _nextMonth(year, month);
  }
  return PlainDate(year, month, dayOfMonth);
}

(int, int) _nextMonth(int year, int month) {
  return month == 12 ? (year + 1, 1) : (year, month + 1);
}

/// Which occurrence of its own weekday [date] is within its month: 1..4, or
/// `-1` for the 5th (i.e. the last) occurrence.
///
/// Since G-2 this is a **seeding** helper, not part of the save path: the
/// chore form calls it once to give the sentence's ordinal hole a sensible
/// starting value, and to fill in the ordinal for an already-persisted rule
/// that predates the explicit field. `buildRecurrence` no longer derives
/// anything from the start date.
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
