/// The category management screen (spec `docs/specs/ux-round-2.md` B1):
/// drag-to-reorder, rename, re-icon/recolor, add, and delete categories of
/// a chosen kind.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/settings/category_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages the active categories of one [CategoryKind] at a time, switched
/// via a segmented control.
///
/// The chore and shopping lists both already sort by `sort_order`, so a
/// drag reorder here is reflected there without any further wiring.
class ManageCategoriesScreen extends ConsumerStatefulWidget {
  /// Creates the manage-categories screen, opening on [initialKind]
  /// (defaulting to chore categories — the Settings entry point never
  /// passes one). The category pickers (feedback round 3) pass their own
  /// kind so the screen opens already showing the relevant section.
  const ManageCategoriesScreen({
    this.initialKind = CategoryKind.chore,
    super.key,
  });

  /// The [CategoryKind] section shown first; the segmented control still
  /// lets the user switch to the other one from there.
  final CategoryKind initialKind;

  @override
  ConsumerState<ManageCategoriesScreen> createState() =>
      _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState
    extends ConsumerState<ManageCategoriesScreen> {
  late CategoryKind _kind;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  StreamProvider<List<Category>> get _activeProvider =>
      _kind == CategoryKind.chore
      ? choreCategoriesProvider
      : shoppingCategoriesProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(_activeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageCategoriesTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<CategoryKind>(
              segments: [
                ButtonSegment(
                  value: CategoryKind.chore,
                  label: semantic(
                    'settings.categories.kind.chore',
                    child: Text(l10n.manageCategoriesKindChore),
                  ),
                ),
                ButtonSegment(
                  value: CategoryKind.shopping,
                  label: semantic(
                    'settings.categories.kind.shopping',
                    child: Text(l10n.manageCategoriesKindShopping),
                  ),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) {
                setState(() => _kind = selection.first);
              },
            ),
          ),
          Expanded(
            child: categoriesAsync.when(
              data: (categories) => categories.isEmpty
                  ? const _EmptyState()
                  : _CategoryList(
                      key: ValueKey(_kind),
                      categories: categories,
                      onReorder: (oldIndex, newIndex) =>
                          _reorder(categories, oldIndex, newIndex),
                      onTapCategory: (category) => showCategoryEditSheet(
                        context,
                        kind: _kind,
                        category: category,
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  _ErrorState(onRetry: () => ref.invalidate(_activeProvider)),
            ),
          ),
        ],
      ),
      floatingActionButton: semantic(
        'settings.categories.add',
        child: FloatingActionButton(
          onPressed: () => showCategoryEditSheet(context, kind: _kind),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _reorder(List<Category> categories, int oldIndex, int newIndex) {
    // `onReorderItem` (unlike the deprecated `onReorder`) already adjusts
    // `newIndex` for the removed item at `oldIndex`, so no manual "minus
    // one when moving down" correction is needed here.
    final updated = List<Category>.of(categories);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    final householdId = ref.read(bootstrapProvider).requireValue;
    unawaited(
      ref.read(categoryRepositoryProvider).reorderCategories(
        householdId,
        _kind,
        [
          for (final category in updated) category.id,
        ],
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.onReorder,
    required this.onTapCategory,
    super.key,
  });

  final List<Category> categories;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<Category> onTapCategory;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryRow(
          key: ValueKey(category.id),
          category: category,
          index: index,
          onTap: () => onTapCategory(category),
        );
      },
      onReorderItem: onReorder,
    );
  }
}

/// One category row: a drag handle (>= 48dp target), its icon + name in the
/// category's color, tappable to open the edit sheet.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.index,
    required this.onTap,
    super.key,
  });

  final Category category;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryTone(context, category.color);
    return semantic(
      'settings.categories.${category.id}',
      child: Row(
        children: [
          // The drag handle is a sibling of the tappable area below, not a
          // descendant of its `InkWell` — nesting it inside would put an
          // `ImmediateMultiDragGestureRecognizer` and a `TapGestureRecognizer`
          // in the same gesture arena for the same pointer, and the tap
          // recognizer can end up winning drags started on the handle.
          semantic(
            'settings.categories.${category.id}.drag',
            child: ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.drag_indicator),
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(categoryIcon(category.icon), color: color),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          category.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.label_outline,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          semantic(
            'settings.categories.empty',
            child: Text(
              AppLocalizations.of(context).manageCategoriesEmptyState,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.manageCategoriesErrorMessage),
          const SizedBox(height: 8),
          semantic(
            'settings.categories.error.retry',
            child: OutlinedButton(
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ),
        ],
      ),
    );
  }
}
