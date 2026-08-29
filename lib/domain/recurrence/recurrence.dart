// `Recurrence` has only final fields and no mutating members, so it is
// effectively immutable; we deliberately don't import `package:meta` (lib
// code is dart:core only) to add the `@immutable` annotation the lint below
// wants (same convention as `plain_date.dart` and `digest_planner.dart`).
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// The unit of time a [Recurrence] repeats on.
enum RecurrenceUnit {
  /// Every N days.
  day,

  /// Every N ISO weeks (Monday..Sunday).
  week,

  /// Every N months.
  month,
}

/// How the due date of the next occurrence is anchored.
enum RecurrenceAnchor {
  /// A fixed calendar series starting from the chore's start date. Missing
  /// an occurrence does not shift the rest of the series (e.g. "trash every
  /// Tuesday").
  schedule,

  /// The next due date is N units after the actual completion date (e.g.
  /// "water plants every 4 days" — doing it late shifts everything after).
  completion,
}

/// How a month-unit [Recurrence] picks its target day within the month.
enum MonthlyMode {
  /// Target day = [Recurrence.monthlyDayOfMonth], clamped to the target
  /// month's length; or, when that is null, the start date's day of month,
  /// clamped the same way.
  dayOfMonth,

  /// The [Recurrence.monthlyOrdinal]-th [Recurrence.monthlyWeekday] of the
  /// month (e.g. "the first Saturday", "the last Friday").
  nthWeekday,
}

/// A rule describing how often and on what pattern a chore recurs.
///
/// This unnamed constructor is intentionally permissive (no validation) so
/// it stays `const`-able; use [Recurrence.validated] or one of the named
/// convenience factories to construct a rule that is guaranteed consistent.
class Recurrence {
  /// Creates a recurrence rule without validating field combinations.
  ///
  /// Prefer [Recurrence.validated] or a named factory such as
  /// [Recurrence.everyNDays], which enforce the invariants documented on
  /// each field.
  const Recurrence({
    required this.interval,
    required this.unit,
    required this.anchor,
    this.weekdays = const {},
    this.monthlyMode = MonthlyMode.dayOfMonth,
    this.monthlyOrdinal,
    this.monthlyWeekday,
    this.monthlyDayOfMonth,
  });

