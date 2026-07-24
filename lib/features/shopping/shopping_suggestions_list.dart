/// Type-ahead suggestions shown under the shopping list's quick-add field.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:flutter/material.dart';

/// Renders [suggestions] (already ranked and limited by
/// `ShoppingRepository.suggestions`) as tappable rows below the quick-add
/// field: each shows the item's name and, when its most recent history row
/// set one, its category (icon + name in the category's own color).
///
/// Tapping a row calls [onTap] with that suggestion; the caller (the
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
    return Column(
      children: [
        for (var i = 0; i < suggestions.length; i++)
          _SuggestionTile(
            index: i,
            suggestion: suggestions[i],
            onTap: () => onTap(suggestions[i]),
          ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
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
      child: ListTile(
        dense: true,
        title: Text(suggestion.name),
        trailing: category == null ? null : CategoryBadge(category: category),
        onTap: onTap,
      ),
    );
  }
}
