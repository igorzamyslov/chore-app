/// The settings screen's 'Language' entry and its picker sheet (spec
/// `docs/next-session-plan.md` #5): System default / English / Deutsch,
/// persisted via `SettingsRepository.setLocale` and consumed by
/// `localeOverrideProvider` (`lib/app/providers.dart`).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Settings tab's 'Language' row: shows the current choice (System
/// default / English / Deutsch) as its subtitle; tapping opens
/// [showLanguageSheet].
class LanguageRow extends ConsumerWidget {
  /// Creates the language row.
  const LanguageRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(settingsProvider).valueOrNull?.locale;
    final subtitle = switch (locale) {
      'en' => l10n.settingsLanguageEnglish,
      'de' => l10n.settingsLanguageDeutsch,
      _ => l10n.settingsLanguageSystem,
    };

    return semantic(
      'settings.language',
      child: ListTile(
        leading: const Icon(Icons.language_outlined),
        title: Text(l10n.settingsLanguageEntry),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showLanguageSheet(context),
      ),
    );
  }
}

/// Opens the language picker: System default / English / Deutsch, with a
/// check on the current choice. Selecting a row persists it via
/// `SettingsRepository.setLocale` and closes the sheet.
Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(settingsProvider).valueOrNull?.locale;

    Future<void> select(String? locale) async {
      await ref.read(settingsRepositoryProvider).setLocale(locale);
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
      'settings.language.sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.settingsLanguageSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            option(
              id: 'settings.language.sheet.system',
              label: l10n.settingsLanguageSystem,
              selected: current == null,
              value: null,
            ),
            option(
              id: 'settings.language.sheet.en',
              label: l10n.settingsLanguageEnglish,
              selected: current == 'en',
              value: 'en',
            ),
            option(
              id: 'settings.language.sheet.de',
              label: l10n.settingsLanguageDeutsch,
              selected: current == 'de',
              value: 'de',
            ),
          ],
        ),
      ),
    );
  }
}
