/// The clear-checked confirmation dialog.
library;

import 'package:chore_app/app/semantics.dart';
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
      return AlertDialog(
        title: const Text('Clear checked items?'),
        content: Text(
          'This removes $count checked item${count == 1 ? '' : 's'} from '
          'the list.',
        ),
        actions: [
          semantic(
            'shopping.clear.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
          ),
          semantic(
            'shopping.clear.confirm',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear'),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
