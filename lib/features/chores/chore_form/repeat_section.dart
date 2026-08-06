/// The chore form's repeat toggle, interval, unit, and anchor controls.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/labelled_field_card.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/features/chores/chore_form/repeat_radio_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The repeat on/off switch.
class RepeatToggle extends StatelessWidget {
  /// Creates the repeat toggle.
  const RepeatToggle({required this.value, required this.onChanged, super.key});

  /// Whether the chore currently repeats.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return semantic(
      'chore_form.repeat.toggle',
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(AppLocalizations.of(context).choreFormRepeatToggleLabel),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// The repeat interval text field, with an inline validation error.
class IntervalField extends StatelessWidget {
  /// Creates the interval field.
  const IntervalField({required this.controller, this.errorText, super.key});

  /// Backs the raw interval text the user typed.
  final TextEditingController controller;

  /// Inline validation error, or `null` if valid (or not yet submitted).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return semantic(
      'chore_form.repeat.interval',
      child: LabelledFieldCard(
        label: AppLocalizations.of(context).choreFormRepeatEveryLabel,
        controller: controller,
        errorText: errorText,
        keyboardType: TextInputType.number,
      ),
    );
  }
}

/// The day/week/month unit segmented control (spec `docs/specs/theme-v2.md`
/// §4.4 item 2): a `surfaceContainerHigh` track, selected segment =
/// `surfaceContainerLow` fill + `primary` ink (both from the app-wide
/// `SegmentedButtonThemeData`, `lib/app/theme.dart`).
///
/// Labels are pluralized by [interval] (field feedback G3 stage 1,
/// `docs/feedback/2026-08-01-field-feedback.md`): this row sits directly
/// under the interval number field, and its label is the only place a unit
/// noun renders in the whole app, so "2 Month" read badly. There is no
/// separate combined-reading widget elsewhere to fix instead.
class UnitRow extends StatelessWidget {
  /// Creates the unit row.
  const UnitRow({
    required this.value,
    required this.interval,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected unit.
  final RecurrenceUnit value;

  /// The current repeat interval, used only to pick the right plural form
  /// of the unit noun (e.g. 'Day' vs 'Days'); it does not change which
  /// segment is selected.
  final int interval;

  /// Called when a different unit is picked.
  final ValueChanged<RecurrenceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RecurrenceUnit>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      segments: [
        for (final unit in RecurrenceUnit.values)
          ButtonSegment(
            value: unit,
            label: semantic(
              'chore_form.repeat.unit.${unit.name}',
              child: Text(_label(context, unit)),
            ),
          ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }

  String _label(BuildContext context, RecurrenceUnit unit) {
    final l10n = AppLocalizations.of(context);
    switch (unit) {
      case RecurrenceUnit.day:
        return l10n.choreFormUnitDayPlural(interval);
      case RecurrenceUnit.week:
        return l10n.choreFormUnitWeekPlural(interval);
      case RecurrenceUnit.month:
        return l10n.choreFormUnitMonthPlural(interval);
    }
  }
}

/// The schedule/completion anchor choice, rendered as two explanatory radio
/// cards (spec `docs/specs/theme-v2.md` §4.4 item 4).
///
/// Both subtitles name the actual configured interval instead of a generic
/// example (field feedback G3 stage 1): the after-last-completion subtitle
/// reads e.g. '3 days after last done'; the fixed-schedule subtitle reads
/// e.g. 'Every Saturday' or 'Every month on the 15th', computed from
/// [weekdays]/[monthlyMode]/[startDate] exactly like `MonthlyModeRow`'s own
/// chip labels are.
class AnchorRow extends StatelessWidget {
  /// Creates the anchor row.
  const AnchorRow({
    required this.value,
    required this.interval,
    required this.unit,
    required this.weekdays,
    required this.monthlyMode,
    required this.startDate,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected anchor.
  final RecurrenceAnchor value;

  /// The current repeat interval, used to make both subtitles concrete.
  final int interval;

  /// The current repeat unit, used to pick which concrete subtitle message
  /// (day/week/month) to render.
  final RecurrenceUnit unit;

  /// The currently-selected ISO weekdays (week unit only), used to name the
  /// fixed-schedule subtitle's actual weekday(s). Empty means "derive from
  /// [startDate]'s weekday", mirroring the engine's own rule.
  final Set<int> weekdays;

  /// The currently-selected monthly mode (month unit only), used to pick
  /// which fixed-schedule subtitle (day-of-month vs. nth/last weekday) to
  /// render.
  final MonthlyMode monthlyMode;

  /// The chore's start date, used to compute the fixed-schedule subtitle's
  /// concrete day/weekday, exactly like `MonthlyModeRow`'s labels are.
  final PlainDate startDate;

  /// Called when a different anchor is picked.
  final ValueChanged<RecurrenceAnchor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final anchor in RecurrenceAnchor.values)
          semantic(
            'chore_form.repeat.anchor.${anchor.name}',
            child: RepeatRadioCard(
              selected: value == anchor,
              title: _title(context, anchor),
              subtitle: _subtitle(context, anchor),
              onTap: () => onChanged(anchor),
            ),
          ),
      ],
    );
  }

  String _title(BuildContext context, RecurrenceAnchor anchor) {
    final l10n = AppLocalizations.of(context);
    return anchor == RecurrenceAnchor.schedule
        ? l10n.choreFormAnchorScheduleTitle
        : l10n.choreFormAnchorCompletionTitle;
  }

  String _subtitle(BuildContext context, RecurrenceAnchor anchor) {
    final l10n = AppLocalizations.of(context);
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
    return _scheduleSubtitle(context);
  }

  /// Names the actual configured fixed-schedule interval (spec
  /// `docs/specs/theme-v2.md` §4.4 item 4), replacing the old generic
  /// "e.g. every Tuesday" example.
  String _scheduleSubtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    switch (unit) {
      case RecurrenceUnit.day:
        return l10n.choreFormAnchorScheduleSubtitleDay(interval);
      case RecurrenceUnit.week:
        final effective = weekdays.isEmpty ? {startDate.weekday} : weekdays;
        final names = (effective.toList()..sort())
            .map((weekday) => weekdayName(weekday, localeName))
            .join(', ');
        return l10n.choreFormAnchorScheduleSubtitleWeek(interval, names);
      case RecurrenceUnit.month:
        if (monthlyMode == MonthlyMode.dayOfMonth) {
          final ordinalDay = localizedOrdinal(startDate.day, localeName);
          return l10n.choreFormAnchorScheduleSubtitleMonthDayOfMonth(
            interval,
            ordinalDay,
          );
        }
        final ordinal = nthWeekdayOrdinalOf(startDate);
        final weekday = weekdayName(startDate.weekday, localeName);
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
}
