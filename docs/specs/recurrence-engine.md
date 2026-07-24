# Spec: Recurrence Engine

*The heart of the app. Pure Dart, zero Flutter imports, zero runtime
dependencies. If you can't unit-test it in isolation, it doesn't belong here.*

## Placement

| What | Where |
|---|---|
| `PlainDate` value type | `lib/domain/recurrence/plain_date.dart` |
| `Recurrence` model + enums | `lib/domain/recurrence/recurrence.dart` |
| Engine functions | `lib/domain/recurrence/recurrence_engine.dart` |
| Tests | `test/domain/recurrence/*_test.dart` (one test file per lib file) |

No imports of `dart:io`, `dart:ui`, or any `package:flutter/*` anywhere in
`lib/domain/`. Only `dart:core` (+ `dart:math` in tests).

## 1. `PlainDate` — calendar date value type

A date with no time and no timezone. Internally backed by `DateTime.utc(y,m,d)`
to reuse Dart's calendar arithmetic (leap years, month lengths), but the API
exposes only date semantics. **The engine never touches local time or
`DateTime.now()`** — that is what makes it DST-proof and testable.

```dart
class PlainDate implements Comparable<PlainDate> {
  PlainDate(int year, int month, int day);        // throws ArgumentError on
                                                  // invalid dates (e.g. Feb 30)
  factory PlainDate.fromDateTime(DateTime dt);    // takes dt's calendar
                                                  // components as-is
  factory PlainDate.parse(String iso);            // "2026-07-24", throws
                                                  // FormatException on garbage
  int get year; int get month; int get day;
  int get weekday;                                // ISO: Mon=1 … Sun=7
                                                  // (same as DateTime.weekday)
  PlainDate addDays(int n);                       // n may be negative
  PlainDate addMonths(int n);                     // clamps day: Jan 31 +1mo →
                                                  // Feb 28 (29 in leap years)
  int daysUntil(PlainDate other);                 // signed; other - this
  bool isBefore/isAfter/isOnOrBefore/isOnOrAfter(PlainDate other);
  String toIso8601();                             // "2026-07-24"
  static int daysInMonth(int year, int month);
  // + ==, hashCode, compareTo, toString (ISO form)
}
```

## 2. `Recurrence` model

```dart
enum RecurrenceUnit { day, week, month }
enum RecurrenceAnchor {
  schedule,    // fixed calendar series from the chore's startDate
               // ("trash every Tuesday" — missing one doesn't shift the series)
  completion,  // next due = N units after the actual last completion
               // ("water plants every 4 days" — doing it late shifts everything)
}
enum MonthlyMode { dayOfMonth, nthWeekday }
```

```dart
class Recurrence {
  final int interval;             // every N units, >= 1
  final RecurrenceUnit unit;
  final RecurrenceAnchor anchor;
  final Set<int> weekdays;        // week unit only. ISO 1..7. Empty set =
                                  // "derive from startDate.weekday".
  final MonthlyMode monthlyMode;  // month unit only. Default: dayOfMonth
                                  // (target day = startDate.day, clamped).
  final int? monthlyOrdinal;      // nthWeekday mode: 1..4, or -1 = "last"
  final int? monthlyWeekday;      // nthWeekday mode: ISO 1..7
}
```

Weekdays use plain `int` 1..7 (`DateTime.monday`..`DateTime.sunday`) — no
custom enum duplicating what the SDK has.

**Validation** — the unnamed const-able constructor is permissive; a
`Recurrence.validated(...)` factory (used by all convenience factories and
`fromJson`) throws `ArgumentError` on:

- `interval < 1`
- `weekdays` non-empty when `unit != week`; any value outside 1..7
- `monthlyOrdinal`/`monthlyWeekday` set when `monthlyMode != nthWeekday`
- `monthlyMode == nthWeekday` and (`monthlyOrdinal` not in {1,2,3,4,-1} or
  `monthlyWeekday` not in 1..7 or either is null)