  /// Creates a recurrence rule, throwing [ArgumentError] if the fields form
  /// an inconsistent combination:
  ///
  /// - [interval] < 1.
  /// - [weekdays] non-empty when [unit] is not [RecurrenceUnit.week], or any
  ///   value outside 1..7.
  /// - [monthlyOrdinal] or [monthlyWeekday] set when [monthlyMode] is not
  ///   [MonthlyMode.nthWeekday].
  /// - [monthlyMode] is [MonthlyMode.nthWeekday] and [monthlyOrdinal] is not
  ///   one of `{1, 2, 3, 4, -1}`, or [monthlyWeekday] is not in 1..7, or
  ///   either is null.
  /// - [monthlyMode] is [MonthlyMode.nthWeekday] when [unit] is not
  ///   [RecurrenceUnit.month].
  /// - [monthlyMode] is [MonthlyMode.nthWeekday] when [anchor] is
  ///   [RecurrenceAnchor.completion] (nth-weekday pinning only makes sense
  ///   for a fixed calendar series).
  /// - [monthlyDayOfMonth] is set when [unit] is not [RecurrenceUnit.month],
  ///   when [monthlyMode] is not [MonthlyMode.dayOfMonth], or when [anchor]
  ///   is [RecurrenceAnchor.completion] -- the engine reads it in none of
  ///   those cases, so a value there would silently do nothing.
  /// - [monthlyDayOfMonth] is set and is neither `-1` nor in 1..31.
  factory Recurrence.validated({
    required int interval,
    required RecurrenceUnit unit,
    required RecurrenceAnchor anchor,
    Set<int> weekdays = const {},
    MonthlyMode monthlyMode = MonthlyMode.dayOfMonth,
    int? monthlyOrdinal,
    int? monthlyWeekday,
    int? monthlyDayOfMonth,
  }) {
    if (interval < 1) {
      throw ArgumentError.value(interval, 'interval', 'Must be >= 1');
    }
    if (weekdays.isNotEmpty && unit != RecurrenceUnit.week) {
      throw ArgumentError.value(
        weekdays,
        'weekdays',
        'Only valid when unit == week',
      );
    }
    if (weekdays.any((weekday) => weekday < 1 || weekday > 7)) {
      throw ArgumentError.value(weekdays, 'weekdays', 'Values must be in 1..7');
    }
    if (monthlyMode != MonthlyMode.nthWeekday) {
      if (monthlyOrdinal != null) {
        throw ArgumentError.value(
          monthlyOrdinal,
          'monthlyOrdinal',
          'Only valid when monthlyMode == nthWeekday',
        );
      }
      if (monthlyWeekday != null) {
        throw ArgumentError.value(
          monthlyWeekday,
          'monthlyWeekday',
          'Only valid when monthlyMode == nthWeekday',
        );
      }
    } else {
      if (unit != RecurrenceUnit.month) {
        throw ArgumentError.value(
          unit,
          'unit',
          'nthWeekday mode requires unit == month',
        );
      }
      if (anchor == RecurrenceAnchor.completion) {
        throw ArgumentError.value(
          anchor,
          'anchor',
          'nthWeekday mode is not supported with a completion anchor',
        );
      }
      if (monthlyOrdinal == null ||
          !{1, 2, 3, 4, -1}.contains(monthlyOrdinal)) {
        throw ArgumentError.value(
          monthlyOrdinal,
          'monthlyOrdinal',
          'Must be 1, 2, 3, 4, or -1',
        );
      }
      if (monthlyWeekday == null || monthlyWeekday < 1 || monthlyWeekday > 7) {
        throw ArgumentError.value(
          monthlyWeekday,
          'monthlyWeekday',
          'Must be in 1..7',
        );
      }
    }
    if (monthlyDayOfMonth != null) {
      if (unit != RecurrenceUnit.month) {
        throw ArgumentError.value(
          monthlyDayOfMonth,
          'monthlyDayOfMonth',
          'Only valid when unit == month',
        );
      }
      if (monthlyMode != MonthlyMode.dayOfMonth) {
        throw ArgumentError.value(
          monthlyDayOfMonth,
          'monthlyDayOfMonth',
          'Only valid when monthlyMode == dayOfMonth',
        );
      }
      // The completion branch of the engine is
      // `completedOn.addMonths(interval)` and reads no monthly field at
      // all, so a day here would be a value that silently does nothing --
      // a trap for the next reader rather than a feature.
      if (anchor == RecurrenceAnchor.completion) {
        throw ArgumentError.value(
          monthlyDayOfMonth,
          'monthlyDayOfMonth',
          'Only valid with a schedule anchor',
        );
      }
      if (monthlyDayOfMonth != -1 &&
          (monthlyDayOfMonth < 1 || monthlyDayOfMonth > 31)) {
        throw ArgumentError.value(
          monthlyDayOfMonth,
          'monthlyDayOfMonth',
          'Must be in 1..31, or -1 for the last day of the month',
        );
      }
    }
    return Recurrence(
      interval: interval,
      unit: unit,
      anchor: anchor,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      monthlyOrdinal: monthlyOrdinal,
      monthlyWeekday: monthlyWeekday,
      monthlyDayOfMonth: monthlyDayOfMonth,
    );
  }

  /// Creates a day-unit rule that recurs every [n] days.
  factory Recurrence.everyNDays(
    int n, {
    RecurrenceAnchor anchor = RecurrenceAnchor.schedule,
  }) {
    return Recurrence.validated(
      interval: n,
      unit: RecurrenceUnit.day,
      anchor: anchor,
    );
  }

  /// Creates a week-unit rule.
  ///
  /// An empty [weekdays] derives its effective weekday from the chore's
  /// start date.
  factory Recurrence.weekly({
    int interval = 1,
    Set<int> weekdays = const {},
    RecurrenceAnchor anchor = RecurrenceAnchor.schedule,
  }) {
    return Recurrence.validated(
      interval: interval,
      unit: RecurrenceUnit.week,
      anchor: anchor,
      weekdays: weekdays,
    );
  }

  /// Creates a month-unit rule targeting [monthlyDayOfMonth] (clamped to
  /// each target month's length), or -- when that is omitted -- the start
  /// date's day of month, clamped the same way.
  factory Recurrence.monthlyOnDay({
    int interval = 1,
    RecurrenceAnchor anchor = RecurrenceAnchor.schedule,
    int? monthlyDayOfMonth,
  }) {
    return Recurrence.validated(
      interval: interval,
      unit: RecurrenceUnit.month,
      anchor: anchor,
      monthlyDayOfMonth: monthlyDayOfMonth,
    );
  }

  /// Creates a month-unit rule pinned to the [ordinal]-th [weekday] of the
  /// month (`-1` for "last"). Schedule-anchored only.
  factory Recurrence.monthlyOnNthWeekday(
    int ordinal,
    int weekday, {
    int interval = 1,
  }) {
    return Recurrence.validated(
      interval: interval,
      unit: RecurrenceUnit.month,
      anchor: RecurrenceAnchor.schedule,
      monthlyMode: MonthlyMode.nthWeekday,
      monthlyOrdinal: ordinal,
      monthlyWeekday: weekday,
    );
  }

