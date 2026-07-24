/// The category add/edit bottom sheet: rename, icon, color, save, delete.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/features/categories/category_icons.dart';
import 'package:chore_app/features/settings/category_delete_dialog.dart';
import 'package:chore_app/features/settings/category_edit_validation.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the modal bottom sheet for adding a new category of [kind] (when
/// [category] is omitted) or editing an existing [category].
///
/// A new category defaults to the `'label'` icon — `categoryIcon`'s
/// fallback identifier, not itself one of [categoryIconIdentifiers], so the
/// icon grid starts with nothing selected — and the first of
/// [CategoryRepository.seedColors] not already used by an active category
/// of [kind] (wrapping back to the first color if every seed color is
/// taken).
Future<void> showCategoryEditSheet(
  BuildContext context, {
  required CategoryKind kind,
  Category? category,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _CategoryEditSheet(kind: kind, category: category),
  );
}

class _CategoryEditSheet extends ConsumerStatefulWidget {
  const _CategoryEditSheet({required this.kind, this.category});

  final CategoryKind kind;
  final Category? category;

  @override
  ConsumerState<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<_CategoryEditSheet> {
  late final TextEditingController _nameController;
  late String _icon;
  late int _color;
  CategoryNameError? _nameError;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _icon = category?.icon ?? 'label';
    _color = category?.color ?? _firstFreeColor();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<Category> get _currentCategories {
    final provider = widget.kind == CategoryKind.chore
        ? choreCategoriesProvider
        : shoppingCategoriesProvider;
    return ref.read(provider).value ?? const <Category>[];
  }

  int _firstFreeColor() {
    final usedColors = _currentCategories.map((c) => c.color).toSet();
    const seedColors = CategoryRepository.seedColors;
    return seedColors.firstWhere(
      (color) => !usedColors.contains(color),
      orElse: () => seedColors[_currentCategories.length % seedColors.length],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? l10n.categoryEditEditTitle : l10n.categoryEditNewTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          semantic(
            'settings.categories.name',
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.categoryEditNameLabel,
                errorText: _nameError == null
                    ? null
                    : l10n.categoryEditNameRequiredError,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.categoryEditIconLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _IconGrid(
            selected: _icon,
            onSelected: (value) => setState(() => _icon = value),
          ),
          const SizedBox(height: 24),
          Text(l10n.categoryEditColorLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _ColorSwatches(
            selected: _color,
            onSelected: (value) => setState(() => _color = value),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (_isEditing)
                semantic(
                  'settings.categories.delete',
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(l10n.commonDelete),
                  ),
                ),
              const Spacer(),
              semantic(
                'settings.categories.save',
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
    final nameError = validateCategoryName(name);
    if (nameError != null) {
      setState(() => _nameError = nameError);
      return;
    }
    final repo = ref.read(categoryRepositoryProvider);
    final existing = widget.category;
    if (existing != null) {
      await repo.updateCategory(
        existing.id,
        name: name,
        icon: _icon,
        color: _color,
      );
    } else {
      final householdId = ref.read(bootstrapProvider).requireValue;
      await repo.createCategory(
        householdId,
        kind: widget.kind,
        name: name,
        icon: _icon,
        color: _color,
        sortOrder: _currentCategories.length,
      );
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.category;
    if (existing == null) {
      return;
    }
    final confirmed = await showCategoryDeleteDialog(
      context,
      categoryName: existing.name,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(categoryRepositoryProvider).softDeleteCategory(existing.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

/// A 48dp-minimum tappable circular tile, used by both the icon grid and
/// the color swatches (design-language: touch targets >= 48dp, enforced
/// with sizing, not hope).
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: child)),
      ),
    );
  }
}

/// The icon picker: a wrapped grid of [categoryIconIdentifiers], each drawn
/// via `categoryIcon`. The selected tile is marked two ways — a filled
/// background AND a small check badge — so selection never rides on color
/// alone (`docs/specs/design-language.md` color-usage rules).
class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final identifier in categoryIconIdentifiers)
          semantic(
            'settings.categories.icon.$identifier',
            child: _PickerTile(
              isSelected: identifier == selected,
              onTap: () => onSelected(identifier),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    categoryIcon(identifier),
                    color: identifier == selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  if (identifier == selected)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Icon(
                        Icons.check_circle,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The color picker: a wrapped row of [CategoryRepository.seedColors]
/// swatches. The selected swatch is marked two ways — a contrasting border
/// ring AND a checkmark — so selection never rides on color alone.
class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (
          var index = 0;
          index < CategoryRepository.seedColors.length;
          index++
        )
          semantic(
            'settings.categories.color.$index',
            child: _ColorSwatch(
              color: Color(CategoryRepository.seedColors[index]),
              isSelected: CategoryRepository.seedColors[index] == selected,
              ringColor: onSurface,
              onTap: () => onSelected(CategoryRepository.seedColors[index]),
            ),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.ringColor,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final Color ringColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return _PickerTile(
      isSelected: false,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: ringColor, width: 2) : null,
        ),
        child: isSelected
            ? Icon(Icons.check, color: checkColor, size: 18)
            : null,
      ),
    );
  }
}
