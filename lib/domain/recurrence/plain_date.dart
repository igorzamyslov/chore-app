// `PlainDate` has a single final field and no mutating members, so it is
// effectively immutable; we deliberately don't import `package:meta` (lib
// code is dart:core only) to add the `@immutable` annotation the lint below
// wants.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// A calendar date with no time-of-day and no timezone.
///
/// Internally backed by a UTC midnight [DateTime] so it can reuse Dart's
/// calendar arithmetic (leap years, month lengths) without ever being
/// affected by the local timezone or daylight-saving transitions. The engine
/// built on top of this type never reads the local clock — "today" is always
/// passed in explicitly — which is what makes it deterministic and testable.
class PlainDate implements Comparable<PlainDate> {
  /// Creates a date from its calendar components.
  ///
  /// Throws [ArgumentError] if [month] is not in 1..12, or if [day] is not a
  /// valid day of that year/month (e.g. February 30th, or February 29th in a
  /// non-leap year).
  PlainDate(int year, int month, int day)
    : _dateTime = _validate(year, month, day);

  /// Creates a [PlainDate] from [dateTime]'s calendar components (year,
  /// month, day), ignoring its time-of-day and timezone entirely.
  factory PlainDate.fromDateTime(DateTime dateTime) =>
      PlainDate(dateTime.year, dateTime.month, dateTime.day);

  /// Parses an ISO-8601 calendar date string, e.g. `"2026-07-24"`.
  ///
  /// Throws [FormatException] if [iso] is not well-formed, or does not
  /// represent a valid calendar date.
  factory PlainDate.parse(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) {
      throw FormatException('Not an ISO-8601 date (yyyy-mm-dd)', iso);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (!_isValidDate(year, month, day)) {
      throw FormatException('Not a valid calendar date', iso);
    }
    return PlainDate._(DateTime.utc(year, month, day));
  }

  PlainDate._(this._dateTime);

  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static DateTime _validate(int year, int month, int day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'Must be in 1..12');
    }
    final maxDay = _daysInMonthUnchecked(year, month);
    if (day < 1 || day > maxDay) {
      throw ArgumentError.value(
        day,
        'day',
        'Must be in 1..$maxDay for $year-$month',
      );
    }
    return DateTime.utc(year, month, day);
  }

  static bool _isValidDate(int year, int month, int day) {
    if (month < 1 || month > 12) {
      return false;
    }
    final maxDay = _daysInMonthUnchecked(year, month);
    return day >= 1 && day <= maxDay;
  }

  // Day 0 of the following month is the last day of this one. Callers must
  // have already validated that month is in 1..12.
  static int _daysInMonthUnchecked(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  /// Returns the number of days in [month] of [year] (28..31).
  ///
  /// [month] must be in 1..12.
  static int daysInMonth(int year, int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'Must be in 1..12');
    }
    return _daysInMonthUnchecked(year, month);
  }

  final DateTime _dateTime;

  /// The calendar year, e.g. `2026`.
  int get year => _dateTime.year;

  /// The calendar month, 1 (January) .. 12 (December).
  int get month => _dateTime.month;

  /// The day of the month, 1..31.
  int get day => _dateTime.day;

  /// The ISO weekday: Monday = 1 .. Sunday = 7 (same convention as
  /// [DateTime.weekday]).
  int get weekday => _dateTime.weekday;

  /// Returns the date [n] days after this one. [n] may be negative.
  PlainDate addDays(int n) => PlainDate._(_dateTime.add(Duration(days: n)));

  /// Returns the date [n] months after this one. [n] may be negative.
  ///
  /// The day of month is clamped to the target month's length: e.g.
  /// `2026-01-31` + 1 month -> `2026-02-28` (`2028-02-29` in a leap year).
  /// Note this deliberately does not use `DateTime.utc(y, m + n, day)`
  /// directly: Dart would roll an out-of-range day into the *next* month
  /// (Feb 30 -> Mar 2), which is not the clamping semantics we want.
  PlainDate addMonths(int n) {
    // DateTime.utc normalizes an out-of-range *month* by carrying into the
    // year, so this always lands on the first of the correct target month.
    final firstOfTargetMonth = DateTime.utc(year, month + n);
    final maxDay = daysInMonth(
      firstOfTargetMonth.year,
      firstOfTargetMonth.month,
    );
    final targetDay = day < maxDay ? day : maxDay;
    return PlainDate(
      firstOfTargetMonth.year,
      firstOfTargetMonth.month,
      targetDay,
    );
  }

  /// The signed number of days from this date to [other] (`other - this`).
  ///
  /// Negative if [other] is before this date.
  int daysUntil(PlainDate other) =>
      other._dateTime.difference(_dateTime).inDays;

  /// Whether this date is strictly before [other].
  bool isBefore(PlainDate other) => _dateTime.isBefore(other._dateTime);

  /// Whether this date is strictly after [other].
  bool isAfter(PlainDate other) => _dateTime.isAfter(other._dateTime);

  /// Whether this date is [other] or earlier.
  bool isOnOrBefore(PlainDate other) => !isAfter(other);

  /// Whether this date is [other] or later.
  bool isOnOrAfter(PlainDate other) => !isBefore(other);

  /// Formats this date as an ISO-8601 calendar date, e.g. `"2026-07-24"`.
  String toIso8601() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  int compareTo(PlainDate other) => _dateTime.compareTo(other._dateTime);

  @override
  bool operator ==(Object other) =>
      other is PlainDate && other._dateTime == _dateTime;

  @override
  int get hashCode => _dateTime.hashCode;

  @override
  String toString() => toIso8601();
}