  /// Deserializes a rule produced by [toJson].
  ///
  /// Throws [FormatException] if a field is missing, has the wrong type, or
  /// (for enum fields) an unrecognized name. Field combinations are then
  /// checked via [Recurrence.validated], which throws [ArgumentError] for an
  /// inconsistent combination of otherwise well-typed fields.
  factory Recurrence.fromJson(Map<String, Object?> json) {
    final intervalRaw = json['interval'];
    if (intervalRaw is! int) {
      throw FormatException('"interval" must be an int', json);
    }

    final unit = _enumFromJson(RecurrenceUnit.values, json['unit'], 'unit');
    final anchor = _enumFromJson(
      RecurrenceAnchor.values,
      json['anchor'],
      'anchor',
    );
    final monthlyMode = _enumFromJson(
      MonthlyMode.values,
      json['monthly_mode'],
      'monthly_mode',
    );

    final weekdaysRaw = json['weekdays'];
    if (weekdaysRaw is! List<Object?>) {
      throw FormatException('"weekdays" must be a list', json);
    }
    final weekdays = <int>{};
    for (final entry in weekdaysRaw) {
      if (entry is! int) {
        throw FormatException('"weekdays" entries must be ints', json);
      }
      weekdays.add(entry);
    }

    final monthlyOrdinalRaw = json['monthly_ordinal'];
    if (monthlyOrdinalRaw is! int?) {
      throw FormatException('"monthly_ordinal" must be an int or null', json);
    }
    final monthlyWeekdayRaw = json['monthly_weekday'];
    if (monthlyWeekdayRaw is! int?) {
      throw FormatException('"monthly_weekday" must be an int or null', json);
    }
    // Added by G-2, after rules were already in the wild: a map written by
    // any earlier client simply has no such key, and a missing key reads as
    // null here -- which is exactly the documented "derive the day from the
    // chore's start date" default those rules already meant. Same `is! int?`
    // shape as the two fields above.
    final monthlyDayOfMonthRaw = json['monthly_day_of_month'];
    if (monthlyDayOfMonthRaw is! int?) {
      throw FormatException(
        '"monthly_day_of_month" must be an int or null',
        json,
      );
    }

    return Recurrence.validated(
      interval: intervalRaw,
      unit: unit,
      anchor: anchor,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      monthlyOrdinal: monthlyOrdinalRaw,
      monthlyWeekday: monthlyWeekdayRaw,
      monthlyDayOfMonth: monthlyDayOfMonthRaw,
    );
  }

  static T _enumFromJson<T extends Enum>(
    List<T> values,
    Object? raw,
    String field,
  ) {
    if (raw is! String) {
      throw FormatException('"$field" must be a string', raw);
    }
    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    throw FormatException('Unknown "$field" value', raw);
  }

  /// Recur every N units. Must be >= 1.
  final int interval;

  /// The unit of time this rule repeats on.
  final RecurrenceUnit unit;

  /// Whether this rule is a fixed calendar series or anchored to
  /// completions.
  final RecurrenceAnchor anchor;

  /// ISO weekdays (1 = Monday .. 7 = Sunday) this rule applies to.
  /// [RecurrenceUnit.week] only. Empty means "derive from the chore's start
  /// date weekday".
  final Set<int> weekdays;

  /// How the target day of month is picked. [RecurrenceUnit.month] only.
  final MonthlyMode monthlyMode;

  /// [MonthlyMode.nthWeekday] only: which occurrence of [monthlyWeekday] in
  /// the month, 1..4, or -1 for "last".
  final int? monthlyOrdinal;

  /// [MonthlyMode.nthWeekday] only: the ISO weekday (1..7) to target.
  final int? monthlyWeekday;

