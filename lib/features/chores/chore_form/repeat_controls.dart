/// The chore form's full repeat-controls block.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/monthly_mode_row.dart';
import 'package:chore_app/features/chores/chore_form/repeat_section.dart';
import 'package:chore_app/features/chores/chore_form/weekday_chips.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        IntervalField(
          controller: intervalController,
          errorText: intervalError,
        ),
        const SizedBox(height: 8),
        UnitRow(value: unit, onChanged: onUnitChanged),
        const SizedBox(height: 8),
        AnchorRow(value: anchor, onChanged: onAnchorChanged),
        if (unit == RecurrenceUnit.week) ...[
          const SizedBox(height: 8),
          WeekdayChips(selected: weekdays, onToggle: onWeekdayToggle),
        ],
        if (unit == RecurrenceUnit.month &&
            anchor == RecurrenceAnchor.schedule) ...[
          const SizedBox(height: 8),
          MonthlyModeRow(
            value: monthlyMode,
            startDate: startDate,
            onChanged: onMonthlyModeChanged,
          ),
        ],
      ],
    );
  }
}
