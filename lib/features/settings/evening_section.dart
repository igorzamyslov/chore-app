/// The settings screen's evening re-reminder rows, inside the Preferences
/// group directly beneath the digest time row (spec
/// `docs/specs/notifications-n2.md` §5, §5.1 and §12).
///
/// **Ships OFF (decision D12)**, and its discoverability is paid for by
/// PLACEMENT and WORDING and by nothing else: the row sits in the one group
/// that already holds the notification the user knows about, and its label
/// names their problem ("it arrives, then it's gone") rather than our
/// mechanism. B-5 settled that a returning nudge IS the nagging, so there
/// must never be a prompt, a banner or a first-run hint pointing at this
/// row -- if it cannot be found where it is with the label it has, the fix
/// is the label.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/features/settings/settings_time_row.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Remind me again in the evening' on/off switch row.
class EveningToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const EveningToggleTile({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Whether the evening re-reminder is currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.evening.toggle',
      child: SettingsRow(
        icon: Icons.notifications_active_outlined,
        label: l10n.settingsEveningToggle,
        // Unconditional, unlike the digest toggle's permission sub-line:
        // this states what the feature DOES, and a user scanning the group
        // for a vanished notification has to be able to read it before
        // deciding to turn the switch on.
        sublabel: l10n.settingsEveningToggleSubtitle,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}

/// The evening re-reminder's fire-time row, revealed while
/// [EveningToggleTile] is on.
class EveningTimeTile extends StatelessWidget {
  /// Creates the time row.
  const EveningTimeTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    this.insideQuietHours = false,
    super.key,
  });

  /// The currently-chosen evening time, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked time, also as minutes since midnight.
  final ValueChanged<int> onChanged;

  /// Whether [minutesSinceMidnight] falls inside the user's quiet-hours
  /// window (spec `docs/specs/notifications-n2.md` §6).
  ///
  /// When true this grows a factual sub-line, because an evening
  /// re-reminder inside the window is DROPPED rather than deferred
  /// (decision D7): deferring it to 07:00 would deliver a notification
  /// whose entire premise -- "these are still open and there is still time
  /// today" -- is false by then, minutes before the digest says the same
  /// thing correctly. Without the sub-line the feature would silently do
  /// nothing.
  ///
  /// Computed by the caller as a pure projection of the two settings (see
  /// `isWithinQuietHours`), never stored: it is always current, it
  /// self-clears the instant either time moves, and there is nothing to
  /// dismiss. Same pattern as `DigestToggleTile.permissionDenied`.
  final bool insideQuietHours;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTimeRow(
      semanticId: 'settings.evening.time',
      icon: Icons.schedule_outlined,
      label: l10n.settingsEveningTime,
      sublabel: insideQuietHours ? l10n.settingsEveningInQuietHoursHint : null,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}
