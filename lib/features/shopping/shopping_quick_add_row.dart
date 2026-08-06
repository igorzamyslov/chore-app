/// The shopping list's pinned quick-add row, plus its type-ahead
/// suggestions.
library;

import 'dart:async';

import 'package:chore_app/app/famdo_colors.dart';
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
/// `ShoppingRepository.suggestions`.
///
/// Focusing the field while it's still empty shows the top 5 suggestions by
/// the same ranking (field feedback F1,
/// `docs/feedback/2026-08-01-field-feedback.md`) — a quiet nudge toward
/// what's usually bought, before the user has typed anything. Typing a
/// prefix seamlessly narrows to the existing type-ahead behavior; clearing
/// the field back to empty while still focused returns to the top-5 view.
/// Losing focus always hides the list, however it got there.
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
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final famdo = famdoColors(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          // The quick-add pill (spec `docs/specs/theme-v2.md` §4.3): a
          // raised card -- `surfaceContainerLow` ground, `primaryOutline`
          // border, `lift` shadow -- containing a leading search glyph, the
          // borderless text field (the card itself is the border), and the
          // trailing filled submit square. Built by hand rather than via
          // `DepthCard` because that shared widget hardcodes an
          // `outlineVariant` border; this card needs the accent
          // `primaryOutline` one instead.
          child: Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              border: Border.all(color: famdo.primaryOutline),
              boxShadow: famdo.lift,
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: semantic(
                    'shopping.add.input',
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.done,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: l10n.shoppingAddHint,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                      // Bug 2 (field feedback round 2,
                      // docs/feedback/2026-08-01-field-feedback.md):
                      // focus-gain only fires on a focus CHANGE, so
                      // returning to this tab with the field still
                      // focused, or tapping an already-focused field,
                      // fired nothing. An explicit onTap covers both.
                      onTap: () => unawaited(_updateSuggestions()),
                    ),
                  ),
                ),
                Semantics(
                  identifier: 'shopping.add.submit',
                  container: true,
                  button: true,
                  label: l10n.shoppingAddTooltip,
                  child: Tooltip(
                    message: l10n.shoppingAddTooltip,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Material(
                        color: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _submit,
                          child: Center(
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.add,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

  /// Shows the top-5 focus-suggestions (F1) when focus is gained while the
  /// field is still empty; hides whatever's showing as soon as focus is
  /// lost, regardless of how it got there (typed prefix or empty-focus).
  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      unawaited(_updateSuggestions());
    } else if (_suggestions.isNotEmpty) {
      setState(() => _suggestions = const []);
    }
  }

  /// Re-queries suggestions for the field's current text, discarding the
  /// result if the text or focus state has since changed (e.g. it raced
  /// with a submit that cleared the field, or with a blur).
  ///
  /// An empty query only queries (the F1 top-5) while the field still has
  /// focus; an empty, unfocused field hides the list instead, same as
  /// clearing the text always did.
  Future<void> _updateSuggestions() async {
    final query = _controller.text;
    if (query.isEmpty && !_focusNode.hasFocus) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = const []);
      }
      return;
    }
    final householdId = ref.read(bootstrapProvider).requireValue;
    final results = await ref
        .read(shoppingRepositoryProvider)
        .suggestions(householdId, query, limit: query.isEmpty ? 5 : 8);
    if (!mounted ||
        _controller.text != query ||
        (query.isEmpty && !_focusNode.hasFocus)) {
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
    // Bug 4 (field feedback round 2,
    // docs/feedback/2026-08-01-field-feedback.md): a suggestion tap never
    // types anything, so the controller is already empty here and
    // `clear()` above doesn't notify `_onTextChanged` — without this
    // explicit refresh the just-added item would stay proposed. Calling it
    // unconditionally (typed submit and suggestion tap alike) refreshes
    // every path uniformly; the newly active item is now excluded by the
    // empty-prefix rule, so it drops out and the next candidate moves in.
    unawaited(_updateSuggestions());
  }

  void _showSnackbar(String message) {
    showAppSnackbar(context, message: message);
  }
}
