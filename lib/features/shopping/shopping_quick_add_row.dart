/// The shopping list's pinned quick-add row, plus its type-ahead
/// suggestions.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/shopping/shopping_suggestions_list.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The pinned row above the shopping list: a text field plus a submit
/// button, with up to 8 type-ahead suggestions shown below it while typing
/// (spec `docs/specs/ux-round-2.md` B2).
///
/// Submitting (button tap, keyboard action, or tapping a suggestion) trims
/// the input and matches its normalized name against ACTIVE items in the
/// household (spec B3):
/// - an unchecked match exists → nothing is added; a snackbar says so.
/// - a checked match exists → it's unchecked (restored) instead of adding a
///   new row; a snackbar says so.
/// - no match → a new item is added, inheriting the most recent category
///   ever used for that name from history when the user didn't pick one
///   (a plain-text submit); a suggestion tap instead uses that suggestion's
///   own category verbatim.
///
/// The field clears and keeps focus after all three outcomes, so entry can
/// continue right away. Suggestions are re-queried on every keystroke via
/// `ShoppingRepository.suggestions` and disappear as soon as the field is
/// empty.
class ShoppingQuickAddRow extends ConsumerStatefulWidget {
  /// Creates the quick-add row.
  const ShoppingQuickAddRow({super.key});

  @override
  ConsumerState<ShoppingQuickAddRow> createState() =>
      _ShoppingQuickAddRowState();
}

class _ShoppingQuickAddRowState extends ConsumerState<ShoppingQuickAddRow> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<ShoppingSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: semantic(
                  'shopping.add.input',
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(hintText: l10n.shoppingAddHint),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              semantic(
                'shopping.add.submit',
                child: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.shoppingAddTooltip,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty)
          ShoppingSuggestionsList(
            suggestions: _suggestions,
            onTap: _selectSuggestion,
          ),
      ],
    );
  }

  void _onTextChanged() {
    unawaited(_updateSuggestions());
  }

  /// Re-queries suggestions for the field's current text, discarding the
  /// result if the text has since changed (e.g. it raced with a submit that
  /// cleared the field).
  Future<void> _updateSuggestions() async {
    final query = _controller.text;
    if (query.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
      return;
    }
    final householdId = ref.read(bootstrapProvider).requireValue;
    final results = await ref
        .read(shoppingRepositoryProvider)
        .suggestions(householdId, query);
    if (!mounted || _controller.text != query) {
      return;
    }
    setState(() => _suggestions = results);
  }

  Future<void> _submit() => _addOrRestore(_controller.text.trim());

  Future<void> _selectSuggestion(ShoppingSuggestion suggestion) {
    return _addOrRestore(
      suggestion.name,
      categoryId: suggestion.categoryId,
      isSuggestionTap: true,
    );
  }

  /// Implements the B3 duplicate-prevention branch shared by a typed submit
  /// and a suggestion tap. See the class doc for the three outcomes.
  Future<void> _addOrRestore(
    String name, {
    String? categoryId,
    bool isSuggestionTap = false,
  }) async {
    if (name.isEmpty) {
      return;
    }
    final householdId = ref.read(bootstrapProvider).requireValue;
    final repository = ref.read(shoppingRepositoryProvider);
    final normalizedName = normalizeShoppingItemName(name);

    final existing = await repository.findActiveByNormalizedName(
      householdId,
      normalizedName,
    );
    if (!mounted) {
      return;
    }

    if (existing != null) {
      if (existing.item.checkedAt == null) {
        _showSnackbar(AppLocalizations.of(context).shoppingAddAlreadyOnList);
      } else {
        await repository.setChecked(existing.item.id, checked: false);
        if (!mounted) {
          return;
        }
        _showSnackbar(AppLocalizations.of(context).shoppingAddMovedBack);
      }
    } else {
      final resolvedCategoryId = isSuggestionTap
          ? categoryId
          : await repository.mostRecentCategoryIdForNormalizedName(
              householdId,
              normalizedName,
            );
      if (!mounted) {
        return;
      }
      await repository.addItem(
        householdId,
        name: name,
        categoryId: resolvedCategoryId,
        addedBy: ref.read(actingMemberProvider)?.id,
      );
    }

    if (!mounted) {
      return;
    }
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _showSnackbar(String message) {
    showAppSnackbar(context, message: message);
  }
}