- `monthlyMode == nthWeekday` when `unit != month`
- `monthlyMode == nthWeekday` when `anchor == completion` (nth-weekday pinning
  only makes sense for fixed series)

**Convenience factories** (all delegate to `validated`):

```dart
Recurrence.everyNDays(int n, {RecurrenceAnchor anchor = .schedule});
Recurrence.weekly({int interval = 1, Set<int> weekdays = const {},
                   RecurrenceAnchor anchor = .schedule});
Recurrence.monthlyOnDay({int interval = 1, RecurrenceAnchor anchor = .schedule});
Recurrence.monthlyOnNthWeekday(int ordinal, int weekday, {int interval = 1});
```

**JSON**: `toJson()` / `Recurrence.fromJson(Map<String, Object?>)` with
snake_case keys (`interval`, `unit`, `anchor`, `weekdays`, `monthly_mode`,
`monthly_ordinal`, `monthly_weekday`); enums serialized as their `name`.
`fromJson` throws `FormatException` on unknown enum values / wrong types, and
routes through `validated` (bad combos → `ArgumentError`). Round-trip must be
lossless. Hand-written, no codegen.

## 3. Engine semantics

Free functions in `recurrence_engine.dart`. **No function reads a clock;
"today" is always a parameter.**

### Schedule anchor — the occurrence series

`scheduleOccurrences(Recurrence rule, PlainDate startDate)` →
lazy **infinite** `Iterable<PlainDate>`, strictly increasing, all ≥ `startDate`.
Callers use `.take(k)` / `.takeWhile(...)`. Series definition per unit:

- **day**: `startDate + k·interval` days, k = 0, 1, 2, …
- **week**: weeks are ISO weeks (Monday–Sunday). The week containing
  `startDate` is week offset 0; active weeks have offset ≡ 0 (mod `interval`).
  Effective weekday set `W` = `rule.weekdays` if non-empty, else
  `{startDate.weekday}`. Occurrences = every date in an active week whose
  weekday ∈ W, filtered to ≥ `startDate`.
  (So weekly-on-Saturday starting Wednesday 2026-07-22 begins Sat 2026-07-25,
  same week. Multiple pinned weekdays yield multiple occurrences per active
  week.)
- **month**: months at offset k·interval from `startDate`'s month, k = 0, 1, …
  - `dayOfMonth`: target day = `startDate.day`, clamped to the month's length
    (start Jan 31 → Feb 28, Mar 31, Apr 30, …).
  - `nthWeekday`: the `monthlyOrdinal`-th `monthlyWeekday` of the month
    (`-1` = last). Always exists for ordinals 1..4 and -1.
  - Filtered to ≥ `startDate`.

`nextScheduledOnOrAfter(Recurrence rule, PlainDate startDate, PlainDate date)`
→ first element of the series that is ≥ `date`.
**Performance contract**: must be efficient for `date` up to ~50 years past
`startDate` — jump by closed-form arithmetic on k (day/week/month offsets),
then scan only a bounded local window (≤ interval·7 days / a few months).
Never iterate day-by-day or occurrence-by-occurrence across the whole span.

### Completion anchor

`nextAfterCompletion(Recurrence rule, PlainDate completedOn)`:

- **day**: `completedOn + interval` days.
- **week**, `weekdays` empty: `completedOn + interval·7` days.
- **week**, `weekdays` = W: candidate = `completedOn + interval·7` days, then
  roll **forward** 0–6 days to the nearest weekday ∈ W.
- **month** (`dayOfMonth` mode only — validation forbids nthWeekday here):
  `completedOn.addMonths(interval)` (clamped by `addMonths`).

### Unified helpers (what the app layer will actually call)

