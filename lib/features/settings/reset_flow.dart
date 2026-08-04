/// The Settings tab's destructive 'Reset app data' row and its
/// double-confirm flow (spec `docs/specs/polish-round-1.md` B2), grouped
/// under the Data section header (`DataSectionHeader`, `export_row.dart`)
/// alongside the export row (spec
/// `docs/feedback/2026-08-01-field-feedback.md` B4/F7).
///
/// The first dialog's body is state-aware (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A6): a linked device's "there is
/// no cloud backup" claim was FALSE (the household lives on the server;
/// signing in again reconnects it) -- [ResetDataTile] reads
/// [settingsProvider]'s `syncHouseholdId` to pick the right copy.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The destructive 'Reset app data' row at the very bottom of Settings,
/// immediately under the export row in the Data section.
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
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;
    return semantic(
      'settings.reset',
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: errorColor),
        title: Text(
          l10n.settingsResetEntry,
          style: TextStyle(color: errorColor),
        ),
        onTap: () => _confirmAndReset(context, ref, linked: linked),
      ),
    );
  }

  Future<void> _confirmAndReset(
    BuildContext context,
    WidgetRef ref, {
    required bool linked,
  }) async {
    final firstConfirmed = await _showFirstDialog(context, linked: linked);
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

  Future<bool> _showFirstDialog(
    BuildContext context, {
    required bool linked,
  }) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsResetConfirm1Title),
          content: Text(
            linked
                ? l10n.settingsResetConfirm1BodyLinked
                : l10n.settingsResetConfirm1Body,
          ),
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
