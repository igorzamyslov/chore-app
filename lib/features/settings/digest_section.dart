/// The settings screen's 'Daily summary' rows, inside the Preferences group
/// (spec `docs/specs/theme-v2.md` §4.2): digest on/off toggle, time row, and
/// OS-permission hint (spec `docs/specs/notifications.md`).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Daily summary' on/off switch row.
class DigestToggleTile extends StatelessWidget {
  /// Creates the toggle row.
  const DigestToggleTile({
    required this.value,
    required this.onChanged,
    this.permissionDenied = false,
    this.reminderOverflowCount = 0,
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

  /// How many reminder-enabled chores did not fit under [reminderCeiling]
  /// and are therefore still counted by the daily summary (spec
  /// `docs/specs/notifications-n2.md` §3.2, decision D4). `0` when the
  /// ceiling does not bind.
  ///
  /// Read straight off `NotificationPlanSet.reminderOverflowCount`, which
  /// the planning pass produces at its single truncation site. This widget
  /// must never re-derive it: two copies of §2.3's arming rule diverge the
  /// moment either changes, and a sub-line that lies about a set it did not
  /// compute is worse than no sub-line.
  ///
  /// A **pure projection** of state that already exists -- no stored flag,
  /// nothing to dismiss, nothing that can go stale -- matching the
  /// permission-denied hint's pattern (backlog B-5 / triage T2.6).
  ///
  /// Precedence when both sub-lines would apply: the permission-denied hint
  /// wins. A hard delivery failure ("nothing is arriving at all") outranks a
  /// cadence downgrade ("these arrive in the summary instead"), and
  /// [SettingsRow] shows one sub-line.
  ///
  /// Shown only while [value] is true. With the digest off there is no daily
  /// summary for these chores to stay in, so the sentence would be FALSE --
  /// spec §2.5 records exactly that as the one place the partition degrades,
  /// and it is not a defect to be papered over with copy.
  final int reminderOverflowCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.digest.toggle',
      child: SettingsRow(
        icon: Icons.notifications_outlined,
        label: l10n.settingsDigestToggleTitle,
        sublabel: switch ((value, permissionDenied, reminderOverflowCount)) {
          (true, _, final int over) when over > 0 =>
            l10n.settingsRemindersCeilingHint(over, reminderCeiling),
          (true, true, _) => l10n.settingsDigestToggleDeniedHint,
          _ => null,
        },
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
    final time = TimeOfDay(
      hour: minutesSinceMidnight ~/ 60,
      minute: minutesSinceMidnight % 60,
    );
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.digest.time',
      child: SettingsRow(
        icon: Icons.schedule_outlined,
        label: l10n.settingsDigestTimeLabel,
        value: time.format(context),
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
