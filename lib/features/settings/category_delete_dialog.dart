/// The delete-confirmation dialog for a category.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A confirmed category delete: where the chores/items that used it go.
class CategoryDeleteChoice {
  /// Creates a choice; [moveToCategoryId] `null` means "Uncategorized".
  const CategoryDeleteChoice({this.moveToCategoryId});

  /// The category the deleted one's chores/items move to, or `null` to
  /// leave them uncategorized.
  final String? moveToCategoryId;
}

/// Shows a confirmation dialog for deleting the category named
/// [categoryName], resolving to the [CategoryDeleteChoice] on confirm, or
/// `null` if cancelled or dismissed.
///
/// Deleting a category detaches it from every active chore/shopping item
/// that references it — costly enough to confirm, per
/// `docs/specs/design-language.md` rule 3. [kind] picks chore-worded or
/// shopping-worded copy (a category only ever references one or the
/// other); [referenceCount] must already be resolved by the caller — this
/// dialog never queries the database itself — and is the exact number of
/// active rows the delete will move, per
/// `CategoryRepository.countActiveReferences`. `referenceCount == 0` reads
/// as a distinct, lower-stakes sentence rather than a "0 chores" plural.
///
/// When something uses the category, a "Move them to" dropdown (persona
/// review 2026-10-06 C10) offers "Uncategorized" (the default, and the only
/// outcome before) plus [moveTargets] — the other active categories of the
/// same kind — so deleting can merge one category into another.
Future<CategoryDeleteChoice?> showCategoryDeleteDialog(
  BuildContext context, {
  required String categoryName,
  required CategoryKind kind,
  required int referenceCount,
  List<Category> moveTargets = const [],
}) {
  return showDialog<CategoryDeleteChoice>(
    context: context,
    builder: (dialogContext) => _CategoryDeleteDialog(
      categoryName: categoryName,
      kind: kind,
      referenceCount: referenceCount,
      moveTargets: moveTargets,
    ),
  );
}

class _CategoryDeleteDialog extends StatefulWidget {
  const _CategoryDeleteDialog({
    required this.categoryName,
    required this.kind,
    required this.referenceCount,
    required this.moveTargets,
  });

  final String categoryName;
  final CategoryKind kind;
  final int referenceCount;
  final List<Category> moveTargets;

  @override
  State<_CategoryDeleteDialog> createState() => _CategoryDeleteDialogState();
}

class _CategoryDeleteDialogState extends State<_CategoryDeleteDialog> {
  String? _moveToCategoryId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoryName = widget.categoryName;
    final body = switch ((widget.kind, widget.referenceCount)) {
      (CategoryKind.chore, 0) => l10n.categoryDeleteDialogBodyChoresZero(
        categoryName,
      ),
      (CategoryKind.chore, final count) =>
        l10n.categoryDeleteDialogBodyChoresCount(categoryName, count),
      (CategoryKind.shopping, 0) => l10n.categoryDeleteDialogBodyShoppingZero(
        categoryName,
      ),
      (CategoryKind.shopping, final count) =>
        l10n.categoryDeleteDialogBodyShoppingCount(categoryName, count),
    };
    return AlertDialog(
      title: Text(l10n.categoryDeleteDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          if (widget.referenceCount > 0) ...[
            const SizedBox(height: 16),
            semantic(
              'settings.categories.delete.moveTo',
              child: DropdownButtonFormField<String?>(
                initialValue: _moveToCategoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.categoryDeleteMoveTo,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    child: semantic(
                      'settings.categories.delete.moveTo.none',
                      child: Text(l10n.categoryDeleteMoveToNone),
                    ),
                  ),
                  for (final category in widget.moveTargets)
                    DropdownMenuItem<String?>(
                      value: category.id,
                      child: semantic(
                        'settings.categories.delete.moveTo.${category.id}',
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _moveToCategoryId = value),
              ),
            ),
          ],
        ],
      ),
      actions: [
        semantic(
          'settings.categories.delete.cancel',
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
        ),
        semantic(
          'settings.categories.delete.confirm',
          child: TextButton(
            onPressed: () => Navigator.pop(
              context,
              CategoryDeleteChoice(moveToCategoryId: _moveToCategoryId),
            ),
            child: Text(l10n.commonDelete),
          ),
        ),
      ],
    );
  }
}
