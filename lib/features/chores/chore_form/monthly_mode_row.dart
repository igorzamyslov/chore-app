/// The chore form's month-unit monthly-mode choice.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:chore_app/features/chores/chore_form/repeat_radio_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The day-of-month vs. nth-weekday choice, labeled from [startDate].
///
/// Only shown for a month-unit, schedule-anchored recurrence.
class MonthlyModeRow extends StatelessWidget {
  /// Creates the monthly mode row.
  const MonthlyModeRow({
    required this.value,
    required this.startDate,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected monthly mode.
  final MonthlyMode value;

  /// The chore's start date, which the chip labels and the eventual
  /// nth-weekday recurrence are computed from.
  final PlainDate startDate;

  /// Called when a different monthly mode is picked.
  final ValueChanged<MonthlyMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final mode in MonthlyMode.values)
          semantic(
            'chore_form.repeat.monthly_mode.${monthlyModeId(mode)}',
            child: RepeatRadioCard(
              selected: value == mode,
              title: _label(context, mode),
              onTap: () => onChanged(mode),
            ),
          ),
      ],
    );
  }

  String _label(BuildContext context, MonthlyMode mode) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    if (mode == MonthlyMode.dayOfMonth) {
      return l10n.monthlyDayOfMonthLabel(
        localizedOrdinal(startDate.day, localeName),
      );
    }
    final ordinal = nthWeekdayOrdinalOf(startDate);
    final weekday = weekdayName(startDate.weekday, localeName);
    return ordinal == -1
        ? l10n.monthlyLastWeekdayLabel(weekday)
        : l10n.monthlyNthWeekdayLabel(
            localizedOrdinal(ordinal, localeName),
            weekday,
          );
  }
}
