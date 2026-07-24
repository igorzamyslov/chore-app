/// The collapsed-by-default 'In the cart' checked-items section.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The checked-items section: a collapsed-by-default [ExpansionTile] headed
/// 'In the cart (N)', holding [tiles] (already-built tile widgets for every
/// checked item), with a 'Clear checked' button that calls [onClear]
/// immediately — no confirmation dialog (spec `docs/specs/ux-round-2.md`
/// B4: items are soft-deleted and suggestions make recovery one keystroke
/// away, so a confirm here would fail design-language rule 3).
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

  /// Called when the user taps 'Clear checked', to clear all checked items
  /// immediately.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Wrap, not Row: at accessibility text sizes the header text and the
    // Clear button don't fit side by side — the button flows to its own
    // line instead of squeezing the title into an awkward two-line wrap
    // (visual QA finding at AX2).
    return ExpansionTile(
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          semantic(
            'shopping.checked.header',
            child: Text(l10n.shoppingCartHeader(count)),
          ),
          semantic(
            'shopping.clear',
            child: TextButton(
              onPressed: onClear,
              child: Text(l10n.shoppingClearButton),
            ),
          ),
        ],
      ),
      children: tiles,
    );
  }
}
