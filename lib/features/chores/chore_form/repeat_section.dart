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
class UnitRow extends StatelessWidget {
  /// Creates the unit row.
  const UnitRow({required this.value, required this.onChanged, super.key});

  /// The currently-selected unit.
  final RecurrenceUnit value;

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
        return l10n.choreFormUnitDay;
      case RecurrenceUnit.week:
        return l10n.choreFormUnitWeek;
      case RecurrenceUnit.month:
        return l10n.choreFormUnitMonth;
    }
  }
}

/// The schedule/completion anchor choice, each with a subtitle hint.
class AnchorRow extends StatelessWidget {
  /// Creates the anchor row.
  const AnchorRow({required this.value, required this.onChanged, super.key});

  /// The currently-selected anchor.
  final RecurrenceAnchor value;

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
    return anchor == RecurrenceAnchor.schedule
        ? l10n.choreFormAnchorScheduleSubtitle
        : l10n.choreFormAnchorCompletionSubtitle;
  }
}
