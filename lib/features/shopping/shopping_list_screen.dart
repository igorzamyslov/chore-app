/// The shopping list screen (this feature's tab).
library;

import 'package:chore_app/app/depth_variant.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/shopping/shopping_category_header.dart';
import 'package:chore_app/features/shopping/shopping_checked_section.dart';
import 'package:chore_app/features/shopping/shopping_edit_sheet.dart';
import 'package:chore_app/features/shopping/shopping_item_tile.dart';
import 'package:chore_app/features/shopping/shopping_quick_add_row.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists the household's shared shopping list: a pinned quick-add row above
/// unchecked items (grouped by category, in repository order) and a
/// collapsed-by-default checked section.
class ShoppingListScreen extends ConsumerWidget {
  /// Creates the shopping list screen.
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(shoppingItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).shoppingTabLabel),
      ),
      body: Column(
        children: [
          const ShoppingQuickAddRow(),
          Expanded(
            child: itemsAsync.when(
              // The `glassCards` background wash sits behind the list
              // only, not the quick-add row above it or loading/error
              // placeholders — see DepthBackground's doc.
              data: (items) => DepthBackground(
                child: _Body(
                  items: items,
                  onCheckedChanged: (id, {required checked}) =>
                      _setChecked(ref, id, checked: checked),
                  onTapItem: (item) =>
                      showShoppingEditSheet(context, item: item),
                  onClear: () => _clearChecked(ref),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorState(
                onRetry: () => ref.invalidate(shoppingItemsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setChecked(WidgetRef ref, String id, {required bool checked}) {
    return ref
        .read(shoppingRepositoryProvider)
        .setChecked(id, checked: checked);
  }

  Future<void> _clearChecked(WidgetRef ref) {
    final householdId = ref.read(bootstrapProvider).requireValue;
    return ref.read(shoppingRepositoryProvider).clearChecked(householdId);
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.onCheckedChanged,
    required this.onTapItem,
    required this.onClear,
  });

  final List<ShoppingItemWithCategory> items;
  final void Function(String id, {required bool checked}) onCheckedChanged;
  final ValueChanged<ShoppingItemWithCategory> onTapItem;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final unchecked = [
      for (final item in items)
        if (item.item.checkedAt == null) item,
    ];
    final checked = [
      for (final item in items)
        if (item.item.checkedAt != null) item,
    ];

    if (unchecked.isEmpty && checked.isEmpty) {
      return const Center(child: _EmptyMessage());
    }

    final children = <Widget>[
      if (unchecked.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: _EmptyMessage()),
        )
      else
        ..._groupedTiles(unchecked),
      if (checked.isNotEmpty)
        ShoppingCheckedSection(
          count: checked.length,
          tiles: [for (final item in checked) _tileFor(item)],
          onClear: onClear,
        ),
    ];

    return ListView(children: children);
  }

  /// Builds a category header before every run of same-category items,
  /// preserving [unchecked]'s existing (repository-sorted) order — never
  /// re-sorting client-side.
  List<Widget> _groupedTiles(List<ShoppingItemWithCategory> unchecked) {
    final children = <Widget>[];
    String? previousCategoryId;
    var isFirstGroup = true;
    for (final item in unchecked) {
      final categoryId = item.item.categoryId;
      if (isFirstGroup || categoryId != previousCategoryId) {
        children.add(ShoppingCategoryHeader(category: item.category));
        previousCategoryId = categoryId;
        isFirstGroup = false;
      }
      children.add(_tileFor(item));
    }
    return children;
  }

  Widget _tileFor(ShoppingItemWithCategory item) {
    return ShoppingItemTile(
      key: ValueKey(item.item.id),
      item: item,
      onCheckedChanged: (value) =>
          onCheckedChanged(item.item.id, checked: value),
      onTap: () => onTapItem(item),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.shopping_cart_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        semantic(
          'shopping.empty',
          child: DepthTextBackdrop(
            child: Text(
              AppLocalizations.of(context).shoppingEmptyState,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ],
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
          Text(l10n.shoppingErrorMessage),
          const SizedBox(height: 8),
          semantic(
            'shopping.error.retry',
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
