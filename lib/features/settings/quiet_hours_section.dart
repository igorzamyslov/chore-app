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
import 'package:chore_app/features/settings/settings_time_row.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Quiet hours' on/off switch row.
class QuietHoursToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const QuietHoursToggleTile({
    required this.value,
    required this.onChanged,
    this.emptyWindow = false,
    super.key,
  });

  /// Whether quiet hours are currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  /// Whether the stored window has zero length (`start == end`), which
  /// spec `docs/specs/notifications-n2.md` §6 treats as OFF rather than as
  /// a 24-hour window.
  ///
  /// When [value] is also true this grows a short factual sub-line, so the
  /// switch's ON position never implies a deferral that isn't happening --
  /// the same reason `DigestToggleTile.permissionDenied` exists (backlog
  /// B-5). Presentation only: it never rewrites either stored time, because
  /// the times remain the record of what the user set.
  ///
  /// A pure projection of the two settings, computed by the caller: always
  /// current, self-clearing the instant either time moves, nothing stored
  /// and nothing to dismiss.
  final bool emptyWindow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.quietHours.toggle',
      child: SettingsRow(
        icon: Icons.bedtime_outlined,
        label: l10n.settingsQuietHoursToggle,
        sublabel: emptyWindow ? l10n.settingsQuietHoursEmptyWindowHint : null,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}

/// The quiet-hours window's START row, revealed while the switch is on.
class QuietHoursStartTile extends StatelessWidget {
  /// Creates the start-time row.
  const QuietHoursStartTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    super.key,
  });

  /// The window's start, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked start, also as minutes since midnight.
  ///
  /// The caller is responsible for writing the window's OTHER end
  /// unchanged alongside it: `SettingsRepository` exposes one
  /// `setQuietHours` rather than two setters, because the window is one
  /// fact and a half-updated one is readable by the debounced recompute.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTimeRow(
      semanticId: 'settings.quietHours.start',
      icon: Icons.schedule_outlined,
      label: AppLocalizations.of(context).settingsQuietHoursFrom,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}

/// The quiet-hours window's END row, revealed while the switch is on.
///
/// The window wraps midnight in the normal case (22:00 to 07:00), so this
/// value is routinely SMALLER than the start's; nothing here validates an
/// ordering, deliberately -- `isWithinQuietHours` treats the pair as a
/// wrapping interval (spec `docs/specs/notifications-n2.md` §6).
class QuietHoursEndTile extends StatelessWidget {
  /// Creates the end-time row.
  const QuietHoursEndTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    super.key,
  });

  /// The window's end, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked end, also as minutes since midnight. See
  /// [QuietHoursStartTile.onChanged] for why the caller must pass the
  /// window's other end through unchanged.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTimeRow(
      semanticId: 'settings.quietHours.end',
      icon: Icons.schedule_outlined,
      label: AppLocalizations.of(context).settingsQuietHoursTo,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}