```dart
/// Due date of the very first occurrence when a chore is created.
PlainDate firstDueDate(Recurrence rule, PlainDate startDate);
//   schedule   → first element of scheduleOccurrences
//   completion → startDate itself (user picks when it starts)

/// Due date of the next occurrence after closing one (done or skipped).
PlainDate nextDueDateAfterClosing({
  required Recurrence rule,
  required PlainDate startDate,
  required PlainDate closedDueDate,   // due date of the occurrence closed
  required PlainDate closedOn,        // date the user closed it
});
//   completion → nextAfterCompletion(rule, closedOn)
//   schedule   → first series element STRICTLY AFTER
//                max(closedDueDate, closedOn)
//                (completing very late skips the missed slots — you don't get
//                an instantly-overdue next occurrence; product decision)
```

`skip` and `done` are identical to the engine — both "close" an occurrence.
(For completion-anchored chores the app passes the skip date as `closedOn`;
documented in a doc comment, no special casing.)

## 4. Testing requirements

`dart test` green; aim for ~100% line coverage of the three lib files.
Table-driven `group`/`test` style. **Must include at least:**

1. **PlainDate**: validity (Feb 30, month 13 → ArgumentError; 2028-02-29
   valid, 2027-02-29 invalid), addMonths clamping, weekday correctness for
   known dates, parse/toIso8601 round-trip, ordering & equality,
   daysUntil signs, DST immunity note-test: `addDays` across 2026-03-29 and
   2026-10-25 (Europe/Berlin DST transitions) shifts exactly 1 calendar day.
2. **Daily schedule**: start 2026-01-01 interval 3 → 01-01, 01-04, 01-07, …;
   `nextScheduledOnOrAfter(..., 2026-01-05)` = 2026-01-07; on an exact
   occurrence date returns that date.
3. **Weekly**: {sat} interval 1 starting Wed 2026-07-22 → first is
   2026-07-25. {mon,thu} interval 2 starting Mon 2026-07-20 → 07-20, 07-23,
   08-03, 08-06, … {sun} starting Mon → Sunday of the *same* ISO week
   (+6 days). Empty weekdays derives from startDate.
4. **Monthly dayOfMonth**: start 2026-01-31 interval 1 → 02-28, 03-31, 04-30,
   …; crosses into leap year 2028 → 2028-02-29. Interval 2 skips months.
   Year rollover (start Nov, interval 3 → Feb next year).
5. **Monthly nthWeekday**: first Saturday from 2026-07-04 → 2026-08-01,
   2026-09-05; last Friday (ordinal -1) cases including a month where last
   Friday is the 5th Friday.
6. **Completion anchor**: every-4-days completed early/late shifts the next
   date; weekly {sat} completed Tue 2026-07-21 interval 1 → candidate Tue
   07-28 rolls forward to Sat 2026-08-01; monthly from Jan 31 → Feb 28.
7. **nextDueDateAfterClosing**: schedule-anchored chore due Tue closed the
   following Thu → next is next Tue; closed 3 weeks late → missed slots are
   skipped, result strictly after `closedOn`; completion-anchored uses
   `closedOn` not `closedDueDate`.
8. **Validation**: one test per ArgumentError bullet in §2; FormatException
   for bad JSON enum value.
9. **JSON round-trip**: representative rule of every unit/anchor/mode combo.
10. **Seeded invariant tests** (use `Random(42)`, ≥ 500 iterations; no
    dependency beyond `dart:math`): generate random valid rules and dates;
    assert (a) every weekly occurrence's weekday ∈ effective W; (b)
    `scheduleOccurrences` is strictly increasing and all ≥ startDate; (c)
    `nextScheduledOnOrAfter(d)` ≥ d and is an element of the series; (d)
    `nextDueDateAfterClosing` > max(closedDueDate, closedOn) for schedule
    anchor; (e) day-unit occurrences satisfy `(occ − start) % interval == 0`
    in days.
11. **Performance sanity**: `nextScheduledOnOrAfter` with `date` 50 years
    after startDate completes for all units in well under a second
    (plain expectation, no benchmark harness).

## 5. Style

- `very_good_analysis` lints must pass (`flutter analyze` clean).
- Doc comments (`///`) on every public symbol; semantics comments where the
  spec is subtle (week-offset math, clamping, roll-forward).
- No codegen, no external packages.
