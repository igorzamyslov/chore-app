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
