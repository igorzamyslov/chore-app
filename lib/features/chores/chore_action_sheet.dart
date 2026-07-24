/// The skip/edit/pause/delete action sheet for a chore occurrence tile.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:flutter/material.dart';

/// The action a user picked from [showChoreActionSheet], or `null` if they
/// dismissed it without picking one.
enum ChoreMenuAction {
  /// Skip the pending occurrence.
  skip,

  /// Open the chore in the edit form.
  edit,

  /// Pause the chore (removing its pending occurrence).
  pause,

  /// Delete the chore, after confirmation.
  delete,
}

/// Shows the tile-level bottom sheet offering skip/edit/pause/delete, and
/// resolves to the chosen [ChoreMenuAction] (or `null` if dismissed).
Future<ChoreMenuAction?> showChoreActionSheet(BuildContext context) {
  return showModalBottomSheet<ChoreMenuAction>(
    context: context,
    builder: (sheetContext) {
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            semantic(
              'chores.menu.skip',
              child: ListTile(
                leading: const Icon(Icons.skip_next_outlined),
                title: const Text('Skip'),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.skip);
                },
              ),
            ),
            semantic(
              'chores.menu.edit',
              child: ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.edit);
                },
              ),
            ),
            semantic(
              'chores.menu.pause',
              child: ListTile(
                leading: const Icon(Icons.pause_circle_outlined),
                title: const Text('Pause'),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.pause);
                },
              ),
            ),
            semantic(
              'chores.menu.delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: errorColor),
                title: Text('Delete', style: TextStyle(color: errorColor)),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.delete);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
