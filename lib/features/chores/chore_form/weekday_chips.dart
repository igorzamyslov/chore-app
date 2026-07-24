/// The chore form's week-unit weekday multi-select chip row.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:flutter/material.dart';

/// A multi-select row of Mon..Sun chips.
///
/// Only shown when the chore's repeat unit is week. An empty selection is
/// allowed — it means "derive the weekday from the start date".
class WeekdayChips extends StatelessWidget {
  /// Creates the weekday chip row, with [selected] holding ISO weekdays
  /// (1 = Monday .. 7 = Sunday).
  const WeekdayChips({
    required this.selected,
    required this.onToggle,
    super.key,
  });

  /// The currently-selected ISO weekdays.
  final Set<int> selected;

  /// Called with the ISO weekday whose chip was tapped.
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          semantic(
            'chore_form.repeat.weekday.$weekday',
            child: FilterChip(
              label: Text(weekdayShortNames[weekday - 1]),
              selected: selected.contains(weekday),
              onSelected: (_) => onToggle(weekday),
            ),
          ),
      ],
    );
  }
}
