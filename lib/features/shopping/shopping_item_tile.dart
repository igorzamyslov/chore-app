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
    super.key,
  });

  /// The item (and its joined category) to display.
  final ShoppingItemWithCategory item;

  /// Called with the new checked value when the leading check control is
  /// tapped.
  final ValueChanged<bool> onCheckedChanged;

  /// Called when the row is tapped anywhere but the check control.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shoppingItem = item.item;
    final checked = shoppingItem.checkedAt != null;
    final theme = Theme.of(context);
    final quantityNote = shoppingItem.quantityNote;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return semantic(
      'shopping.item.${shoppingItem.id}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
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
