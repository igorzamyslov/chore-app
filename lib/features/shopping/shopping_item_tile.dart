/// A single shopping item's list row.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';

/// A row for one active [ShoppingItemWithCategory].
///
/// **Ticking is the row's primary gesture.** Tapping ANYWHERE on the row --
/// the 23dp check ring inside its 48dp tap target (spec
/// `docs/specs/theme-v2.md` §4.3) or the name and quantity beside it --
/// toggles checked/unchecked through [onCheckedChanged]. The ring is an
/// `outline` 2px border when unchecked and a filled `primary` circle with an
/// `onPrimary` check when checked. The same row renders both the unchecked
/// list and the checked section; checked items render with strikethrough,
/// muted text (color is never the only signal for the checked state, per
/// `docs/specs/design-language.md`).
///
/// **Long-pressing opens the item's menu** -- the edit sheet -- through
/// [onLongPress]. Rename, quantity, category and Delete all live there, so
/// long-press is the one door to everything ticking is not.
///
/// There is deliberately NO horizontal gesture here. The row used to carry a
/// swipe-left `Dismissible` (backlog D-2), which won the gesture arena
/// against the shell's tab `PageView` and therefore stopped the user paging
/// away from Shopping over any row -- a cost `docs/specs/ui-shopping.md`
/// recorded as accepted, with an escape hatch, and which Igor then hit on a
/// real phone (field report 2026-09-19, v0.10.1). The hatch was taken. Do
/// NOT reintroduce a `Dismissible`, a `GestureDetector` with horizontal drag
/// callbacks, or anything else that claims a horizontal drag on this row:
/// the middle tab's rows cover most of the screen, so whatever they claim,
/// the pager cannot have.
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
    required this.onLongPress,
    super.key,
  });

  /// The item (and its joined category) to display.
  final ShoppingItemWithCategory item;

  /// Called with the new checked value when the row is tapped -- on the
  /// check ring or anywhere else on the row, which are the same action.
  ///
  /// The ring keeps its own nested tap target rather than relying on the
  /// row's: it carries the `Semantics.checked` flag assistive technology
  /// reads, and it is the 48dp target `theme-v2.md` §4.3 specifies.
  final ValueChanged<bool> onCheckedChanged;

  /// Called when the row is long-pressed, to open the item's menu -- the
  /// edit sheet (`shopping_edit_sheet.dart`), where rename, quantity,
  /// category and Delete live.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final shoppingItem = item.item;
    final checked = shoppingItem.checkedAt != null;
    final theme = Theme.of(context);
    final quantityNote = shoppingItem.quantityNote;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      // INVERSION 1a: put a horizontal-drag claim back on the row, the way
      // the removed `Dismissible` did. Nothing else changes.
      onHorizontalDragStart: (_) {},
      child: semantic(
        'shopping.item.${shoppingItem.id}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            // The row's tap IS the tick (field report 2026-09-19): it is the
            // thing a user does dozens of times per shop, so it gets the
            // cheapest gesture and the largest target. Editing, which is
            // rare, moved to the long-press below.
            onTap: () => onCheckedChanged(!checked),
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
