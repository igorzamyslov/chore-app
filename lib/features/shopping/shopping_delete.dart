/// The single shared delete-with-undo action for one shopping item.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Soft-deletes the item [itemId] and shows the standard 'Removed' undo
/// snackbar (spec `docs/specs/polish-round-1.md` C3), whose UNDO action
/// restores it by clearing `deleted_at` — a plain
/// `ShoppingRepository.restoreItem` call, since soft delete never touches
/// any other column.
///
/// This is the ONE place that logic lives (backlog D-2: "the swipe must
/// reuse that existing undo, not invent a second one"). Since the
/// 2026-09-19 field report there is also exactly ONE door: the edit sheet's
/// Delete button (`shopping_edit_sheet.dart`), reached by long-pressing the
/// row. The other two doors are gone — swipe-left took the tab pager's
/// horizontal gesture with it, and the one-row long-press menu it existed
/// to back up went with it. The function stays a shared helper rather than
/// being inlined into the sheet: it is the sheet's only caller today, but
/// it is also the written contract that a delete never confirms and always
/// offers undo, and that contract is what a second door would have to meet.
///
/// Never confirms first (spec `docs/specs/design-language.md` rule 3, and
/// `docs/specs/ui-shopping.md`: shopping items are cheap and the undo is the
/// recovery). No caller may add a confirmation dialog in front of it.
Future<void> deleteShoppingItemWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
}) async {
  final repository = ref.read(shoppingRepositoryProvider);
  await repository.deleteItem(itemId);
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  showAppSnackbar(
    context,
    message: l10n.shoppingDeletedSnackbar,
    action: SnackBarAction(
      label: l10n.shoppingDeletedUndo,
      onPressed: () => unawaited(repository.restoreItem(itemId)),
    ),
  );
}