  /// [MonthlyMode.dayOfMonth] with a [RecurrenceAnchor.schedule] anchor
  /// only: the day of the month to target, 1..31, or `-1` for "the last day
  /// of the month" (the same `-1` = "last" convention [monthlyOrdinal]
  /// uses -- one class, one encoding for "last"; `32` would be a
  /// valid-looking day number that a naive 1..31 range check would let
  /// through).
  ///
  /// `null` means "derive the day from the chore's start date", which is
  /// what every rule persisted before this field existed means, and remains
  /// the behaviour for those rows forever. A day past the target month's
  /// length is clamped, so `31` lands on Feb 28 (Feb 29 in a leap year).
  ///
  /// **Alignment contract -- callers must keep `startDate.day` equal to this
  /// field** (G-2 OPD-1, `docs/plans/2026-08-18-repeat-form-sentence.md`
  /// Analysis §2a; the chore form is the only caller that sets it, and it
  /// maintains this from both the day picker and the start-date picker).
  /// The reason is cross-version convergence, and it is exact: this rule is
  /// serialized as JSON into an opaque `TEXT` column and synced verbatim, so
  /// a household member on a client predating this field decodes the row
  /// with the unknown key ignored and evaluates the derived branch,
  /// `min(startDate.day, daysInMonth)`. This field's branch is
  /// `min(monthlyDayOfMonth, daysInMonth)`. Those are the SAME expression
  /// whenever `startDate.day == monthlyDayOfMonth`, so the two devices
  /// compute a byte-identical series for the whole infinite series --
  /// divergence is zero, not merely bounded, for every day in 1..31.
  ///
  /// This field is **authoritative**; `startDate.day` is a redundant mirror
  /// maintained only for those older clients, and the engine never reads
  /// `startDate.day` while this is non-null. `Recurrence` cannot enforce the
  /// contract, because it never sees the start date -- it is an invariant
  /// the form maintains, which is why it is documented here rather than
  /// checked in [Recurrence.validated].
  ///
  /// **`-1` is the one value with no exact `startDate` mirror.** Since
  /// `daysInMonth <= 31` always, `min(31, daysInMonth) == daysInMonth`, so a
  /// start date on a 31st would converge exactly -- but the 31st only exists
  /// in 31-day months, and forcing the start date into one would delete the
  /// earlier occurrences from the series. So "last day" keeps a residual: at
  /// most **3 days**, always with the older client **early**, never late, so
  /// nothing is silently missed. It is zero when the start date happens to
  /// sit in a 31-day month, at most 1 day for a 30-day month, at most 3 for
  /// February, and it disappears permanently the moment that device updates.
  final int? monthlyDayOfMonth;

  /// Serializes this rule to a JSON-compatible map with snake_case keys.
  /// Enums are serialized as their `name` (e.g. `RecurrenceUnit.week` ->
  /// `"week"`).
  Map<String, Object?> toJson() {
    return {
      'interval': interval,
      'unit': unit.name,
      'anchor': anchor.name,
      'weekdays': weekdays.toList()..sort(),
      'monthly_mode': monthlyMode.name,
      'monthly_ordinal': monthlyOrdinal,
      'monthly_weekday': monthlyWeekday,
      'monthly_day_of_month': monthlyDayOfMonth,
    };
  }

  /// Value equality over all eight fields, with [weekdays] compared as an
  /// unordered set (backlog E-4).
  ///
  /// Without this, a rule round-tripped through [toJson] and
  /// [Recurrence.fromJson] -- which is what every persisted rule is --
  /// compared unequal to the original, so any "did the recurrence change?"
  /// check silently answered "yes, always".
  ///
  /// Note the knock-on effect this deliberately unlocks:
  /// drift's generated `Chore` data class compares its `recurrence` field
  /// with `==`, so two `Chore` rows carrying the same rule now compare
  /// equal too, which is the correct answer and the one callers expect.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Recurrence &&
        other.interval == interval &&
        other.unit == unit &&
        other.anchor == anchor &&
        other.monthlyMode == monthlyMode &&
        other.monthlyOrdinal == monthlyOrdinal &&
        other.monthlyWeekday == monthlyWeekday &&
        other.monthlyDayOfMonth == monthlyDayOfMonth &&
        _weekdaysEqual(other.weekdays, weekdays);
  }

  @override
  int get hashCode {
    // Sets aren't order-stable, so folding `weekdays` into `Object.hash`
    // directly would hash `{1, 3}` and `{3, 1}` differently even though
    // they compare equal above -- breaking the "equal objects hash equally"
    // contract, which is exactly what a `Set<Recurrence>` or a
    // `Map<Recurrence, ...>` relies on. XOR-folding each element's hash is
    // order-independent, and needs no `package:collection` import (see the
    // dart:core-only note at the top of this file).
    final weekdaysHash = weekdays.fold<int>(
      0,
      (acc, day) => acc ^ day.hashCode,
    );
    return Object.hash(
      interval,
      unit,
      anchor,
      monthlyMode,
      monthlyOrdinal,
      monthlyWeekday,
      monthlyDayOfMonth,
      weekdaysHash,
    );
  }

  static bool _weekdaysEqual(Set<int> a, Set<int> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.every(b.contains);
  }
}
