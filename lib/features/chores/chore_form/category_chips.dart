/// The chore form's own category chip row (spec `docs/specs/theme-v2.md`
/// §4.4 item 6): a thin, purpose-specific reimplementation of
/// `lib/features/categories/category_picker.dart`'s `CategoryPicker`, whose
/// chips carry a Material-icon avatar rather than the flat `categoryTone`
/// dot this wave calls for.
///
/// Duplicated rather than changing the shared `CategoryPicker` widget:
/// that widget is also used by the shopping edit sheet
/// (`lib/features/shopping/shopping_edit_sheet.dart`), which is out of this
/// wave's scope. Ids and behavior mirror it exactly --
/// `chore_form.category.none`, `chore_form.category.<id>`, and the fixed
/// `category_picker.manage` -- so every existing chore-form test keeps
/// passing unchanged.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/settings/manage_categories_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A horizontally-scrollable row of category [ChoiceChip]s (a 'None' chip
/// plus one per entry in [categories]), each carrying an 8dp `categoryTone`
/// dot before its name, followed by a trailing "edit categories" button.
class ChoreFormCategoryChips extends StatelessWidget {
  /// Creates the chore form's category chip row.
  const ChoreFormCategoryChips({
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
    super.key,
  });

  /// The selectable categories, in display order.
  final List<Category> categories;

  /// The currently-selected category id, or `null` for 'None'.
  final String? selectedCategoryId;

  /// Called with the newly-selected category id (`null` for 'None').
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // The manage button is pinned outside the scrollable chip row, mirroring
    // CategoryPicker's own review-hardened layout: its whole purpose is an
    // always-visible in-context entry point, and inside the scroll area it
    // disappears behind several seeded chips on narrow screens.
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                semantic(
                  'chore_form.category.none',
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
                    'chore_form.category.${category.id}',
                    child: ChoiceChip(
                      avatar: _CategoryDot(
                        color: categoryTone(context, category.color),
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
      MaterialPageRoute<void>(builder: (_) => const ManageCategoriesScreen()),
    );
  }
}

/// The 8dp `categoryTone` dot drawn before a category chip's name (spec
/// `docs/specs/theme-v2.md` §4.4 item 6), replacing `CategoryPicker`'s
/// Material-icon avatar in this form.
class _CategoryDot extends StatelessWidget {
  const _CategoryDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
