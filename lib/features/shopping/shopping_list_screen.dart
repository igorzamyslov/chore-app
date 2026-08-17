/// The shopping list screen (this feature's tab).
library;

import 'dart:async';

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/shopping/shopping_category_header.dart';
import 'package:chore_app/features/shopping/shopping_checked_section.dart';
import 'package:chore_app/features/shopping/shopping_delete.dart';
import 'package:chore_app/features/shopping/shopping_edit_sheet.dart';
import 'package:chore_app/features/shopping/shopping_item_action_sheet.dart';
import 'package:chore_app/features/shopping/shopping_item_tile.dart';
import 'package:chore_app/features/shopping/shopping_quick_add_row.dart';
import 'package:chore_app/features/sync/sync_health_banner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists the household's shared shopping list: a pinned quick-add row above
/// unchecked items (grouped by category, in repository order) and a
/// collapsed-by-default checked section.
class ShoppingListScreen extends ConsumerStatefulWidget {
  /// Creates the shopping list screen.
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  /// Whether the checked-items ('In the cart') section is expanded.
  ///
  /// Hoisted here rather than left as an uncontrolled `ExpansionTile`'s own
  /// internal state (field feedback G1,
  /// `docs/feedback/2026-08-01-field-feedback.md`): checking/unchecking an
  /// item rebuilds and re-parents `ShoppingCheckedSection` within the
  /// `ListView` below, which can reset a bare `ExpansionTile`'s expansion.
  /// This screen stays mounted for the tab's entire lifetime once first
  /// visited (each page of the `PageView` in `lib/app/app_shell.dart` is
  /// kept alive), so this field survives every such rebuild. Reset to
  /// `false` in [build] whenever the section itself unmounts (no checked
  /// items left) — its next appearance always starts collapsed, by design.
  bool _cartExpanded = false;

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(shoppingItemsProvider);
    // C1 (spec docs/specs/sync-freshness.md §2.3): same linked-AND-signed-in
    // gate as the chores list -- see chores_list_screen.dart's matching
    // comment and syncEngineProvider's own doc comment
    // (lib/app/providers.dart) for why.
    final syncLinked = ref.watch(syncEngineProvider) is! NoopSyncEngine;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).shoppingTabLabel),
      ),
      body: Column(
        children: [
          // This screen's only banner (backlog D-5, spec
          // `docs/specs/sync-freshness.md` §2.5), self-hiding to
          // `SizedBox.shrink()` whenever sync looks healthy — which is
          // always, for an unlinked household.
          //
          // ABOVE the quick-add row, not below it: the warning is about
          // whether what you are here to type will reach the person you are
          // shopping for, so it has to be readable BEFORE the field, not
          // after it. Deliberately not lifted into a `_BannerRegion` like
          // the chores list's (`lib/features/chores/chores_list_screen.dart`)
          // — one member does not need a region. If a second banner ever
          // lands on this screen, lift both into one, follow that region's
          // documented contract (every member self-hides; order by urgency
          // to the person on screen right now), and keep this one above the
          // quick-add row for the reason above.
          const SyncHealthBanner(),
          const ShoppingQuickAddRow(),
          Expanded(
            // Bug 3 (field feedback round 2,
            // docs/feedback/2026-08-01-field-feedback.md): the quick-add
            // field keeps focus after F1's focus-suggestions appear, so the
            // list stayed open while the user worked the list underneath.
            // Unfocusing on a user-driven scroll dismisses it (the existing
            // blur path already hides the list); only `ScrollStartNotification`
            // with non-null `dragDetails` is a real user drag, so
            // programmatic scrolls and overscroll glow are ignored.
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                return false;
              },
              child: itemsAsync.when(
                data: (items) {
                  final hasChecked = items.any(
                    (item) => item.item.checkedAt != null,
                  );
                  if (!hasChecked && _cartExpanded) {
                    // The section only mounts while ≥1 item is checked;
                    // once it unmounts, reset so it starts collapsed next
                    // time (documented behavior above).
                    _cartExpanded = false;
                  }
                  final body = _Body(
                    items: items,
                    cartExpanded: _cartExpanded,
                    onCartExpansionChanged: (value) =>
                        setState(() => _cartExpanded = value),
                    onCheckedChanged: (id, {required checked}) {
                      // Bug 3: checking/unchecking an item is also "working
                      // the list" — dismiss the suggestions the same way.
                      FocusManager.instance.primaryFocus?.unfocus();
                      unawaited(_setChecked(ref, id, checked: checked));
                    },
                    onTapItem: (item) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      unawaited(showShoppingEditSheet(context, item: item));
                    },
                    onLongPressItem: (item) => unawaited(_openMenu(item)),
                    onSwipeDeleteItem: (id) => unawaited(
                      deleteShoppingItemWithUndo(context, ref, itemId: id),
                    ),
                    onClear: () => unawaited(
                      _clearChecked(
                        ref,
                        // Captured NOW, before the write: T1.4's undo must
                        // restore exactly the items this tap cleared, not
                        // whatever happens to be checked when Undo is later
                        // tapped (checking a new item in between must not
                        // grow what Undo restores).
                        [
                          for (final item in items)
                            if (item.item.checkedAt != null) item.item.id,
                        ],
                      ),
                    ),
                    onUncheckAll: () => _uncheckAll(ref),
                  );
                  if (!syncLinked) {
                    return body;
                  }
                  // Success is silent (spec §2.3): the list simply updates,
                  // which is the platform convention -- no snackbar here.
                  return semantic(
                    'shopping.refresh',
                    child: RefreshIndicator(
                      // Field feedback 2026-08-07 C1 -- see the matching
                      // comment on the chores list for why `displacement`
                      // is the only available lever here.
                      displacement: 88,
                      onRefresh: () => _refresh(context, ref),
                      child: body,
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _ErrorState(
                  onRetry: () => ref.invalidate(shoppingItemsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setChecked(
    WidgetRef ref,
    String id, {
    required bool checked,
  }) async {
    await ref.read(shoppingRepositoryProvider).setChecked(id, checked: checked);
    // C3 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
    // haptic feedback, not animation -- doesn't touch the "no custom
    // animation" rule (design-language.md's Motion bullet) or E2E
    // determinism, so a future reader shouldn't "fix" this away. Fired here,
    // once the write is confirmed, rather than in the tile's onTap, so it
    // fires exactly once per real check/uncheck.
    unawaited(HapticFeedback.selectionClick());
  }

  /// Clears every checked item, then shows an undo snackbar restoring
  /// exactly [checkedIds] (spec T1.4) -- unlike every other delete-like
  /// action in the app, this bulk one previously had no undo of its own.
  Future<void> _clearChecked(WidgetRef ref, List<String> checkedIds) async {
    final householdId = ref.read(bootstrapProvider).requireValue;
    final repository = ref.read(shoppingRepositoryProvider);
    await repository.clearChecked(householdId);
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    showAppSnackbar(
      context,
      message: l10n.shoppingClearedSnackbar(checkedIds.length),
      action: SnackBarAction(
        label: l10n.shoppingClearedUndo,
        onPressed: () => unawaited(repository.restoreItems(checkedIds)),
      ),
    );
  }

  Future<void> _uncheckAll(WidgetRef ref) {
    final householdId = ref.read(bootstrapProvider).requireValue;
    return ref.read(shoppingRepositoryProvider).uncheckAll(householdId);
  }

  /// Opens the long-press action sheet for [item] and acts on the chosen
  /// [ShoppingItemMenuAction] (backlog D-3) -- currently just Delete,
  /// reusing the same `deleteShoppingItemWithUndo` every other delete path
  /// calls (see `shopping_delete.dart`). Takes no explicit `context`/`ref`
  /// params -- uses the State's own ambient values, matching
  /// `chores_list_screen.dart`'s `_openMenu(OccurrenceWithChore occurrence)`
  /// precedent exactly.
  Future<void> _openMenu(ShoppingItemWithCategory item) async {
    final action = await showShoppingItemActionSheet(context);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ShoppingItemMenuAction.delete:
        await deleteShoppingItemWithUndo(context, ref, itemId: item.item.id);
    }
  }
}

/// Runs a USER-INITIATED sync and reports failure (spec
/// `docs/specs/sync-freshness.md` §2.3).
///
/// Uses `refreshNow()`, not `pushDirty()`: the latter swallows every error
/// by contract (spec `sync-backend.md` §8.3), so the indicator used to spin
/// and stop identically whether the sync worked or the phone was offline --
/// found by the 2026-08-07 persona walkthrough. Success stays silent; the
/// list simply updates, which is the platform convention.
Future<void> _refresh(BuildContext context, WidgetRef ref) async {
  final ok = await ref.read(syncEngineProvider).refreshNow();
  if (ok || !context.mounted) {
    return;
  }
  showAppSnackbar(
    context,
    message: AppLocalizations.of(context).syncRefreshError,
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.cartExpanded,
    required this.onCartExpansionChanged,
    required this.onCheckedChanged,
    required this.onTapItem,
    required this.onLongPressItem,
    required this.onSwipeDeleteItem,
    required this.onClear,
    required this.onUncheckAll,
  });

  final List<ShoppingItemWithCategory> items;
  final bool cartExpanded;
  final ValueChanged<bool> onCartExpansionChanged;
  final void Function(String id, {required bool checked}) onCheckedChanged;
  final ValueChanged<ShoppingItemWithCategory> onTapItem;
  final ValueChanged<ShoppingItemWithCategory> onLongPressItem;
  final ValueChanged<String> onSwipeDeleteItem;
  final VoidCallback onClear;
  final VoidCallback onUncheckAll;

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
      // Scrollable (not a bare Center): a RefreshIndicator higher up the
      // tree (C1, spec docs/specs/sync-freshness.md §2.3) needs a
      // Scrollable descendant to detect the pull gesture, and that must
      // hold even when the list is empty -- an indicator that only "works"
      // on a populated list would be exactly the kind of
      // provably-does-nothing affordance waves M and R removed.
      return const _ScrollableEmptyState(child: _EmptyMessage());
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
          expanded: cartExpanded,
          onExpansionChanged: onCartExpansionChanged,
          onClear: onClear,
          onUncheckAll: onUncheckAll,
        ),
    ];

    return ListView(
      // C8 (conventions audit): dismisses the keyboard on a scroll drag --
      // the quick-add field above stays focused after a submit, so scrolling
      // the list underneath is exactly the "working the list" gesture Bug 3
      // (field feedback round 2) already dismisses the suggestions list for.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: children,
    );
  }

  /// Builds a category header followed by one card per run of same-category
  /// items (spec `docs/specs/theme-v2.md` §4.3: "one card per category", not
  /// one card per item), preserving [unchecked]'s existing
  /// (repository-sorted) order — never re-sorting client-side.
  List<Widget> _groupedTiles(List<ShoppingItemWithCategory> unchecked) {
    final children = <Widget>[];
    var index = 0;
    while (index < unchecked.length) {
      final categoryId = unchecked[index].item.categoryId;
      final group = <ShoppingItemWithCategory>[];
      while (index < unchecked.length &&
          unchecked[index].item.categoryId == categoryId) {
        group.add(unchecked[index]);
        index++;
      }
      children
        ..add(ShoppingCategoryHeader(category: group.first.category))
        ..add(_aisleCard(group));
    }
    return children;
  }

  /// One [DepthCard] holding every item in [group] as a hairline-separated
  /// row — never a hairline after the last row.
  Widget _aisleCard(List<ShoppingItemWithCategory> group) {
    return DepthCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < group.length; i++) ...[
            _tileFor(group[i]),
            if (i < group.length - 1) const Divider(height: 1, thickness: 1),
          ],
        ],
      ),
    );
  }

  Widget _tileFor(ShoppingItemWithCategory item) {
    return ShoppingItemTile(
      key: ValueKey(item.item.id),
      item: item,
      onCheckedChanged: (value) =>
          onCheckedChanged(item.item.id, checked: value),
      onTap: () => onTapItem(item),
      onLongPress: () => onLongPressItem(item),
      onSwipeDelete: () => onSwipeDeleteItem(item.item.id),
    );
  }
}

/// Wraps an empty-state [child] in a scrollable that fills the available
/// height (`SliverFillRemaining(hasScrollBody: false)`), so the
/// [RefreshIndicator] wrapping this screen's list (C1, spec
/// `docs/specs/sync-freshness.md` §2.3) still has a `Scrollable` descendant
/// to detect a pull gesture even when the list is empty -- otherwise the
/// indicator would silently do nothing on the empty state, exactly the
/// dishonest affordance waves M and R removed.
class _ScrollableEmptyState extends StatelessWidget {
  const _ScrollableEmptyState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
      ],
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The accent icon tile mirrors the chores list's empty state (spec
    // `docs/specs/theme-v2.md` §4.1 item 6). Wave T4's scope (§4.3) never
    // named this widget, so shopping was left with the old lone grey glyph
    // while chores got the new treatment — visual QA caught the two tabs
    // disagreeing with each other.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: famdoColors(context).primaryOutline),
            ),
            child: Icon(
              Icons.add_shopping_cart_outlined,
              size: 36,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          semantic(
            'shopping.empty',
            child: Text(
              AppLocalizations.of(context).shoppingEmptyState,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
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
