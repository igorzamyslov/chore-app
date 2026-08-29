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
  final MonthlyMode monthlyMode;  // month unit only. Default: dayOfMonth.
  final int? monthlyOrdinal;      // nthWeekday mode: 1..4, or -1 = "last"
  final int? monthlyWeekday;      // nthWeekday mode: ISO 1..7
  final int? monthlyDayOfMonth;   // dayOfMonth mode + schedule anchor only:
                                  // 1..31, or -1 = "the last day of the
                                  // month". null = derive from
                                  // startDate.day (clamped), which is what
                                  // every rule persisted before G-2 means.
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
- `monthlyDayOfMonth` set when `unit != month`, when
  `monthlyMode != dayOfMonth`, or when `anchor == completion` — the engine
  reads it in none of those cases, so a value there would silently do
  nothing
- `monthlyDayOfMonth` set and neither `-1` nor in 1..31. `-1` is the same
  "last" sentinel `monthlyOrdinal` uses: one class, one encoding. `32` was
  rejected as an alternative because it is a valid-looking day number that a
  naive 1..31 range check would wave through into the database

**Convenience factories** (all delegate to `validated`):

```dart
Recurrence.everyNDays(int n, {RecurrenceAnchor anchor = .schedule});
Recurrence.weekly({int interval = 1, Set<int> weekdays = const {},
                   RecurrenceAnchor anchor = .schedule});
Recurrence.monthlyOnDay({int interval = 1, RecurrenceAnchor anchor = .schedule,
                        int? monthlyDayOfMonth});
Recurrence.monthlyOnNthWeekday(int ordinal, int weekday, {int interval = 1});
```

**JSON**: `toJson()` / `Recurrence.fromJson(Map<String, Object?>)` with
snake_case keys (`interval`, `unit`, `anchor`, `weekdays`, `monthly_mode`,
`monthly_ordinal`, `monthly_weekday`, `monthly_day_of_month`); enums
serialized as their `name`.
`fromJson` throws `FormatException` on unknown enum values / wrong types, and
routes through `validated` (bad combos → `ArgumentError`). Round-trip must be
lossless. Hand-written, no codegen.

### 2.1 The `monthlyDayOfMonth` alignment invariant (G-2, 2026-08-29)

`monthly_day_of_month` was added to a JSON shape that was already in the
wild. `Chores.recurrence` is an opaque nullable `TEXT` column on both the
drift and the Supabase side, so this needed **no migration and no
schema-version bump** — but it does create a cross-device hazard, and the
mitigation is part of the contract rather than a nicety.

**The hazard.** A client writes `"monthly_day_of_month": 20` and syncs the
row verbatim. A household member still on an older build decodes it,
ignores the unknown key, and computes the due date from `startDate.day`
instead. Two phones in one household then disagree about when a chore is
due, with no error anywhere. Silent cross-device divergence is the failure
class this project hunts hardest, so it does not get to stand as a noted
cost.

**The mitigation, and it is exact.** The old client's day-of-month branch
is `min(startDate.day, daysInMonth)`. The new branch is
`min(monthlyDayOfMonth, daysInMonth)`. These are the **same expression**
whenever `startDate.day == monthlyDayOfMonth`. So the form keeps the start
date aligned to the chosen day, and an un-updated device computes a
**byte-identical series, forever**. Divergence is not bounded, it is zero,
for every day in 1..31.

- `monthlyDayOfMonth` is **authoritative**; `startDate.day` is a redundant
  mirror kept solely for older clients, and the engine never reads
  `startDate.day` while the field is non-null.
- Alignment is maintained in **both directions** by the chore form: picking
  a day moves the start date, and moving the start date re-derives the day.
  Only maintaining the first would let a user save a rule whose mirror
  disagrees — and that gap can fall either way, meaning the older client
  could be *late*, which the safety argument below depends on not happening.
- Alignment moves the start date **forwards only** — the nearest date on or
  after the current one whose day matches — because `scheduleOccurrences`
  filters to `isOnOrAfter(startDate)` and `firstDueDate` reads the first
  element, so moving it backwards would put the first occurrence in the
  past. The move can be large (picking the 31st on 1 February lands on 31
  March), but it happens in a field the user is looking at and can override.
- `Recurrence` cannot enforce any of this, because it never sees the start
  date. It is an invariant the form maintains, documented on the field.

**The residual: `-1` alone.** "Last day" is the one value with no exact
`startDate` mirror. Since `daysInMonth <= 31` always,
`min(31, daysInMonth) == daysInMonth`, so a start date on a **31st** would
converge exactly — but the 31st only exists in 31-day months, and forcing
the start date into one would delete every earlier occurrence from the
series and delay the chore by up to 31 days, paid by every household
including the single-version ones that had no divergence to fix. So the form
does not do that: it aligns to the last day of the start date's **own**
month and accepts the residual.

| Start month's length | Aligned `startDate.day` | Old client computes | Divergence |
| --- | --- | --- | --- |
| 31 | 31 | last day, every month | **none** |
| 30 | 30 | 30th, or 28th/29th in February | **≤ 1 day, old client early** |
| 28/29 | 28 or 29 | 28th/29th | **≤ 3 days, old client early** |

The residual is confined to "last day" rules, is at most **3 days**, and is
**always in the safe direction** — the un-updated device shows the chore due
*earlier*, never later, so nothing is silently missed. It converges
permanently the moment that device updates, and it never occurs at all for a
household on one version or for any non-"last day" rule.

`test/domain/recurrence/recurrence_engine_test.dart`'s
"cross-version convergence" group pins the identity above. If it goes red,
the mitigation is broken and the sync hazard is live again.

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
  required bool skipped,              // skip vs done (2026-08-01, see below)
});
//   completion + done    → nextAfterCompletion(rule, closedOn)
//   completion + skipped → nextAfterCompletion(rule,
//                          max(closedDueDate, closedOn))
//   schedule (either)    → first series element STRICTLY AFTER
//                          max(closedDueDate, closedOn)
//                          (completing very late skips the missed slots — you
//                          don't get an instantly-overdue next occurrence;
//                          product decision)
```

`skip` and `done` differ for completion-anchored chores only (amended
2026-08-01 per field feedback B3, docs/feedback/2026-08-01-field-feedback.md):
completing anchors at the completion day ("3 days after the last time it
was done" — even when done early), while skipping a not-yet-due occurrence
anchors at that occurrence's own due date ("skip Friday's attempt → next
one is 3 days after Friday", not "3 days after the day I tapped skip").
For overdue/today skips `closedOn` is the max, so nothing changes there.

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
