/// A category-run header for the shopping list's unchecked-items section.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// The header shown above a run of items sharing the same category:
/// [category]'s icon and name, both in the category's own color; a neutral
/// 'Uncategorized' label (icon + text in [ColorScheme.onSurfaceVariant])
/// when [category] is `null`.
class ShoppingCategoryHeader extends StatelessWidget {
  /// Creates a header for [category] (`null` for the uncategorized run).
  const ShoppingCategoryHeader({required this.category, super.key});

  /// The category this run of items belongs to, or `null` for the
  /// uncategorized run.
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final category = this.category;
    final color = category != null ? Color(category.color) : onSurfaceVariant;
    final icon = category != null
        ? categoryIcon(category.icon)
        : Icons.label_outlined;
    final name = category?.name ?? 'Uncategorized';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
