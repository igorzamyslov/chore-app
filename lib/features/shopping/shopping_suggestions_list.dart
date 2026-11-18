/// Type-ahead suggestions shown under the shopping list's quick-add field.
library;

import 'dart:async';

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// How many suggestions the quick-add row asks for, on both the
/// focus-on-empty path (F1) and the type-ahead path (B2). See
/// `docs/specs/ui-shopping.md`, Amendment 2026-11-18: the screen space is
/// bounded by [ShoppingSuggestionsList]'s height cap, not by this count.
const shoppingSuggestionLimit = 20;

/// Renders [suggestions] (already ranked and limited by
/// `ShoppingRepository.suggestions`) as a wrap of tappable pill chips below
/// the quick-add field (spec `docs/specs/theme-v2.md` §3/§4.3: pill radius
/// 20, unselected style -- the app's shared `ChipThemeData` already gives
/// any [ActionChip] that look): each shows the item's name and, when its
/// most recent history row set one, its category's ICON ONLY, leading, in
/// the category's own color -- the name is carried as the icon's
/// `semanticLabel` rather than drawn, since a category name is regularly
/// longer than the item it describes.
///
/// **Height cap** (`docs/specs/ui-shopping.md`, Amendment 2026-11-18): the
/// wrap scrolls vertically inside an area as tall as its content but no
/// taller than [visibleRows] chip rows -- two full rows and half of a third,
/// so the cut row itself says "there is more". While content remains below,
/// the bottom [fadeExtent] fades out. A horizontal strip was rejected: a
/// horizontal drag on this screen belongs to the shell's tab `PageView`.
///
/// Tapping a chip calls [onTap] with that suggestion; the caller (the
/// quick-add row) adds it immediately, subject to the same duplicate
/// prevention as a typed submit. See `docs/specs/ux-round-2.md` B2/B3.
///
/// **Long-pressing a chip opens a one-entry menu, "Forget this
/// suggestion"** (persona finding F11), which calls [onForget]: a typo added
/// once used to stay proposed forever.
class ShoppingSuggestionsList extends StatefulWidget {
  /// Creates the suggestions list for [suggestions].
  const ShoppingSuggestionsList({
    required this.suggestions,
    required this.onTap,
    required this.onForget,
    this.query = '',
    super.key,
  });

  /// Chip rows visible before the area scrolls: two full, half of a third.
  static const visibleRows = 2.5;

  /// Height of the bottom fade shown while more chips sit below.
  static const fadeExtent = 24.0;

  /// The suggestions to render, in display order (already ranked/limited).
  final List<ShoppingSuggestion> suggestions;

  /// The field text [suggestions] were queried for. When it changes, the
  /// area scrolls back to the top; a re-query for the SAME text (after a
  /// chip tap) keeps the position, so several chips can be tapped in a row
  /// from the scrolled part.
  final String query;

  /// Called with the tapped suggestion.
  final ValueChanged<ShoppingSuggestion> onTap;

  /// Called with the suggestion the user chose to forget.
  final ValueChanged<ShoppingSuggestion> onForget;

  @override
  State<ShoppingSuggestionsList> createState() =>
      _ShoppingSuggestionsListState();
}

class _ShoppingSuggestionsListState extends State<ShoppingSuggestionsList> {
  static const _spacing = 8.0;

  /// The chip height before the first one has been measured: an
  /// [ActionChip] with the default padded tap target. Only the very first
  /// frame at a non-default text scale uses it.
  static const double _defaultChipHeight = kMinInteractiveDimension;

  final _scrollController = ScrollController();
  final GlobalKey _wrapKey = GlobalKey();
  double _chipHeight = _defaultChipHeight;
  bool _moreBelow = false;

