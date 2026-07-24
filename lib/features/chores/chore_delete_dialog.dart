/// The delete-confirmation dialog for a chore.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for deleting the chore titled [choreTitle],
/// resolving to whether the user confirmed (defaults to `false` if
/// dismissed).
Future<bool> showChoreDeleteDialog(
  BuildContext context, {
  required String choreTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.choresDeleteDialogTitle),
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
            child: TextButton(
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
