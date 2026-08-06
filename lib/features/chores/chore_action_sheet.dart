/// The skip/edit/pause/delete action sheet for a chore occurrence tile.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
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
///
/// Rows are full-width with 22dp icons and a ≥48dp height (spec
/// `docs/specs/theme-v2.md` §4.5); delete sits last, in `error`. The drag
/// handle comes from the app-wide `BottomSheetThemeData`
/// (`lib/app/theme.dart`) -- never hand-rolled here.
Future<ChoreMenuAction?> showChoreActionSheet(BuildContext context) {
  return showModalBottomSheet<ChoreMenuAction>(
    context: context,
    builder: (sheetContext) {
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      final l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            semantic(
              'chores.menu.skip',
              child: ListTile(
                leading: const Icon(Icons.skip_next_outlined, size: 22),
                title: Text(l10n.choresMenuSkip),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.skip);
                },
              ),
            ),
            semantic(
              'chores.menu.edit',
              child: ListTile(
                leading: const Icon(Icons.edit_outlined, size: 22),
                title: Text(l10n.choresMenuEdit),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.edit);
                },
              ),
            ),
            semantic(
              'chores.menu.pause',
              child: ListTile(
                leading: const Icon(Icons.pause_circle_outlined, size: 22),
                title: Text(l10n.choresMenuPause),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.pause);
                },
              ),
            ),
            semantic(
              'chores.menu.delete',
              child: ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: errorColor,
                  size: 22,
                ),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: errorColor),
                ),
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
