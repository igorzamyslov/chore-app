/// The chore form's per-chore reminder row (spec
/// `docs/specs/notifications-n2.md` §2.1).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A switch that, when on, reveals a time card and a one-line explanation
/// of Rule D.
///
/// [minutes] is the chore's `reminder_minutes` — minutes since local
/// midnight, or `null` for no individual reminder. Opt-in and time are
/// **one** nullable fact (decision D1), so there is no state in which this
/// row holds a time it is not using: turning the switch off reports `null`,
/// and turning it on reports the [defaultReminderMinutes] constant. The
/// pre-fill is that constant and not a settings column, because a default
/// is not state (§2.1).
///
/// The visual shape follows the form's two existing families rather than
/// inventing a third: the switch is a zero-inset `SwitchListTile` like
/// `RepeatToggle`, and the time card copies `StartDateField`'s labelled
/// card — a `surfaceContainerLow` fill, radius 14, a permanently-visible
/// uppercase micro-label above the value, a trailing glyph.
///
/// The picker opens in [TimePickerEntryMode.input] for the same two reasons
/// `DigestTimeTile` does: a time can be typed directly, and the dial's
/// freeform gestures are not deterministically driveable from a test.
///
/// Says nothing about *guaranteed* delivery, deliberately: §2.6 makes these
/// one-shot notifications rewritten whenever the app runs, and Android
/// scheduling stays `inexactAllowWhileIdle`. The UI must not promise
/// alarm-like behaviour it cannot deliver.
class ChoreFormReminderRow extends StatelessWidget {
  /// Creates the reminder row.
  const ChoreFormReminderRow({
    required this.minutes,
    required this.onChanged,
    super.key,
  });

  /// The chore's reminder time as minutes since local midnight, or `null`
  /// when the chore has no individual reminder.
  final int? minutes;

  /// Called with the new value: `null` to turn the reminder off, otherwise
  /// minutes since local midnight.
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = minutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        semantic(
          'chore_form.reminder.toggle',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.choreFormReminderToggle),
            value: current != null,
            onChanged: (enabled) =>
                onChanged(enabled ? defaultReminderMinutes : null),
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 8),
          semantic(
            'chore_form.reminder.time',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _pick(context, current),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Uppercase is typography, not content: the
                            // natural-case label stays as the
                            // accessibility label so TalkBack does not
                            // shout it, and so the translator sees a
                            // natural-case source (German capitalization
                            // rules differ). Same pattern as
                            // `LabelledFieldCard` and `StartDateField`.
                            Semantics(
                              label: l10n.choreFormReminderTime,
                              child: ExcludeSemantics(
                                child: Text(
                                  l10n.choreFormReminderTime.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _timeOf(current).format(context),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.schedule_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.choreFormReminderHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  TimeOfDay _timeOf(int value) =>
      TimeOfDay(hour: value ~/ 60, minute: value % 60);

  Future<void> _pick(BuildContext context, int current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOf(current),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      onChanged(picked.hour * 60 + picked.minute);
    }
  }
}
