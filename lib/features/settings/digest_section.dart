/// The settings screen's 'Daily summary' section: digest on/off toggle,
/// time row, and OS-permission hint (spec `docs/specs/notifications.md`).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Section header above the digest rows, matching the design-language
/// spec's section-header treatment (labelLarge, onSurfaceVariant, 24/8
/// padding, no divider line).
class DigestSectionHeader extends StatelessWidget {
  /// Creates the section header.
  const DigestSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        AppLocalizations.of(context).settingsDigestSectionTitle,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The 'Daily summary' on/off switch row.
class DigestToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const DigestToggleTile({
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Whether the digest is currently enabled.
  final bool value;

  /// Called when the switch is flipped.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return semantic(
      'settings.digest.toggle',
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_outlined),
        title: Text(AppLocalizations.of(context).settingsDigestToggleTitle),
        value: value,
        onChanged: onChanged,
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
    final time = TimeOfDay(
      hour: minutesSinceMidnight ~/ 60,
      minute: minutesSinceMidnight % 60,
    );
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.digest.time',
      child: ListTile(
        leading: const SizedBox(width: 24),
        title: Text(l10n.settingsDigestTimeLabel),
        trailing: Text(
          time.format(context),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        onTap: () => _pick(context),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final time = TimeOfDay(
      hour: minutesSinceMidnight ~/ 60,
      minute: minutesSinceMidnight % 60,
    );
    // Input mode (rather than the default dial) so the picker is reachable
    // by typing a time directly — also what makes this deterministically
    // driveable from a widget test, unlike the dial's freeform gestures.
    final picked = await showTimePicker(
      context: context,
      initialTime: time,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      onChanged(picked.hour * 60 + picked.minute);
    }
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
