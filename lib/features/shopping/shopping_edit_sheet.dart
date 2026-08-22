/// The item edit bottom sheet: rename, adjust quantity/category, or delete.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/categories/category_picker.dart';
import 'package:chore_app/features/shopping/shopping_delete.dart';
import 'package:chore_app/features/shopping/shopping_edit_validation.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the modal bottom sheet for editing [item]: name, quantity/note,
/// and category, plus save/delete actions.
Future<void> showShoppingEditSheet(
  BuildContext context, {
  required ShoppingItemWithCategory item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ShoppingEditSheet(item: item),
  );
}

class _ShoppingEditSheet extends ConsumerStatefulWidget {
  const _ShoppingEditSheet({required this.item});

  final ShoppingItemWithCategory item;

  @override
  ConsumerState<_ShoppingEditSheet> createState() => _ShoppingEditSheetState();
}

class _ShoppingEditSheetState extends ConsumerState<_ShoppingEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late String? _categoryId;
  ItemNameError? _nameError;

  @override
  void initState() {
    super.initState();
    final item = widget.item.item;
    _nameController = TextEditingController(text: item.name);
    _quantityController = TextEditingController(text: item.quantityNote ?? '');
    _categoryId = item.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(shoppingCategoriesProvider).value ?? const [];
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final l10n = AppLocalizations.of(context);

    // Same fallback as the chore form's picker (feedback round 3): the
    // picker's "edit categories" button can push the manage-categories
    // screen and come back having deleted the item's currently-selected
    // category. `shoppingCategoriesProvider` only lists active categories,
    // so drop back to 'None' when the selected id is no longer among them.
    ref.listen<AsyncValue<List<Category>>>(shoppingCategoriesProvider, (
      _,
      next,
    ) {
      final active = next.value;
      if (active == null) {
        return;
      }
      if (_categoryId != null && !active.any((c) => c.id == _categoryId)) {
        setState(() => _categoryId = null);
      }
    });

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          semantic(
            'shopping.edit.name',
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.shoppingEditNameLabel,
                errorText: _nameError == null
                    ? null
                    : l10n.shoppingEditNameRequiredError,
              ),
            ),
          ),
          const SizedBox(height: 16),
          semantic(
            'shopping.edit.quantity',
            child: TextField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: l10n.shoppingEditQuantityLabel,
              ),
            ),
          ),
          const SizedBox(height: 16),
          semantic(
            'shopping.edit.category',
            child: CategoryPicker(
              categories: categories,
              selectedCategoryId: _categoryId,
              onChanged: (value) => setState(() => _categoryId = value),
              idPrefix: 'shopping.edit.category',
              kind: CategoryKind.shopping,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              semantic(
                'shopping.edit.delete',
                child: TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(l10n.commonDelete),
                ),
              ),
              const Spacer(),
              semantic(
                'shopping.edit.save',
                child: FilledButton(
                  onPressed: _save,
                  child: Text(l10n.commonSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final nameError = validateItemName(name);
    if (nameError != null) {
      setState(() => _nameError = nameError);
      return;
    }
    final quantityNote = _quantityController.text.trim();
    await ref
        .read(shoppingRepositoryProvider)
        .updateItem(
          widget.item.item.id,
          name: name,
          quantityNote: Value(quantityNote.isEmpty ? null : quantityNote),
          categoryId: Value(_categoryId),
        );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    // The snackbar is shown (and this sheet popped) before the row
    // disappears from view, so the undo mirrors the chores undo tone (spec
    // `docs/specs/polish-round-1.md` C3): soft delete makes UNDO a plain
    // restore, clearing `deleted_at`. The logic itself lives in
    // `shopping_delete.dart`, shared with swipe-to-delete (D-2) and the
    // long-press menu's Delete row (D-3) — this button is one of three
    // doors into exactly one behavior.
    await deleteShoppingItemWithUndo(
      context,
      ref,
      itemId: widget.item.item.id,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
