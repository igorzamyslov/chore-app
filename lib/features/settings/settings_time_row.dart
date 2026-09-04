/// The settings screen's reusable "pick a time" row.
///
/// Extracted so the four time rows the Preferences group now holds -- the
/// digest time, the evening re-reminder time, and the two ends of the
/// quiet-hours window (spec `docs/specs/notifications-n2.md` §12) -- share
/// one picker call rather than four copies of it.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:flutter/material.dart';

/// A [SettingsRow] whose trailing value is a wall-clock time, opening a
/// time picker on tap.
///
/// The time is rendered with `TimeOfDay.format(context)`, so 12h/24h and
/// the separator follow the viewer's locale and
/// `MediaQuery.alwaysUse24HourFormat` -- never a hand-composed string. This
/// is also why the quiet-hours window is two rows rather than one "22:00 -
/// 07:00" label: a composed range would need a locale-sensitive string
/// nobody can format correctly, and two rows need none.
class SettingsTimeRow extends StatelessWidget {
  /// Creates a time row identified by [semanticId].
  const SettingsTimeRow({
    required this.semanticId,
    required this.icon,
    required this.label,
    required this.minutesSinceMidnight,
    required this.onChanged,
    this.sublabel,
    super.key,
  });

  /// The stable identifier this row is wrapped with, for E2E and widget
  /// selectors (see `lib/app/semantics.dart`).
  final String semanticId;

  /// The row's leading glyph.
  final IconData icon;

  /// The row's title.
  final String label;

  /// An optional factual sub-line under [label].
  final String? sublabel;

  /// The currently-chosen time, as minutes since local midnight (0..1439).
  final int minutesSinceMidnight;

  /// Called with the newly-picked time, also as minutes since midnight.
  /// Not called when the picker is dismissed.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return semantic(
      semanticId,
      child: SettingsRow(
        icon: icon,
        label: label,
        sublabel: sublabel,
        value: _timeOfDay.format(context),
        onTap: () => _pick(context),
      ),
    );
  }

  TimeOfDay get _timeOfDay => TimeOfDay(
    hour: minutesSinceMidnight ~/ 60,
    minute: minutesSinceMidnight % 60,
  );

  Future<void> _pick(BuildContext context) async {
    // Input mode (rather than the default dial) so the picker is reachable
    // by typing a time directly -- also what makes this deterministically
    // driveable from a widget test, unlike the dial's freeform gestures.
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      onChanged(picked.hour * 60 + picked.minute);
    }
  }
}
