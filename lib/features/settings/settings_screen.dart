/// The Settings tab's root screen.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/about_section.dart';
import 'package:chore_app/features/settings/account_section.dart';
import 'package:chore_app/features/settings/appearance_section.dart';
import 'package:chore_app/features/settings/digest_section.dart';
import 'package:chore_app/features/settings/export_row.dart';
import 'package:chore_app/features/settings/language_section.dart';
import 'package:chore_app/features/settings/manage_categories_screen.dart';
import 'package:chore_app/features/settings/manage_members_screen.dart';
import 'package:chore_app/features/settings/reset_flow.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// The Settings tab (spec `docs/specs/theme-v2.md` §4.2: labelled groups --
/// Household, Preferences, Data, About, in that order -- each a card of
/// hairline-separated [SettingsRow]s with the current value visible on the
/// right; spec `docs/specs/ux-round-2.md` B1: "Manage categories"; spec
/// `docs/specs/notifications.md`: the 'Daily summary' rows; spec
/// `docs/next-session-plan.md` #5: the Language row and the About group;
/// spec `docs/feedback/2026-08-01-field-feedback.md` G2: the Appearance row,
/// directly below Language; B4/F7: the Data group -- the export row, then
/// the destructive reset row).
///
/// The Household group (spec `docs/feedback/2026-08-07-field-feedback.md`
/// B2) leads with whatever [AccountSectionBody] renders (spec
/// `docs/specs/sync-backend.md` §5), then the Members row, then the
/// Categories row -- merging what used to be a separate top-level Account
/// group (between Data and About) into Household.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final permissionGranted = ref.watch(notificationPermissionGrantedProvider);
    final settingsRepository = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTabLabel)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        // C8 (conventions audit): dismisses the keyboard on a scroll drag --
        // the Account section's sign-in email field is the one text input
        // reachable from this scroll view.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SettingsGroup(
            label: l10n.settingsHouseholdSectionTitle,
            children: [
              const AccountSectionBody(),
              semantic(
                'settings.members',
                child: SettingsRow(
                  icon: Icons.people_outline,
                  label: l10n.settingsMembersEntry,
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManageMembersScreen(),
                    ),
                  ),
                ),
              ),
              semantic(
                'settings.categories',
                child: SettingsRow(
                  icon: Icons.label_outlined,
                  label: l10n.settingsCategoriesEntry,
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManageCategoriesScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SettingsGroup(
            label: l10n.settingsPreferencesSectionTitle,
            children: [
              const LanguageRow(),
              const AppearanceRow(),
              ...settingsAsync.when(
                data: (settings) => [
                  DigestToggleTile(
                    value: settings.digestEnabled,
                    onChanged: (enabled) =>
                        settingsRepository.setDigestEnabled(enabled: enabled),
                  ),
                  if (settings.digestEnabled)
                    DigestTimeTile(
                      minutesSinceMidnight: settings.digestMinutes,
                      onChanged: settingsRepository.setDigestTime,
                    ),
                  if (settings.digestEnabled && !permissionGranted)
                    const DigestPermissionHint(onOpenSettings: openAppSettings),
                ],
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (error, stackTrace) => const [],
              ),
            ],
          ),
          SettingsGroup(
            label: l10n.settingsDataSectionTitle,
            children: const [ExportDataTile(), ResetDataTile()],
          ),
          SettingsGroup(
            label: l10n.settingsAboutSectionTitle,
            children: const [
              AboutVersionTile(),
              AboutLicensesTile(),
              AboutDonateTile(),
            ],
          ),
        ],
      ),
    );
  }
}
