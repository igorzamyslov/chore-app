/// The Settings tab's root screen.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/manage_categories_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The Settings tab (spec `docs/specs/ux-round-2.md` B1: "Manage
/// categories" is this tab's first real content).
///
/// A plain [ListView] of entries, leaving room for future settings
/// sections beyond category management.
class SettingsScreen extends StatelessWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTabLabel)),
      body: ListView(
        children: [
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
        ],
      ),
    );
  }
}
