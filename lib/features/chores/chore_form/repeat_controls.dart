/// The chore form's full repeat-controls block.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/monthly_mode_row.dart';
import 'package:chore_app/features/chores/chore_form/repeat_section.dart';
import 'package:chore_app/features/chores/chore_form/repeat_sentence.dart';
import 'package:chore_app/features/chores/chore_form/weekday_chips.dart';
import 'package:chore_app/features/chores/recurrence_sentence.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The whole repeat block: one fill-in-the-blank sentence, the pattern
/// pickers that belong to the chosen unit, the anchor under a 'Counting
/// from' header, and an always-visible preview naming real dates.
///
/// Shown only while the form's repeat toggle is on.
///
/// The organising rule (G-2,
/// `docs/plans/2026-08-18-repeat-form-sentence.md`) is that **a control
/// that does not apply does not exist** — it is never merely disabled.
/// Weekday chips exist for a week unit; the monthly-mode row exists for a
/// month unit with a schedule anchor, since `nextAfterCompletion`'s month
/// branch reads no monthly field at all; and the after-last-completion
/// anchor card does not exist in monthly weekday mode, where there is
/// nothing for a completion date to count from (OPD-2).
class RepeatControls extends StatelessWidget {
  /// Creates the repeat controls block.
  const RepeatControls({
    required this.intervalController,
    required this.intervalError,
    required this.unit,
    required this.onUnitChanged,
    required this.anchor,
    required this.onAnchorChanged,
    required this.weekdays,
    required this.onWeekdayToggle,
    required this.monthlyMode,
    required this.onMonthlyModeChanged,
    required this.monthlyDayOfMonth,
    required this.onMonthlyDayOfMonthChanged,
    required this.monthlyOrdinal,
    required this.onMonthlyOrdinalChanged,
    required this.monthlyWeekday,
    required this.onMonthlyWeekdayChanged,
    required this.startDate,
    required this.today,
    super.key,
  });

  /// Backs the raw interval text the user typed.
  final TextEditingController intervalController;

  /// Inline validation error for the interval field.
  final String? intervalError;

  /// The currently-selected unit.
  final RecurrenceUnit unit;

  /// Called when a different unit is picked.
  final ValueChanged<RecurrenceUnit> onUnitChanged;

  /// The currently-selected anchor.
  final RecurrenceAnchor anchor;

  /// Called when a different anchor is picked.
  final ValueChanged<RecurrenceAnchor> onAnchorChanged;

  /// The currently-selected ISO weekdays (week unit only), never empty.
  final Set<int> weekdays;

  /// Called with the ISO weekday whose chip was tapped.
  final ValueChanged<int> onWeekdayToggle;

  /// The currently-selected monthly mode (month unit + schedule anchor
  /// only).
  final MonthlyMode monthlyMode;

  /// Called when a different monthly mode is picked.
  final ValueChanged<MonthlyMode> onMonthlyModeChanged;

  /// The currently-selected day of the month, 1..31 or `-1` for the last
  /// day.
  final int monthlyDayOfMonth;

  /// Called with the newly-picked day of the month.
  final ValueChanged<int> onMonthlyDayOfMonthChanged;

  /// The currently-selected monthly ordinal, 1..4 or `-1` for last.
  final int monthlyOrdinal;

  /// Called with the newly-picked monthly ordinal.
  final ValueChanged<int> onMonthlyOrdinalChanged;

  /// The currently-selected monthly ISO weekday, 1..7.
  final int monthlyWeekday;

  /// Called with the newly-picked monthly ISO weekday.
  final ValueChanged<int> onMonthlyWeekdayChanged;

  /// The chore's start date, which the preview's real dates count from.
  final PlainDate startDate;

  /// Today, so the preview names the next three dates from now rather than
  /// replaying a series that began in the past.
  final PlainDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localeName = Localizations.localeOf(context).toString();
    // Best-effort parse for display only; `intervalError` is what actually
    // blocks save, and an empty field still has to render a sensible
    // preview rather than the line disappearing under the user.
    final interval = int.tryParse(intervalController.text.trim()) ?? 1;
    final isMonthlyPattern =
        unit == RecurrenceUnit.month && anchor == RecurrenceAnchor.schedule;
    final isWeekdayPattern =
        isMonthlyPattern && monthlyMode == MonthlyMode.nthWeekday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        RepeatSentence(
          intervalController: intervalController,
          intervalError: intervalError,
          unit: unit,
          onUnitChanged: onUnitChanged,
          anchor: anchor,
          monthlyMode: monthlyMode,
          monthlyDayOfMonth: monthlyDayOfMonth,
          onMonthlyDayOfMonthChanged: onMonthlyDayOfMonthChanged,
          monthlyOrdinal: monthlyOrdinal,
          onMonthlyOrdinalChanged: onMonthlyOrdinalChanged,
          monthlyWeekday: monthlyWeekday,
          onMonthlyWeekdayChanged: onMonthlyWeekdayChanged,
        ),
        if (unit == RecurrenceUnit.week) ...[
          const SizedBox(height: 8),
          WeekdayChips(selected: weekdays, onToggle: onWeekdayToggle),
        ],
        if (isMonthlyPattern) ...[
          const SizedBox(height: 8),
          MonthlyModeRow(value: monthlyMode, onChanged: onMonthlyModeChanged),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
        const SizedBox(height: 12),
        Text(
          l10n.choreFormCountingFromLabel.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        AnchorRow(
          value: anchor,
          interval: interval,
          unit: unit,
          weekdays: weekdays,
          monthlyMode: monthlyMode,
          monthlyDayOfMonth: monthlyDayOfMonth,
          monthlyOrdinal: monthlyOrdinal,
          monthlyWeekday: monthlyWeekday,
          startDate: startDate,
          onChanged: onAnchorChanged,
          showCompletion: !isWeekdayPattern,
        ),
        // OPD-2: rather than offering the completion anchor and silently
        // reverting it, the card is absent and this line says why — in the
        // section whose contents changed, on the same frame they changed.
        // No snackbar, no dialog.
        if (isWeekdayPattern)
          Text(
            l10n.choreFormCountingFromWeekdayOnly,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        semantic(
          'chore_form.repeat.preview',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_upcoming, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recurrencePreview(
                    l10n,
                    localeName,
                    interval: interval,
                    unit: unit,
                    anchor: anchor,
                    weekdays: weekdays,
                    monthlyMode: monthlyMode,
                    startDate: startDate,
                    today: today,
                    monthlyDayOfMonth: monthlyDayOfMonth,
                    monthlyOrdinal: monthlyOrdinal,
                    monthlyWeekday: monthlyWeekday,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
