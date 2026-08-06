/// The chore form's week-unit weekday multi-select row.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/chores/chore_form/recurrence_builder.dart';
import 'package:flutter/material.dart';

/// A multi-select row of Mon..Sun circular toggles (spec
/// `docs/specs/theme-v2.md` §4.4 item 3): selected = `primary` fill +
/// `onPrimary` ink; unselected = `surfaceContainerLow` fill +
/// `outlineVariant` border. Each toggle is a ≥48dp tap target holding a
/// visually-smaller 36dp circle.
///
/// Only shown when the chore's repeat unit is week. An empty selection is
/// allowed — it means "derive the weekday from the start date".
class WeekdayChips extends StatelessWidget {
  /// Creates the weekday toggle row, with [selected] holding ISO weekdays
  /// (1 = Monday .. 7 = Sunday).
  const WeekdayChips({
    required this.selected,
    required this.onToggle,
    super.key,
  });

  /// The currently-selected ISO weekdays.
  final Set<int> selected;

  /// Called with the ISO weekday whose toggle was tapped.
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final localeName = Localizations.localeOf(context).toString();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          semantic(
            'chore_form.repeat.weekday.$weekday',
            child: _WeekdayToggle(
              weekday: weekday,
              localeName: localeName,
              selected: selected.contains(weekday),
              onTap: () => onToggle(weekday),
            ),
          ),
      ],
    );
  }
}

/// A single circular weekday toggle inside a 48dp tap target.
class _WeekdayToggle extends StatelessWidget {
  const _WeekdayToggle({
    required this.weekday,
    required this.localeName,
    required this.selected,
    required this.onTap,
  });

  final int weekday;
  final String localeName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fillColor = selected
        ? colorScheme.primary
        : colorScheme.surfaceContainerLow;
    final inkColor = selected
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return Semantics(
      label: weekdayName(weekday, localeName),
      button: true,
      selected: selected,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fillColor,
                    border: selected
                        ? null
                        : Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Center(
                    child: Text(
                      weekdayNarrowName(weekday, localeName),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: inkColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
