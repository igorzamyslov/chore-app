/// The Settings tab's root screen.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/about_section.dart';
import 'package:chore_app/features/settings/account_section.dart';
import 'package:chore_app/features/settings/digest_section.dart';
import 'package:chore_app/features/settings/export_row.dart';
import 'package:chore_app/features/settings/language_section.dart';
import 'package:chore_app/features/settings/manage_categories_screen.dart';
import 'package:chore_app/features/settings/manage_members_screen.dart';
import 'package:chore_app/features/settings/reset_flow.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// The Settings tab (spec `docs/specs/ux-round-2.md` B1: "Manage
/// categories"; spec `docs/specs/notifications.md`: the 'Daily summary'
/// section; spec `docs/next-session-plan.md` #5: the Language row and the
/// About section at the bottom; spec `docs/specs/polish-round-1.md` B1/B2:
/// the export row and the destructive reset row at the very bottom; spec
/// `docs/specs/sync-backend.md` §5: the Account section, above About).
///
/// A plain [ListView] of entries/sections, leaving room for further
/// settings beyond category management, language, digest, and About.
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
        children: [
          semantic(
            'settings.members',
            child: ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(l10n.settingsMembersEntry),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManageMembersScreen(),
                ),
              ),
            ),
          ),
          semantic(
            'settings.categories',
            child: ListTile(
              leading: const Icon(Icons.label_outlined),
              title: Text(l10n.settingsCategoriesEntry),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManageCategoriesScreen(),
                ),
              ),
            ),
          ),
          const LanguageRow(),
          const DigestSectionHeader(),
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
          const ExportDataTile(),
          const AccountSectionHeader(),
          const AccountSectionBody(),
          const AboutSectionHeader(),
          const AboutVersionTile(),
          const AboutLicensesTile(),
          const AboutDonateTile(),
          const ResetSectionHeader(),
          const ResetDataTile(),
        ],
      ),
    );
  }
}
