/// The clear-checked confirmation dialog.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for clearing [count] checked items, resolving
/// to whether the user confirmed (defaults to `false` if dismissed).
Future<bool> showClearCheckedDialog(
  BuildContext context, {
  required int count,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.shoppingClearDialogTitle),
        content: Text(l10n.shoppingClearDialogBody(count)),
        actions: [
          semantic(
            'shopping.clear.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'shopping.clear.confirm',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.shoppingClearConfirm),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
