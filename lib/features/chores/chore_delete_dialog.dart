/// The delete-confirmation dialog for a chore.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for deleting the chore titled [choreTitle],
/// resolving to whether the user confirmed (defaults to `false` if
/// dismissed).
///
/// A 44dp `errorContainer` rounded tile holds a `delete` glyph above the
/// title (spec `docs/specs/theme-v2.md` §4.5); title = the consequence,
/// body = one line, actions are Cancel (text) + Delete (filled,
/// `error`/`onError`).
Future<bool> showChoreDeleteDialog(
  BuildContext context, {
  required String choreTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.delete_outline, color: colorScheme.error),
            ),
            const SizedBox(height: 12),
            Text(l10n.choresDeleteDialogTitle),
          ],
        ),
        content: Text(l10n.choresDeleteDialogBody(choreTitle)),
        actions: [
          semantic(
            'chores.delete.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'chores.delete.confirm',
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.commonDelete),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
