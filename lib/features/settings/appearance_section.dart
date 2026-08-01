/// The settings screen's 'Appearance' entry and its picker sheet (spec
/// `docs/feedback/2026-08-01-field-feedback.md` G2): System / Light / Dark,
/// persisted via `SettingsRepository.setThemeMode` and consumed by
/// `themeModeProvider` (`lib/app/providers.dart`).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Settings tab's 'Appearance' row, directly below the Language row:
/// shows the current choice (System / Light / Dark) as its subtitle;
/// tapping opens [showAppearanceSheet].
class AppearanceRow extends ConsumerWidget {
  /// Creates the appearance row.
  const AppearanceRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(settingsProvider).valueOrNull?.themeMode;
    final subtitle = switch (themeMode) {
      'light' => l10n.settingsAppearanceLight,
      'dark' => l10n.settingsAppearanceDark,
      _ => l10n.settingsAppearanceSystem,
    };

    return semantic(
      'settings.appearance',
      child: ListTile(
        leading: const Icon(Icons.dark_mode_outlined),
        title: Text(l10n.settingsAppearanceEntry),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppearanceSheet(context),
      ),
    );
  }
}

/// Opens the appearance picker: System / Light / Dark, with a check on the
/// current choice. Selecting a row persists it via
/// `SettingsRepository.setThemeMode` and closes the sheet.
Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _AppearanceSheet(),
  );
}

class _AppearanceSheet extends ConsumerWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(settingsProvider).valueOrNull?.themeMode;

    Future<void> select(String? themeMode) async {
      await ref.read(settingsRepositoryProvider).setThemeMode(themeMode);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }

    Widget option({
      required String id,
      required String label,
      required bool selected,
      required String? value,
    }) {
      return semantic(
        id,
        child: ListTile(
          title: Text(label),
          trailing: selected ? const Icon(Icons.check) : null,
          onTap: () => select(value),
        ),
      );
    }

    return semantic(
      'settings.appearance.sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.settingsAppearanceSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            option(
              id: 'settings.appearance.system',
              label: l10n.settingsAppearanceSystem,
              selected: current == null,
              value: null,
            ),
            option(
              id: 'settings.appearance.light',
              label: l10n.settingsAppearanceLight,
              selected: current == 'light',
              value: 'light',
            ),
            option(
              id: 'settings.appearance.dark',
              label: l10n.settingsAppearanceDark,
              selected: current == 'dark',
              value: 'dark',
            ),
          ],
        ),
      ),
    );
  }
}
