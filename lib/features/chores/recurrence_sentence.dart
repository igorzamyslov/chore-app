/// The app's single formatter for recurrence prose.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/recurrence/recurrence_engine.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

/// Renders a recurrence rule as one localized clause, e.g. `'Every 2 weeks
/// on Tuesday, Friday'` or `'3 days after last done'`.
///
/// **This is the only place in the app that turns a recurrence into prose,
/// and it must stay that way** (G-2,
/// `docs/plans/2026-08-18-repeat-form-sentence.md` Analysis §1). Its callers
/// are `AnchorRow`'s two radio-card subtitles, [recurrencePreview] below,
/// and the paused rows in `chore_paused_section.dart`. Before G-2 the same
/// switch over unit/anchor/monthlyMode was written out privately inside
/// `AnchorRow`, and the preview line was about to become a second copy of
/// it — two switches over the same enums, rendering the same rule in two
/// wordings, guaranteed to diverge on the first copy change. A second
/// recurrence formatter anywhere in `lib/` is a regression, not a
/// convenience.
///
/// This file deliberately lives in `lib/features/chores/`, not in
/// `chore_form/`, so `chore_paused_section.dart` can import it without
/// reaching into a form-private directory. It cannot live in `lib/domain/`,
/// which is `dart:core`-only and so can use neither `package:intl` nor
/// [AppLocalizations].
///
/// Every argument is passed loose rather than as a [Recurrence] because the
/// chore form holds these values as separate pieces of `State` while the
/// user is editing, and there is no valid rule to build until they stop.
/// [localeName] is the `Localizations.localeOf(context).toString()` the
/// caller already has; it drives `package:intl`'s weekday names and the
/// ordinal suffix, never a hardcoded list.
///
/// [startDate] is only read as a fallback, for rules that predate the
/// directly-editable pattern: a week rule with an empty [weekdays] derives
/// its weekday from it (mirroring the engine's own `_effectiveWeekdays`),
/// and a month rule with a null [monthlyDayOfMonth] /
/// [monthlyOrdinal] / [monthlyWeekday] derives those from it, exactly as
/// the engine does. Rules the form writes after G-2 always carry them
/// explicitly, so the fallback only ever runs for already-persisted rows.
///
/// [monthlyDayOfMonth] renders as an already-localized ordinal ('20th',
/// '20.'), or as `choreFormDayOfMonthLast` for the `-1` sentinel, which has
/// no numeral form. [monthlyOrdinal] renders the same way, `-1` reaching
/// the dedicated last-weekday message. Ordinals are rendered as numerals
/// ('3rd Tuesday', not 'third Tuesday') because that is what the rest of
/// the app already says and because German's weak adjective endings would
/// otherwise have to be baked into hand-written strings; see
/// [localizedOrdinal].
String recurrenceSentence(
  AppLocalizations l10n,
  String localeName, {
  required int interval,
  required RecurrenceUnit unit,
  required RecurrenceAnchor anchor,
  required Set<int> weekdays,
  required MonthlyMode monthlyMode,
  required PlainDate startDate,
  int? monthlyDayOfMonth,
  int? monthlyOrdinal,
  int? monthlyWeekday,
}) {
  if (anchor == RecurrenceAnchor.completion) {
    switch (unit) {
      case RecurrenceUnit.day:
        return l10n.choreFormAnchorCompletionSubtitleDay(interval);
      case RecurrenceUnit.week:
        return l10n.choreFormAnchorCompletionSubtitleWeek(interval);
      case RecurrenceUnit.month:
        return l10n.choreFormAnchorCompletionSubtitleMonth(interval);
    }
  }
  switch (unit) {
    case RecurrenceUnit.day:
      return l10n.choreFormAnchorScheduleSubtitleDay(interval);
    case RecurrenceUnit.week:
      return l10n.choreFormAnchorScheduleSubtitleWeek(
        interval,
        weekdayNames(weekdays, localeName, startDate: startDate),
      );
    case RecurrenceUnit.month:
      if (monthlyMode == MonthlyMode.dayOfMonth) {
        final day = monthlyDayOfMonth ?? startDate.day;
        return l10n.choreFormAnchorScheduleSubtitleMonthDayOfMonth(
          interval,
          day == -1
              ? l10n.choreFormDayOfMonthLast
              : localizedOrdinal(day, localeName),
        );
      }
      final ordinal = monthlyOrdinal ?? nthWeekdayOrdinalOf(startDate);
      final weekday = weekdayName(
        monthlyWeekday ?? startDate.weekday,
        localeName,
      );
      return ordinal == -1
          ? l10n.choreFormAnchorScheduleSubtitleMonthLastWeekday(
              interval,
              weekday,
            )
          : l10n.choreFormAnchorScheduleSubtitleMonthNthWeekday(
              interval,
              localizedOrdinal(ordinal, localeName),
              weekday,
            );
  }
}

