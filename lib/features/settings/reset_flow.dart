/// The Settings tab's destructive 'Reset app data' row and its
/// double-confirm flow (spec `docs/specs/polish-round-1.md` B2).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Section header above [ResetDataTile], matching every other Settings
/// section header's style but existing purely to visually separate the
/// destructive row from everything above it (spec: "visually separated,
/// destructive-styled row").
class ResetSectionHeader extends StatelessWidget {
  /// Creates the section header.
  const ResetSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        AppLocalizations.of(context).settingsResetSectionTitle,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The destructive 'Reset app data' row at the very bottom of Settings.
///
/// Tapping it runs the spec's double-confirm (two chained dialogs; a
/// cancel anywhere is a no-op and leaves the database untouched). Only
/// after both confirms does it call [resetAppData] and invalidate
/// [bootstrapProvider] (and [settingsProvider], whose device-settings row
/// the reset just deleted out from under its already-running watch
/// stream) so the app re-bootstraps to the fresh-install state.
class ResetDataTile extends ConsumerWidget {
  /// Creates the reset row.
  const ResetDataTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    return semantic(
      'settings.reset',
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: errorColor),
        title: Text(
          l10n.settingsResetEntry,
          style: TextStyle(color: errorColor),
        ),
        onTap: () => _confirmAndReset(context, ref),
      ),
    );
  }

  Future<void> _confirmAndReset(BuildContext context, WidgetRef ref) async {
    final firstConfirmed = await _showFirstDialog(context);
    if (!firstConfirmed || !context.mounted) {
      return;
    }
    final secondConfirmed = await _showSecondDialog(context);
    if (!secondConfirmed || !context.mounted) {
      return;
    }

    final database = ref.read(appDatabaseProvider);
    await resetAppData(database);
    ref
      ..invalidate(bootstrapProvider)
      ..invalidate(settingsProvider);
  }

  Future<bool> _showFirstDialog(BuildContext context) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsResetConfirm1Title),
          content: Text(l10n.settingsResetConfirm1Body),
          actions: [
            semantic(
              'settings.reset.cancel1',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.reset.confirm1',
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: errorColor),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.settingsResetConfirm1Action),
              ),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<bool> _showSecondDialog(BuildContext context) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsResetConfirm2Title),
          content: Text(l10n.settingsResetConfirm2Body),
          actions: [
            semantic(
              'settings.reset.cancel',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.reset.confirm2',
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: errorColor),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.settingsResetConfirm2Action),
              ),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}
