/// The discard-changes confirmation dialog for the chore form (C4,
/// conventions audit `docs/feedback/2026-08-06-conventions-audit.md`;
/// implements `design-language.md` interaction rule 7, "never lose user
/// input"). Deliberately a standalone file rather than living inside
/// `lib/features/chores/chore_form/` or `chore_form_screen.dart` itself: a
/// concurrent wave is editing both, and this dialog only needs a
/// `BuildContext` to show, so it can live anywhere under `lib/features/chores/`.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for discarding unsaved chore-form changes,
/// resolving to whether the user confirmed discarding (defaults to `false`
/// if dismissed, which keeps editing -- same "dismiss = safest option" shape
/// as `chore_delete_dialog.dart`'s `showChoreDeleteDialog`).
Future<bool> showChoreFormDiscardDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.choreFormDiscardDialogTitle),
        content: Text(l10n.choreFormDiscardDialogBody),
        actions: [
          semantic(
            'chore_form.discard.keepEditing',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.choreFormDiscardKeepEditing),
            ),
          ),
          semantic(
            'chore_form.discard.confirm',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.choreFormDiscardConfirm),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
