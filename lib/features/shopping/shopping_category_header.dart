/// A category-run header for the shopping list's unchecked-items section.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The header shown above a run of items sharing the same category (spec
/// `docs/specs/theme-v2.md` §4.3): [category]'s icon and uppercase name,
/// both in the category's own color, followed by a 1px `outlineVariant`
/// rule filling the remaining width; a neutral 'Uncategorized' label (icon +
/// text in [ColorScheme.onSurfaceVariant]) when [category] is `null`.
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
    final color = category != null
        ? categoryTone(context, category.color)
        : onSurfaceVariant;
    final icon = category != null
        ? categoryIcon(category.icon)
        : Icons.label_outlined;
    final name =
        category?.name ?? AppLocalizations.of(context).shoppingUncategorized;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              // Uppercased here (never by an already-uppercase ARB string --
              // German capitalization rules differ, spec theme-v2.md §2).
              name.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}
