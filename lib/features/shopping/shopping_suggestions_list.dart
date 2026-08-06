/// Type-ahead suggestions shown under the shopping list's quick-add field.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:flutter/material.dart';

/// Renders [suggestions] (already ranked and limited by
/// `ShoppingRepository.suggestions`) as a wrap of tappable pill chips below
/// the quick-add field (spec `docs/specs/theme-v2.md` §3/§4.3: pill radius
/// 20, unselected style -- the app's shared `ChipThemeData` already gives
/// any [ActionChip] that look, so this widget only had to change container
/// from a column of full-width rows to a wrap of chips): each shows the
/// item's name and, when its most recent history row set one, its category
/// (icon + name in the category's own color).
///
/// Tapping a chip calls [onTap] with that suggestion; the caller (the
/// quick-add row) adds it immediately, subject to the same duplicate
/// prevention as a typed submit. See `docs/specs/ux-round-2.md` B2/B3.
class ShoppingSuggestionsList extends StatelessWidget {
  /// Creates the suggestions list for [suggestions].
  const ShoppingSuggestionsList({
    required this.suggestions,
    required this.onTap,
    super.key,
  });

  /// The suggestions to render, in display order (already ranked/limited).
  final List<ShoppingSuggestion> suggestions;

  /// Called with the tapped suggestion.
  final ValueChanged<ShoppingSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < suggestions.length; i++)
            _SuggestionChip(
              index: i,
              suggestion: suggestions[i],
              onTap: () => onTap(suggestions[i]),
            ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.index,
    required this.suggestion,
    required this.onTap,
  });

  final int index;
  final ShoppingSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = suggestion.category;
    return semantic(
      'shopping.suggestion.$index',
      child: ActionChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(suggestion.name),
            if (category != null) ...[
              const SizedBox(width: 6),
              CategoryBadge(category: category),
            ],
          ],
        ),
        onPressed: onTap,
      ),
    );
  }
}
