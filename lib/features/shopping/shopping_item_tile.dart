/// A single shopping item's list tile.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';

/// A tile for one active [ShoppingItemWithCategory].
///
/// Leading round checkbox (tap toggles checked/unchecked via
/// [onCheckedChanged], writing through immediately); tapping anywhere else
/// on the tile opens the edit sheet via [onTap]. The same tile renders both
/// the unchecked list and the checked section — checked items render with
/// strikethrough, muted text.
class ShoppingItemTile extends StatelessWidget {
  /// Creates a tile for [item].
  const ShoppingItemTile({
    required this.item,
    required this.onCheckedChanged,
    required this.onTap,
    super.key,
  });

  /// The item (and its joined category) to display.
  final ShoppingItemWithCategory item;

  /// Called with the new checked value when the leading checkbox is tapped.
  final ValueChanged<bool> onCheckedChanged;

  /// Called when the tile is tapped anywhere but the checkbox.
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
      child: ListTile(
        onTap: onTap,
        leading: semantic(
          'shopping.item.${shoppingItem.id}.check',
          child: Checkbox(
            value: checked,
            shape: const CircleBorder(),
            onChanged: (value) => onCheckedChanged(value ?? false),
          ),
        ),
        title: Text(
          shoppingItem.name,
          style: theme.textTheme.titleMedium?.copyWith(
            decoration: checked ? TextDecoration.lineThrough : null,
            color: checked ? mutedColor : null,
          ),
        ),
        subtitle: quantityNote == null || quantityNote.isEmpty
            ? null
            : Text(
                quantityNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mutedColor,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
      ),
    );
  }
}
