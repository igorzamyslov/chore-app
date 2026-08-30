/// The settings screen's quiet-hours rows, inside the Preferences group
/// (spec `docs/specs/notifications-n2.md` §6 and §12): an on/off switch and,
/// while it is on, the window's start and end time rows.
///
/// Quiet hours DEFER, never drop, for the digest and for per-chore
/// reminders (decision D7) -- the evening re-reminder is the one exception,
/// and its collision with this window is surfaced on the evening time row
/// (`evening_section.dart`), not here.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Quiet hours' on/off switch row.
class QuietHoursToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const QuietHoursToggleTile({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Whether quiet hours are currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.quietHours.toggle',
      child: SettingsRow(
        icon: Icons.bedtime_outlined,
        label: l10n.settingsQuietHoursToggle,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}
