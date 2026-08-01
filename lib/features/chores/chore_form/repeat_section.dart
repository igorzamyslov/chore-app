/// The chore form's repeat toggle, interval, unit, and anchor controls.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
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
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).choreFormRepeatEveryLabel,
          errorText: errorText,
        ),
      ),
    );
  }
}

/// The day/week/month unit chip row.
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
  /// chip is selected.
  final int interval;

  /// Called when a different unit is picked.
  final ValueChanged<RecurrenceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final unit in RecurrenceUnit.values)
          semantic(
            'chore_form.repeat.unit.${unit.name}',
            child: ChoiceChip(
              label: Text(_label(context, unit)),
              selected: value == unit,
              onSelected: (_) => onChanged(unit),
            ),
          ),
      ],
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

/// The schedule/completion anchor choice, each with a subtitle hint.
///
/// The after-last-completion subtitle names the actual current [interval]
/// and [unit] (field feedback G3 stage 1) instead of a generic example, so
/// it reads as a concrete sentence, e.g. '3 days after last done'.
class AnchorRow extends StatelessWidget {
  /// Creates the anchor row.
  const AnchorRow({
    required this.value,
    required this.interval,
    required this.unit,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected anchor.
  final RecurrenceAnchor value;

  /// The current repeat interval, used to make the after-last-completion
  /// subtitle concrete.
  final int interval;

  /// The current repeat unit, used to pick which concrete subtitle message
  /// (day/week/month) to render.
  final RecurrenceUnit unit;

  /// Called when a different anchor is picked.
  final ValueChanged<RecurrenceAnchor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final anchor in RecurrenceAnchor.values)
          semantic(
            'chore_form.repeat.anchor.${anchor.name}',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                value == anchor
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(_title(context, anchor)),
              subtitle: Text(_subtitle(context, anchor)),
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
    if (anchor == RecurrenceAnchor.schedule) {
      return l10n.choreFormAnchorScheduleSubtitle;
    }
    switch (unit) {
      case RecurrenceUnit.day:
        return l10n.choreFormAnchorCompletionSubtitleDay(interval);
      case RecurrenceUnit.week:
        return l10n.choreFormAnchorCompletionSubtitleWeek(interval);
      case RecurrenceUnit.month:
        return l10n.choreFormAnchorCompletionSubtitleMonth(interval);
    }
  }
}
