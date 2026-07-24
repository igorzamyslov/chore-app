/// The shopping list's pinned quick-add row.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The pinned row above the shopping list: a text field plus a submit
/// button that adds a new, uncategorized item.
///
/// Submitting (button tap or the keyboard's action button) trims the input;
/// an empty result adds nothing (no error, no row). A non-empty result adds
/// an uncategorized item via [shoppingRepositoryProvider], clears the field,
/// and keeps focus so another item can be typed right away.
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

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
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
    );
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    final householdId = ref.read(bootstrapProvider).requireValue;
    await ref
        .read(shoppingRepositoryProvider)
        .addItem(
          householdId,
          name: name,
          addedBy: ref.read(actingMemberProvider)?.id,
        );
    if (!mounted) {
      return;
    }
    _controller.clear();
    _focusNode.requestFocus();
  }
}
