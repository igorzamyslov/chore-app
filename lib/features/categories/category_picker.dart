/// Selectable horizontal chip row for choosing a category (or none).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// A horizontally-scrollable row of [ChoiceChip]s: one 'None' chip plus one
/// chip per entry in [categories], each showing its icon and name in its own
/// color.
///
/// Every chip is individually wrapped with a stable identifier:
/// `'$idPrefix.none'` for the 'None' chip, `'$idPrefix.${category.id}'` for
/// each category. This lets the same widget serve both the chore form's
/// `chore_form.category*` ids and a future shopping form's own prefix.
class CategoryPicker extends StatelessWidget {
  /// Creates a picker over [categories], currently selecting
  /// [selectedCategoryId] (`null` for 'None'), reporting changes via
  /// [onChanged], with semantic ids rooted at [idPrefix].
  const CategoryPicker({
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
    required this.idPrefix,
    super.key,
  });

  /// The selectable categories, in display order.
  final List<Category> categories;

  /// The currently-selected category id, or `null` for 'None'.
  final String? selectedCategoryId;

  /// Called with the newly-selected category id (`null` for 'None').
  final ValueChanged<String?> onChanged;

  /// The semantic id prefix each chip's id is rooted at.
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          semantic(
            '$idPrefix.none',
            child: ChoiceChip(
              label: const Text('None'),
              selected: selectedCategoryId == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            semantic(
              '$idPrefix.${category.id}',
              child: ChoiceChip(
                avatar: Icon(
                  categoryIcon(category.icon),
                  color: Color(category.color),
                  size: 18,
                ),
                label: Text(category.name),
                selected: selectedCategoryId == category.id,
                onSelected: (_) => onChanged(category.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
