/// The chore form's repeat toggle and recurrence-anchor cards.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/features/chores/chore_form/repeat_radio_card.dart';
import 'package:chore_app/features/chores/recurrence_sentence.dart';
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

/// The schedule/completion anchor choice, rendered as explanatory radio
/// cards under the 'Counting from' header (spec `docs/specs/theme-v2.md`
/// §4.4).
///
/// Both subtitles name the actual configured rule instead of a generic
/// example (field feedback G3 stage 1), via the app's single recurrence
/// formatter: the after-last-completion subtitle reads e.g. '3 days after
/// last done'; the fixed-schedule subtitle reads e.g. 'Every Saturday' or
/// 'Every month on the 20th'.
///
/// [showCompletion] is false in exactly one state (G-2 OPD-2): a month unit
/// in nth-weekday mode, where an anchor relative to a completion date has
/// nothing to count from and `Recurrence.validated` throws on the pair.
/// The card is **absent** rather than disabled -- the same "does not apply,
/// does not exist" rule the weekday chips follow -- and the caller shows a
/// line saying why in its place.
class AnchorRow extends StatelessWidget {
  /// Creates the anchor row.
  const AnchorRow({
    required this.value,
    required this.interval,
    required this.unit,
    required this.weekdays,
    required this.monthlyMode,
    required this.monthlyDayOfMonth,
    required this.monthlyOrdinal,
    required this.monthlyWeekday,
    required this.startDate,
    required this.onChanged,
    this.showCompletion = true,
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

  /// The currently-selected day of the month (month unit, day-of-month mode
  /// only), 1..31 or `-1` for the last day.
  final int monthlyDayOfMonth;

  /// The currently-selected monthly ordinal (nth-weekday mode only), 1..4
  /// or `-1` for last.
  final int monthlyOrdinal;

  /// The currently-selected monthly ISO weekday (nth-weekday mode only).
  final int monthlyWeekday;

  /// The chore's start date. Only a fallback now -- the form passes every
  /// part of the pattern explicitly -- but the formatter still needs it for
  /// already-persisted rules whose fields are null.
  final PlainDate startDate;

  /// Called when a different anchor is picked.
  final ValueChanged<RecurrenceAnchor> onChanged;

  /// Whether the after-last-completion card is offered at all (see the
  /// class doc).
  final bool showCompletion;

  @override
  Widget build(BuildContext context) {
    final anchors = showCompletion
        ? RecurrenceAnchor.values
        : const [RecurrenceAnchor.schedule];
    return Column(
      children: [
        for (final anchor in anchors)
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
    // One formatter for every piece of recurrence prose in the app -- see
    // `recurrenceSentence`'s doc comment for why a second one is a
    // regression. Note this is the CARD's own anchor, not [value]: both
    // cards render their own reading so the user can compare them.
    return recurrenceSentence(
      AppLocalizations.of(context),
      Localizations.localeOf(context).toString(),
      interval: interval,
      unit: unit,
      anchor: anchor,
      weekdays: weekdays,
      monthlyMode: monthlyMode,
      startDate: startDate,
      monthlyDayOfMonth: monthlyDayOfMonth,
      monthlyOrdinal: monthlyOrdinal,
      monthlyWeekday: monthlyWeekday,
    );
  }
}
