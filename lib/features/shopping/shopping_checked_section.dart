/// The collapsed-by-default 'In the cart' checked-items section.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/shopping/shopping_clear_dialog.dart';
import 'package:flutter/material.dart';

/// The checked-items section: a collapsed-by-default [ExpansionTile] headed
/// 'In the cart (N)', holding [tiles] (already-built tile widgets for every
/// checked item), with a 'Clear checked' button that confirms via
/// [showClearCheckedDialog] before calling [onClear].
///
/// The caller only mounts this widget while there's at least one checked
/// item (see `docs/specs/ui-shopping.md`), so 'Clear checked' is always
/// shown here.
class ShoppingCheckedSection extends StatelessWidget {
  /// Creates the section for [count] checked items, rendering [tiles].
  const ShoppingCheckedSection({
    required this.count,
    required this.tiles,
    required this.onClear,
    super.key,
  });

  /// The number of checked items, shown in the header.
  final int count;

  /// The already-built tile widgets for each checked item.
  final List<Widget> tiles;

  /// Called after the user confirms clearing all checked items.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: semantic(
              'shopping.checked.header',
              child: Text('In the cart ($count)'),
            ),
          ),
          semantic(
            'shopping.clear',
            child: TextButton(
              onPressed: () => _confirmClear(context),
              child: const Text('Clear checked'),
            ),
          ),
        ],
      ),
      children: tiles,
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showClearCheckedDialog(context, count: count);
    if (confirmed) {
      onClear();
    }
  }
}