/// The comma-joined, locale-formatted names of [weekdays] in ascending ISO
/// order, e.g. `'Tuesday, Friday'`.
///
/// An empty [weekdays] falls back to [startDate]'s own weekday, which is
/// exactly the engine's `_effectiveWeekdays` rule — so the prose and the
/// computed due dates can never disagree about which day an
/// empty-set rule means.
String weekdayNames(
  Set<int> weekdays,
  String localeName, {
  required PlainDate startDate,
}) {
  final effective = weekdays.isEmpty ? {startDate.weekday} : weekdays;
  return (effective.toList()..sort())
      .map((weekday) => weekdayName(weekday, localeName))
      .join(', ');
}

/// The chore form's always-visible preview line: the same clause
/// [recurrenceSentence] renders, followed by what it actually means in real
/// dates.
///
/// For a [RecurrenceAnchor.schedule] rule that is the **next three due
/// dates** on or after [today], formatted with `DateFormat.MMMEd` — the same
/// `package:intl` formatter `futureDueText` uses for absolute dates on the
/// chore tiles, deliberately not a second date format.
///
/// Three dates, not one, because the sentence alone is ambiguous and the
/// dates are not: "every 2 weeks on Tuesday and Friday" means the week
/// repeats every two weeks and the chore is due on *each* picked day inside
/// an active week — two chores a fortnight, not one alternating. Nothing in
/// the prose distinguishes those readings. The preview also shows the
/// month-length clamp happening (a 31st-of-the-month rule simply lands on
/// Feb 28) rather than explaining it in words.
///
/// For a [RecurrenceAnchor.completion] rule there are no real dates to name
/// — the series depends on when the user ticks it — so the preview is prose:
/// a week rule with more than one picked weekday explains the roll-forward
/// to the next matching day, and every other case says the next due date
/// depends on the day it is done.
String recurrencePreview(
  AppLocalizations l10n,
  String localeName, {
  required int interval,
  required RecurrenceUnit unit,
  required RecurrenceAnchor anchor,
  required Set<int> weekdays,
  required MonthlyMode monthlyMode,
  required PlainDate startDate,
  required PlainDate today,
  int? monthlyDayOfMonth,
  int? monthlyOrdinal,
  int? monthlyWeekday,
}) {
  final base = recurrenceSentence(
    l10n,
    localeName,
    interval: interval,
    unit: unit,
    anchor: anchor,
    weekdays: weekdays,
    monthlyMode: monthlyMode,
    startDate: startDate,
    monthlyDayOfMonth: monthlyDayOfMonth,
    monthlyOrdinal: monthlyOrdinal,
    monthlyWeekday: monthlyWeekday,
  );

  if (anchor == RecurrenceAnchor.completion) {
    // Mirrors `nextAfterCompletion`'s week branch: with a single pinned
    // weekday the roll-forward is a no-op, so promising one would be
    // misleading -- the generic wording is the honest one there.
    if (unit == RecurrenceUnit.week && weekdays.length > 1) {
      return l10n.choreFormPreviewCompletionRolledForward(
        base,
        weekdayNames(weekdays, localeName, startDate: startDate),
      );
    }
    return l10n.choreFormPreviewCompletionDependsOnDay(base);
  }

  // The permissive const constructor, not `validated`: this runs on every
  // rebuild while the user is mid-edit, when the loose field values may not
  // yet form a rule anyone would persist. The engine reads only the fields
  // relevant to `unit`/`monthlyMode`, and the nth-weekday branch dereferences
  // its two fields, so both are resolved here rather than passed through
  // null.
  final rule = Recurrence(
    interval: interval,
    unit: unit,
    anchor: anchor,
    weekdays: weekdays,
    monthlyMode: monthlyMode,
    monthlyOrdinal: monthlyOrdinal ?? nthWeekdayOrdinalOf(startDate),
    monthlyWeekday: monthlyWeekday ?? startDate.weekday,
    monthlyDayOfMonth: monthlyDayOfMonth,
  );

  // `nextScheduledOnOrAfter` rather than
  // `scheduleOccurrences(...).where(...).take(3)`: both are correct, but the
  // filter walks every occurrence since `startDate`, which for an edited
  // chore that began years ago is thousands of allocations on every form
  // rebuild. This is the engine's own bounded idiom (see
  // `latestScheduledOnOrBefore`), and it handles `today` at or before
  // `startDate` by returning the series' first element.
  final first = nextScheduledOnOrAfter(rule, startDate, today);
  final second = nextScheduledOnOrAfter(rule, startDate, first.addDays(1));
  final third = nextScheduledOnOrAfter(rule, startDate, second.addDays(1));

  final format = DateFormat.MMMEd(localeName);
  String render(PlainDate date) =>
      format.format(DateTime.utc(date.year, date.month, date.day));

  return l10n.choreFormPreviewNextThree(
    base,
    render(first),
    render(second),
    render(third),
  );
}
