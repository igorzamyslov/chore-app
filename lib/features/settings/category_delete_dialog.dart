/// The delete-confirmation dialog for a category.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for deleting the category named
/// [categoryName], resolving to whether the user confirmed (defaults to
/// `false` if dismissed).
///
/// Deleting a category detaches it from every chore/shopping item that
/// references it (they become uncategorized) — costly enough to confirm,
/// per `docs/specs/design-language.md` rule 3.
Future<bool> showCategoryDeleteDialog(
  BuildContext context, {
  required String categoryName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.categoryDeleteDialogTitle),
        content: Text(l10n.categoryDeleteDialogBody(categoryName)),
        actions: [
          semantic(
            'settings.categories.delete.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'settings.categories.delete.confirm',
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
