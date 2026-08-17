/// The chore form's full repeat-controls block.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/monthly_mode_row.dart';
import 'package:chore_app/features/chores/chore_form/repeat_section.dart';
import 'package:chore_app/features/chores/chore_form/weekday_chips.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Composes the interval/unit/anchor controls with the weekday chips (week
/// unit only) and monthly mode choice (month unit + schedule anchor only).
///
/// Shown only while the form's repeat toggle is on.
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
    required this.startDate,
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

  /// The currently-selected ISO weekdays (week unit only).
  final Set<int> weekdays;

  /// Called with the ISO weekday whose chip was tapped.
  final ValueChanged<int> onWeekdayToggle;

  /// The currently-selected monthly mode (month unit + schedule anchor
  /// only).
  final MonthlyMode monthlyMode;

  /// Called when a different monthly mode is picked.
  final ValueChanged<MonthlyMode> onMonthlyModeChanged;

  /// The chore's start date, used to label the monthly mode chips.
  final PlainDate startDate;

  @override
  Widget build(BuildContext context) {
    // Best-effort parse for display only (pluralizing the unit label and
    // the after-last-completion subtitle); an invalid/empty field still
    // shows *something* sensible here, and `intervalError` is what
    // actually blocks save.
    final interval = int.tryParse(intervalController.text.trim()) ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        IntervalField(controller: intervalController, errorText: intervalError),
        const SizedBox(height: 8),
        UnitRow(value: unit, interval: interval, onChanged: onUnitChanged),
        const SizedBox(height: 8),
        AnchorRow(
          value: anchor,
          interval: interval,
          unit: unit,
          weekdays: weekdays,
          monthlyMode: monthlyMode,
          startDate: startDate,
          onChanged: onAnchorChanged,
        ),
        if (unit == RecurrenceUnit.week) ...[
          const SizedBox(height: 8),
          WeekdayChips(selected: weekdays, onToggle: onWeekdayToggle),
          // An empty selection derives the effective weekday from the
          // start date (see WeekdayChips' doc comment); once at least one
          // day is explicitly picked, the pattern no longer has a hidden
          // dependency on the start date, so the hint no longer applies.
          if (weekdays.isEmpty) ...[
            const SizedBox(height: 4),
            const _PatternFollowsStartDateHint(),
          ],
        ],
        if (unit == RecurrenceUnit.month &&
            anchor == RecurrenceAnchor.schedule) ...[
          const SizedBox(height: 8),
          MonthlyModeRow(
            value: monthlyMode,
            startDate: startDate,
            onChanged: onMonthlyModeChanged,
          ),
          const SizedBox(height: 4),
          const _PatternFollowsStartDateHint(),
        ],
      ],
    );
  }
}

/// A subtle one-line caption pointing at the start date as the lever that
/// actually controls the derived monthly day / weekly weekday (field
/// feedback G3 stage 1): both `MonthlyModeRow` and an empty `WeekdayChips`
/// selection silently compute their pattern from the chore's start date,
/// which is easy to miss since the start date field sits well below this
/// one in the form.
class _PatternFollowsStartDateHint extends StatelessWidget {
  const _PatternFollowsStartDateHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context).choreFormPatternFollowsStartDate,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
