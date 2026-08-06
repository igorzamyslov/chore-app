/// The collapsed-by-default 'In the cart' checked-items section.
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The checked-items section: collapses to one `surfaceContainerHigh` row
/// (spec `docs/specs/theme-v2.md` §4.3) -- a `shopping_basket` glyph, the
/// 'In the cart (N)' count, and the 'Put all back'/'Clear checked' actions --
/// which expands (a controlled [ExpansionTile]) to reveal [tiles]
/// (already-built row widgets for every checked item) gathered into one
/// hairline-separated card, matching the aisle cards above it. Neither
/// action is gated behind a confirmation dialog (spec
/// `docs/specs/ux-round-2.md` B4: items are soft-deleted and suggestions
/// make recovery one keystroke away, so a confirm here would fail
/// design-language rule 3).
///
/// [expanded] and [onExpansionChanged] hoist the expand/collapse state to
/// the caller (field feedback G1,
/// `docs/feedback/2026-08-01-field-feedback.md`): checking/unchecking an
/// item rebuilds and re-parents this section within the shopping list's
/// `ListView`, which can make a bare, uncontrolled `ExpansionTile` forget
/// whether it was open. Passing the current value back in as
/// `initiallyExpanded` on every build means the section's open/closed state
/// survives no matter how the surrounding list reshuffles it, as long as the
/// caller's own state survives (see `ShoppingListScreen`).
///
/// The caller only mounts this widget while there's at least one checked
/// item (see `docs/specs/ui-shopping.md`), so 'Clear checked' is always
/// shown here. Per the same contract, the caller resets [expanded] to
/// `false` once this section unmounts, so its *next* appearance always
/// starts collapsed — a deliberate, documented simplification: it's only
/// the "stay open while working inside an already-open section" case that
/// was broken, not "remember collapsed/expanded across separate shopping
/// trips".
class ShoppingCheckedSection extends StatelessWidget {
  /// Creates the section for [count] checked items, rendering [tiles].
  const ShoppingCheckedSection({
    required this.count,
    required this.tiles,
    required this.expanded,
    required this.onExpansionChanged,
    required this.onClear,
    required this.onUncheckAll,
    super.key,
  });

  /// The number of checked items, shown in the header.
  final int count;

  /// The already-built tile widgets for each checked item.
  final List<Widget> tiles;

  /// Whether the section is currently expanded, per the caller's hoisted
  /// state.
  final bool expanded;

  /// Called with the new expanded value whenever the user taps the section
  /// header to toggle it.
  final ValueChanged<bool> onExpansionChanged;

  /// Called when the user taps 'Clear checked', to clear all checked items
  /// immediately.
  final VoidCallback onClear;

  /// Called when the user taps 'Put all back', to uncheck every checked
  /// item immediately (field feedback G1).
  final VoidCallback onUncheckAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const Border.fromBorderSide(BorderSide.none),
        collapsedShape: const Border.fromBorderSide(BorderSide.none),
        leading: Icon(
          Icons.shopping_basket_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        // Wrap, not Row: at accessibility text sizes the header text and
        // the action buttons don't fit side by side — buttons flow to
        // their own line instead of squeezing the title into an awkward
        // two-line wrap (visual QA finding at AX2).
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            semantic(
              'shopping.checked.header',
              child: Text(l10n.shoppingCartHeader(count)),
            ),
            semantic(
              'shopping.uncheckAll',
              child: TextButton(
                onPressed: onUncheckAll,
                child: Text(l10n.shoppingUncheckAll),
              ),
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DepthCard(
              margin: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    tiles[i],
                    if (i < tiles.length - 1)
                      const Divider(height: 1, thickness: 1),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
