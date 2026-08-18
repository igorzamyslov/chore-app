/// A single shopping item's list row.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';

/// A row for one active [ShoppingItemWithCategory].
///
/// Leading check control (tap toggles checked/unchecked via
/// [onCheckedChanged], writing through immediately): a 23dp ring inside a
/// 48dp tap target (spec `docs/specs/theme-v2.md` §4.3) -- an `outline` 2px
/// border when unchecked, filled `primary` with an `onPrimary` check when
/// checked. Tapping anywhere else on the row opens the edit sheet via
/// [onTap]. The same row renders both the unchecked list and the checked
/// section -- checked items render with strikethrough, muted text (color is
/// never the only signal for the checked state, per
/// `docs/specs/design-language.md`).
///
/// Two more gestures (backlog D-2/D-3, conventions audit C2/C5): swiping
/// left ([DismissDirection.endToStart] only, never both directions) fires
/// [onSwipeDelete]; long-pressing anywhere on the row fires [onLongPress].
/// Both ultimately call the SAME `deleteShoppingItemWithUndo` the edit
/// sheet's own Delete button uses (`shopping_delete.dart`) -- there is
/// exactly one delete-with-undo behavior in the app, reached three ways.
/// The row wins the horizontal gesture arena against the shell's tab
/// `PageView` because it is deeper in the tree, which is a deliberate,
/// documented trade-off -- see `docs/specs/ui-shopping.md`
/// §"Behaviors & constraints" for the accepted cost and the escape hatch,
/// and do NOT try to hand the pager priority back.
///
/// This widget is deliberately bare (no card of its own): callers group rows
/// from the same category into one shared card (see `ShoppingListScreen`'s
/// aisle cards and `ShoppingCheckedSection`'s cart card), hairline-separated,
/// rather than each row carrying its own card as before this wave.
class ShoppingItemTile extends StatelessWidget {
  /// Creates a row for [item].
  const ShoppingItemTile({
    required this.item,
    required this.onCheckedChanged,
    required this.onTap,
    required this.onLongPress,
    required this.onSwipeDelete,
    super.key,
  });

  /// The item (and its joined category) to display.
  final ShoppingItemWithCategory item;

  /// Called with the new checked value when the leading check control is
  /// tapped.
  final ValueChanged<bool> onCheckedChanged;

  /// Called when the row is tapped anywhere but the check control.
  final VoidCallback onTap;

  /// Called when the row is long-pressed, to open the delete action sheet
  /// (backlog D-3) -- the tap-reachable equivalent of [onSwipeDelete] for
  /// anyone who can't perform a calibrated horizontal drag.
  final VoidCallback onLongPress;

  /// Called once the swipe-to-delete gesture's own dismiss animation
  /// completes (backlog D-2). The caller does the actual delete + undo
  /// snackbar (`deleteShoppingItemWithUndo`) -- this widget only reports
  /// that the gesture happened, matching how [onTap]/[onLongPress] report
  /// gestures without owning their side effects.
  final VoidCallback onSwipeDelete;

  @override
  Widget build(BuildContext context) {
    final shoppingItem = item.item;
    final checked = shoppingItem.checkedAt != null;
    final theme = Theme.of(context);
    final quantityNote = shoppingItem.quantityNote;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Dismissible(
      key: ValueKey('shopping.item.${shoppingItem.id}.dismissible'),
      // Single direction (OD-1, docs/plans/2026-08-08-shopping-gestures.md):
      // delete-only, swipe left -- never both directions, so this never
      // duplicates the dedicated 48dp check-ring control and keeps the
      // smallest possible collision surface against the shell's tab
      // `PageView` (backlog D-1, `lib/app/app_shell.dart`).
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onSwipeDelete(),
      background: const _SwipeDeleteBackground(),
      child: semantic(
        'shopping.item.${shoppingItem.id}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _CheckRing(
                    identifier: 'shopping.item.${shoppingItem.id}.check',
                    checked: checked,
                    onChanged: onCheckedChanged,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shoppingItem.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              decoration: checked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: checked ? mutedColor : null,
                            ),
                          ),
                          if (quantityNote != null && quantityNote.isNotEmpty)
                            Text(
                              quantityNote,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedColor,
                                decoration: checked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The swipe-to-delete background: an `errorContainer` ground with a
/// trailing delete glyph in `error`, revealed as the row is dragged left --
/// the same error-container/error pairing the overdue chore tile already
/// uses (`lib/features/chores/chore_occurrence_tile.dart`), so this doesn't
/// introduce a new color pairing. Purely a transient drag-in-progress
/// affordance, not a persistent status color, so it doesn't conflict with
/// design-language.md's "category color is an accent, not a background"
/// rule (a different subject: persistent per-item state, not a one-off
/// gesture reveal).
class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.errorContainer,
      // Directional, not `centerRight`: the glyph must sit at the END of the
      // row, which is where an `endToStart` drag reveals it in either text
      // direction.
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(Icons.delete_outline, color: colorScheme.error),
    );
  }
}

/// The 23dp check ring inside a 48dp tap target (spec
/// `docs/specs/theme-v2.md` §4.3/§5): hand-rolled (rather than a Material
/// [Checkbox], which has no supported way to render at this exact visual
/// size) but carries the same accessibility contract via an explicit
/// `Semantics.checked` flag, so it still announces as a toggle to assistive
/// technology.
class _CheckRing extends StatelessWidget {
  const _CheckRing({
    required this.identifier,
    required this.checked,
    required this.onChanged,
  });

  final String identifier;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: identifier,
      container: true,
      button: true,
      checked: checked,
      onTap: () => onChanged(!checked),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onChanged(!checked),
            child: Center(
              child: Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? colorScheme.primary : null,
                  border: checked
                      ? null
                      : Border.all(color: colorScheme.outline, width: 2),
                ),
                child: checked
                    ? Icon(Icons.check, size: 16, color: colorScheme.onPrimary)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