  @override
  void didUpdateWidget(ShoppingSuggestionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Reads the laid-out height of the first chip, so the cap cuts mid-row
  /// at any text scale. Every chip in the wrap is the same height.
  void _measureChipHeight() {
    if (!mounted) {
      return;
    }
    final wrap = _wrapKey.currentContext?.findRenderObject();
    final first = wrap is RenderWrap ? wrap.firstChild : null;
    if (first == null || !first.hasSize) {
      return;
    }
    final height = first.size.height;
    if ((height - _chipHeight).abs() > 0.5) {
      setState(() => _chipHeight = height);
    }
  }

  /// Tracks whether chips remain below the visible part (the fade's cue).
  bool _onMetrics(ScrollMetrics metrics) {
    final moreBelow = metrics.extentAfter > 0.5;
    if (moreBelow != _moreBelow) {
      setState(() => _moreBelow = moreBelow);
    }
    // Stop here: the area's scrolling is not the list's. Bubbling on would
    // reach the Scaffold's scroll observer and tint the app bar as if the
    // list had scrolled under it.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureChipHeight());
    final suggestions = widget.suggestions;
    final maxHeight =
        _chipHeight * ShoppingSuggestionsList.visibleRows +
        _spacing * ShoppingSuggestionsList.visibleRows.floor();
    // The mask stays in the tree whether or not it fades: wrapping and
    // unwrapping the scroll view as `_moreBelow` flips would remount it and
    // throw away the scroll position the moment the user reached the end.
    final area = ShaderMask(
      // A mask, not a drawn element: the chips themselves fade out over the
      // bottom `fadeExtent`, whatever the ground behind them is. `dst`
      // ignores the shader, i.e. no fade.
      blendMode: _moreBelow ? BlendMode.dstIn : BlendMode.dst,
      shaderCallback: (bounds) {
        final fadeStart =
            (bounds.height - ShoppingSuggestionsList.fadeExtent) /
            bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, fadeStart.clamp(0, 1), 1],
        ).createShader(bounds);
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Wrap(
          key: _wrapKey,
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (var i = 0; i < suggestions.length; i++)
              _SuggestionChip(
                // Keyed by NAME, not position (field feedback 2026-08-07 C3):
                // tapping a chip adds that item, which re-ranks this list and
                // shifts every later chip up one slot. Without a key Flutter
                // matches chip elements positionally, so it reuses the tapped
                // chip's element for the NEXT suggestion -- and the in-flight
                // ink splash carries over, making the next proposal look like
                // it tapped itself. A name key makes the tapped element leave
                // with its own splash.
                key: ValueKey(suggestions[i].name),
                index: i,
                suggestion: suggestions[i],
                onTap: () => widget.onTap(suggestions[i]),
                onForget: () => widget.onForget(suggestions[i]),
              ),
          ],
        ),
      ),
    );
    return semantic(
      'shopping.suggestions',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) => _onMetrics(notification.metrics),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) =>
                  _onMetrics(notification.metrics),
              child: area,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.index,
    required this.suggestion,
    required this.onTap,
    required this.onForget,
    super.key,
  });

  final int index;
  final ShoppingSuggestion suggestion;
  final VoidCallback onTap;
  final VoidCallback onForget;

  /// Opens the one-entry "Forget this suggestion" menu at the chip.
  Future<void> _showForgetMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx - box.size.width,
      0,
    );
    final forget = await showMenu<bool>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<bool>(
          value: true,
          child: semantic(
            'shopping.suggestion.$index.forget',
            child: Text(AppLocalizations.of(context).shoppingSuggestionForget),
          ),
        ),
      ],
    );
    if (forget ?? false) {
      onForget();
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = suggestion.category;
    return semantic(
      'shopping.suggestion.$index',
      // A long-press-only detector: it claims no tap and no drag, so the
      // chip's own tap (add) and the list's vertical scroll are untouched.
      child: GestureDetector(
        onLongPress: () => unawaited(_showForgetMenu(context)),
        child: ActionChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (category != null) ...[
                // Icon only, and LEADING. Deliberately not `CategoryBadge`
                // (which is icon + name): a category name is regularly longer
                // than the item it describes -- "Haushaltswaren" against
                // "Milch" -- so on a chip it doubled the width and pushed the
                // useful half, the item name, out of a glanceable position.
                // Leading keeps the names left-aligned down the wrap, which is
                // what the eye scans.
                //
                // `semanticLabel` carries the category name that is no longer
                // drawn: an `Icon` without one is invisible to a screen
                // reader, so dropping the text would otherwise have removed
                // the category from the accessible tree entirely rather than
                // just from the pixels. The chip still reads
                // "<category>, <item>".
                Icon(
                  categoryIcon(category.icon),
                  color: categoryTone(context, category.color),
                  size: 16,
                  semanticLabel: category.name,
                ),
                const SizedBox(width: 6),
              ],
              Text(suggestion.name),
            ],
          ),
          onPressed: onTap,
        ),
      ),
    );
  }
}
