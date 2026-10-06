/// A category-run header for the shopping list's unchecked-items section.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The header shown above a run of items sharing the same category (spec
/// `docs/specs/theme-v2.md` §4.3): [category]'s icon and uppercase name,
/// both in the category's own color, followed by a 1px `outlineVariant`
/// rule filling the remaining width; a neutral 'Uncategorized' label (icon +
/// text in [ColorScheme.onSurfaceVariant]) when [category] is `null`.
///
/// **Tapping the header collapses or expands its aisle** (persona finding
/// F9, tom-shopping MF1): a chevron shows the state, and while collapsed the
/// number of hidden items sits beside the name. The collapse state itself
/// lives with the caller (it is persisted per device); this widget only
/// reports the tap.
class ShoppingCategoryHeader extends StatelessWidget {
  /// Creates a header for [category] (`null` for the uncategorized run).
  const ShoppingCategoryHeader({
    required this.category,
    required this.collapsed,
    required this.itemCount,
    required this.onToggle,
    super.key,
  });

  /// The category this run of items belongs to, or `null` for the
  /// uncategorized run.
  final Category? category;

  /// Whether the aisle below is collapsed.
  final bool collapsed;

  /// How many items the aisle holds; shown only while [collapsed].
  final int itemCount;

  /// Called when the header is tapped.
  final VoidCallback onToggle;

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

    final key = category?.id ?? uncategorizedCollapseKey;
    return semantic(
      'shopping.category.$key.toggle',
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: _row(theme, color, icon, name),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, Color color, IconData icon, String name) {
    return Semantics(
      expanded: !collapsed,
      child: Row(
        children: [
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            color: theme.colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 4),
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Flexible(
            // Uppercased here (never by an already-uppercase ARB string --
            // German capitalization rules differ, spec theme-v2.md §2), and
            // the natural-case name stays as the accessibility label:
            // uppercase is typography, not content, so TalkBack announces
            // "Produce", not "PRODUCE".
            child: Semantics(
              label: name,
              child: ExcludeSemantics(
                child: Text(
                  name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ),
          ),
          if (collapsed) ...[
            const SizedBox(width: 6),
            Text(
              '($itemCount)',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
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
