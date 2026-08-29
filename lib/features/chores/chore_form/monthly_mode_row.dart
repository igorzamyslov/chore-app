/// The chore form's month-unit monthly-mode choice.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/features/chores/chore_form/repeat_radio_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The day-of-month vs. nth-weekday choice.
///
/// Only shown for a month-unit, schedule-anchored recurrence:
/// `nextAfterCompletion`'s month branch is
/// `completedOn.addMonths(interval)` and reads no monthly field at all, so
/// under a completion anchor this row would change nothing.
///
/// Since G-2 the two options name the **mode** ("A day of the month" / "A
/// weekday") rather than the concrete day derived from the start date ("On
/// the 15th" / "On the 3rd Tuesday"). The concrete day now lives in the
/// repeat sentence's own chip, and naming it here as well would be two
/// places to keep in step.
class MonthlyModeRow extends StatelessWidget {
  /// Creates the monthly mode row.
  const MonthlyModeRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected monthly mode.
  final MonthlyMode value;

  /// Called when a different monthly mode is picked.
  final ValueChanged<MonthlyMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final mode in MonthlyMode.values)
          semantic(
            'chore_form.repeat.monthly_mode.${monthlyModeId(mode)}',
            child: RepeatRadioCard(
              selected: value == mode,
              title: mode == MonthlyMode.dayOfMonth
                  ? l10n.choreFormMonthlyModeDayOfMonth
                  : l10n.choreFormMonthlyModeWeekday,
              onTap: () => onChanged(mode),
            ),
          ),
      ],
    );
  }
}
