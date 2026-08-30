/// The settings screen's 'Daily summary' rows, inside the Preferences group
/// (spec `docs/specs/theme-v2.md` §4.2): digest on/off toggle, time row, and
/// OS-permission hint (spec `docs/specs/notifications.md`).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/features/settings/settings_time_row.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Daily summary' on/off switch row.
class DigestToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const DigestToggleTile({
    required this.value,
    required this.onChanged,
    this.permissionDenied = false,
    super.key,
  });

  /// Whether the digest is currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  /// Whether the OS notification permission is currently denied (backlog
  /// B-5 / triage T2.6).
  ///
  /// When [value] is also true this grows a short factual sub-line, so the
  /// switch's ON position never implies a delivery that isn't happening.
  /// Presentation only: it never changes [value], because the stored
  /// `digestEnabled` remains the record of what the user WANTS (spec
  /// `docs/specs/notifications.md` — permission state must not write back
  /// to the stored flag, or granting the permission later would leave the
  /// digest silently off).
  final bool permissionDenied;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.digest.toggle',
      child: SettingsRow(
        icon: Icons.notifications_outlined,
        label: l10n.settingsDigestToggleTitle,
        sublabel: value && permissionDenied
            ? l10n.settingsDigestToggleDeniedHint
            : null,
        switchValue: value,
        onSwitchChanged: onChanged,
      ),
    );
  }
}

/// The digest fire-time row, opening a time picker on tap.
class DigestTimeTile extends StatelessWidget {
  /// Creates the time row.
  const DigestTimeTile({
    required this.minutesSinceMidnight,
    required this.onChanged,
    super.key,
  });

  /// The currently-chosen fire time, as minutes since local midnight.
  final int minutesSinceMidnight;

  /// Called with the newly-picked time, also as minutes since midnight.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTimeRow(
      // Load-bearing for E2E -- unchanged by this refactor.
      semanticId: 'settings.digest.time',
      icon: Icons.schedule_outlined,
      label: AppLocalizations.of(context).settingsDigestTimeLabel,
      minutesSinceMidnight: minutesSinceMidnight,
      onChanged: onChanged,
    );
  }
}

/// Inline hint shown when the digest is enabled but the OS notification
/// permission is denied (spec: "the OS state is the source of truth,
/// re-checked on app resume via the plugin's API").
class DigestPermissionHint extends StatelessWidget {
  /// Creates the hint row.
  const DigestPermissionHint({required this.onOpenSettings, super.key});

  /// Called when the hint's action button is tapped.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return semantic(
      'settings.digest.permission',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(
              Icons.notifications_off_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.settingsDigestPermissionHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: onOpenSettings,
              child: Text(l10n.settingsDigestPermissionAction),
            ),
          ],
        ),
      ),
    );
  }
}
