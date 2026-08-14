/// The delete-confirmation dialog for a category.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for deleting the category named
/// [categoryName], resolving to whether the user confirmed (defaults to
/// `false` if dismissed).
///
/// Deleting a category detaches it from every active chore/shopping item
/// that references it (they become uncategorized) — costly enough to
/// confirm, per `docs/specs/design-language.md` rule 3. [kind] picks
/// chore-worded or shopping-worded copy (a category only ever references
/// one or the other); [referenceCount] must already be resolved by the
/// caller — this dialog never queries the database itself — and is the
/// exact number of active rows the delete will detach, per
/// `CategoryRepository.countActiveReferences`. `referenceCount == 0` reads
/// as a distinct, lower-stakes sentence rather than a "0 chores" plural.
Future<bool> showCategoryDeleteDialog(
  BuildContext context, {
  required String categoryName,
  required CategoryKind kind,
  required int referenceCount,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      final body = switch ((kind, referenceCount)) {
        (CategoryKind.chore, 0) => l10n.categoryDeleteDialogBodyChoresZero(
          categoryName,
        ),
        (CategoryKind.chore, final count) =>
          l10n.categoryDeleteDialogBodyChoresCount(categoryName, count),
        (CategoryKind.shopping, 0) => l10n.categoryDeleteDialogBodyShoppingZero(
          categoryName,
        ),
        (CategoryKind.shopping, final count) =>
          l10n.categoryDeleteDialogBodyShoppingCount(categoryName, count),
      };
      return AlertDialog(
        title: Text(l10n.categoryDeleteDialogTitle),
        content: Text(body),
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
