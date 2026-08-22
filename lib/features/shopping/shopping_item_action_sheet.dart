/// The long-press action sheet for a shopping item tile (backlog D-3).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The action a user picked from [showShoppingItemActionSheet], or `null`
/// if they dismissed it without picking one.
enum ShoppingItemMenuAction {
  /// Delete the item, with the same undo snackbar as every other shopping
  /// delete path (`shopping_delete.dart`).
  delete,
}

/// Shows the tile-level long-press sheet, currently offering only Delete --
/// see "OD-2" in `docs/plans/2026-08-08-shopping-gestures.md` for why this
/// menu is deliberately one row rather than mirroring the chore action
/// sheet's five: renaming/quantity/category already has a one-tap path (the
/// row's own [InkWell.onTap] opens the edit sheet) and checking/unchecking
/// already has a dedicated 48dp control, so duplicating either here would
/// only make an already-one-tap action slower. Delete is the one action
/// introduced by a gesture (swipe-left, D-2) with no other tap-only path,
/// and a calibrated horizontal drag is exactly what a user on Switch
/// Control or with a motor condition cannot rely on -- so this sheet is
/// that path, and it is an accessibility floor rather than a second door to
/// something a tap already does.
///
/// Resolves to the chosen [ShoppingItemMenuAction] (or `null` if dismissed).
/// Row shape (22dp icon, ≥48dp height, drag handle from the app-wide
/// `BottomSheetThemeData` in `lib/app/theme.dart` -- never hand-rolled
/// here) matches `chore_action_sheet.dart` exactly.
Future<ShoppingItemMenuAction?> showShoppingItemActionSheet(
  BuildContext context,
) {
  return showModalBottomSheet<ShoppingItemMenuAction>(
    context: context,
    builder: (sheetContext) {
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      final l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            semantic(
              'shopping.menu.delete',
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
                  Navigator.pop(sheetContext, ShoppingItemMenuAction.delete);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
