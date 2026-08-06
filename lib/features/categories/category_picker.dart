/// Selectable horizontal chip row for choosing a category (or none).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/settings/manage_categories_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A horizontally-scrollable row of [ChoiceChip]s: one 'None' chip plus one
/// chip per entry in [categories], each showing its icon and name in its own
/// color, followed by a trailing "edit categories" icon button.
///
/// Every chip is individually wrapped with a stable identifier:
/// `'$idPrefix.none'` for the 'None' chip, `'$idPrefix.${category.id}'` for
/// each category. This lets the same widget serve both the chore form's
/// `chore_form.category*` ids and a future shopping form's own prefix. The
/// trailing button always uses the fixed id `category_picker.manage`, since
/// only one picker is ever on screen at a time.
///
/// Field feedback round 3 ("categories are managed in Settings, far from
/// where they're used"): the button pushes the existing manage-categories
/// screen, opened directly on [kind] so the right section shows first. The
/// Settings entry point is unchanged and still defaults to chore categories.
///
/// Callers own [selectedCategoryId]; if the category it refers to is
/// deleted while the manage screen is open, this widget does not itself
/// reset it — see `ChoreFormScreen`/`_ShoppingEditSheetState` for the
/// fallback-to-'None' logic that keeps the two in sync with [categories].
class CategoryPicker extends StatelessWidget {
  /// Creates a picker over [categories], currently selecting
  /// [selectedCategoryId] (`null` for 'None'), reporting changes via
  /// [onChanged], with semantic ids rooted at [idPrefix]. [kind] identifies
  /// which section of the manage-categories screen the trailing button
  /// opens.
  const CategoryPicker({
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
    required this.idPrefix,
    required this.kind,
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

  /// Which kind of categories [categories] holds, forwarded to the
  /// manage-categories screen so it opens on the matching section.
  final CategoryKind kind;

  @override
  Widget build(BuildContext context) {
    // The manage button is PINNED outside the scrollable chip row (review
    // hardening of the round-3 fix): its whole purpose is an
    // always-visible in-context entry point, and inside the scroll area
    // it disappears behind 7-8 seeded chips on narrow screens.
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                semantic(
                  '$idPrefix.none',
                  child: ChoiceChip(
                    label: Text(
                      AppLocalizations.of(context).categoryPickerNone,
                    ),
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
                        color: categoryTone(context, category.color),
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
          ),
        ),
        semantic(
          'category_picker.manage',
          child: IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: AppLocalizations.of(context).categoryPickerManageTooltip,
            onPressed: () => _openManageCategories(context),
          ),
        ),
      ],
    );
  }

  Future<void> _openManageCategories(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManageCategoriesScreen(initialKind: kind),
      ),
    );
  }
}
