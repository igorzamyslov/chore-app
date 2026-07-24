/// The delete-confirmation dialog for a chore.
library;

import 'package:chore_app/app/semantics.dart';
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
      return AlertDialog(
        title: const Text('Delete chore?'),
        content: Text(
          "This deletes '$choreTitle'. Its history is kept, but its "
          'pending occurrence is removed.',
        ),
        actions: [
          semantic(
            'chores.delete.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
          ),
          semantic(
            'chores.delete.confirm',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
