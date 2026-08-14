/// The app's three-tab bottom navigation shell.
library;

import 'dart:async';

import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/chores/chores_list_screen.dart';
import 'package:chore_app/features/settings/settings_screen.dart';
import 'package:chore_app/features/shopping/shopping_list_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The three top-level tabs, in display order.
enum _AppTab {
  /// The chores list (this spec's feature).
  chores(filled: Icons.checklist, outlined: Icons.checklist_outlined),

  /// The shopping list.
  shopping(
    filled: Icons.shopping_cart,
    outlined: Icons.shopping_cart_outlined,
  ),

  /// Household settings.
  settings(filled: Icons.settings, outlined: Icons.settings_outlined);

  const _AppTab({required this.filled, required this.outlined});

  /// This tab's icon when selected.
  final IconData filled;

  /// This tab's icon when unselected.
  final IconData outlined;
}

/// This tab's localized display label.
String _tabLabel(BuildContext context, _AppTab tab) {
  final l10n = AppLocalizations.of(context);
  switch (tab) {
    case _AppTab.chores:
      return l10n.choresTabLabel;
    case _AppTab.shopping:
      return l10n.shoppingTabLabel;
    case _AppTab.settings:
      return l10n.settingsTabLabel;
  }
}

/// Bottom-navigation shell holding the app's three top-level tabs.
///
/// Content lives in a [PageView] so the three tabs can be swiped between
/// (backlog D-1 / field feedback 2026-08-07 B3). Each page is wrapped in a
/// [_KeepAlivePage] so leaving a tab preserves its scroll position and
/// in-flight state instead of rebuilding it from scratch — the property the
/// [IndexedStack] this replaced was chosen for, and a binding requirement
/// (spec `docs/specs/ui-shopping.md`).
///
/// The tab bar is hand-rolled rather than built from [NavigationBar]:
/// [NavigationBar] wraps each destination in a `MergeSemantics` boundary
/// that collapses a nested `Semantics(identifier: ...)` into the merged
/// node, silently dropping the very identifier E2E/widget tests need to
/// select a tab by.
class AppShell extends StatefulWidget {
  /// Creates the shell.
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _AppTab _selected = _AppTab.chores;

  /// Drives the content [PageView].
  ///
  /// A tab TAP calls [PageController.jumpToPage], never `animateToPage`:
  /// Material 3 does not slide between bottom-navigation destinations, and
  /// an instant switch keeps every existing E2E flow and widget test seeing
  /// exactly the timing they saw before D-1 (spec
  /// `docs/specs/testing-strategy.md` §2.4). Only a user's own drag animates,
  /// and then it is `PageScrollPhysics`' standard settle — no custom
  /// animation code, so `docs/specs/design-language.md`'s Motion rule holds.
  final _pageController = PageController();

  /// One scroll controller per tab, published into that tab's subtree by
  /// [_KeepAlivePage] via [PrimaryScrollController].
  ///
  /// The three tab screens' scroll views are all uncontrolled and vertical
  /// (`ListView`/`CustomScrollView` with no `controller:` and no `primary:`),
  /// so `ScrollView.effectivePrimary` makes them attach to whatever
  /// `PrimaryScrollController` is in scope — which is how the shell reaches
  /// a tab's scroll position for D-4 without any feature file exposing one.
  /// Every scrollable INSIDE a tab that must not attach (the members list,
  /// the categories reorder list, every bottom sheet) lives on a pushed
  /// route or an overlay, i.e. a sibling of this shell under the `Navigator`
  /// rather than a descendant of a page.
  late final Map<_AppTab, ScrollController> _scrollControllers = {
    for (final tab in _AppTab.values) tab: ScrollController(),
  };

  /// Keyed so [_onPageChanged] can reach the nested [ScaffoldMessenger]'s
  /// state directly (it has no `BuildContext` of its own to look up via
  /// `ScaffoldMessenger.of`).
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Backlog D-6: Material's rule is that back returns to the start
    // destination before it leaves the app, and today a back press on any
    // tab quits outright. `canPop` is true only on the first tab, so the
    // first-tab case is left entirely alone — the framework bubbles it and
    // calls `SystemNavigator.pop()` exactly as before. (Side effect: with
    // `canPop: false` Android's predictive-back preview is suppressed on the
    // other two tabs, which is the documented cost of intercepting a pop.)
    return PopScope(
      canPop: _selected == _AppTab.chores,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _onTabSelected(_AppTab.chores);
      },
      child: Scaffold(
        // A nested ScaffoldMessenger so tab screens' `ScaffoldMessenger.of
        // (context)` lookups resolve to it instead of the root one:
        // ScaffoldMessenger only ever presents in the topmost Scaffold among
        // its registered descendants, so without this the root messenger
        // would present tab-screen snackbars in THIS Scaffold (the one
        // below, owning `bottomNavigationBar`) — flush against
        // `_BottomTabBar` with no room to breathe. Nesting it here makes
        // each tab's own inner Scaffold the topmost one instead, so its
        // snackbars present above the tab bar with margin (see
        // `lib/app/snackbars.dart`).
        body: ScaffoldMessenger(
          key: _messengerKey,
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            // `allowImplicitScrolling` is deliberately left at its default
            // (false) and must stay there: it widens the viewport's cache
            // extent so the neighbouring page is laid out INSIDE the
            // semantics clip, which would leak that tab's
            // `Semantics(identifier: ...)` nodes into every
            // `find.bySemanticsIdentifier` and every Maestro
            // `assertVisible` while another tab is on screen. Covered by
            // test/app/shell_navigation_test.dart.
            children: [
              for (final tab in _AppTab.values)
                _KeepAlivePage(
                  scrollController: _scrollControllers[tab]!,
                  child: _screenFor(tab),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomTabBar(
          selected: _selected,
          onSelected: _onTabSelected,
        ),
      ),
    );
  }

  /// The screen shown on [tab]'s page.
  Widget _screenFor(_AppTab tab) {
    switch (tab) {
      case _AppTab.chores:
        return const ChoresListScreen();
      case _AppTab.shopping:
        return const ShoppingListScreen();
      case _AppTab.settings:
        return const SettingsScreen();
    }
  }

  /// Switches the visible tab — or, when [tab] is already the visible one,
  /// scrolls that tab's list back to the top (conventions audit C6 /
  /// backlog D-4): the convention every list-based mobile app has taught
  /// the user.
  ///
  /// `animateTo` rather than `jumpTo` because landing at the top from far
  /// down a list without motion is disorienting, and it is a first-party
  /// `ScrollController` API reached only from a user tap — not custom
  /// animation code (spec `docs/specs/design-language.md`, Motion).
  /// `animateTo` also iterates `positions` internally, so unlike `.offset`
  /// it is safe even if a tab ever ends up with two attached scroll views;
  /// `hasClients` covers the zero case (a tab with nothing scrollable in it
  /// yet).
  void _onTabSelected(_AppTab tab) {
    if (tab == _selected) {
      final controller = _scrollControllers[tab]!;
      if (controller.hasClients) {
        unawaited(
          controller.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return;
    }
    _pageController.jumpToPage(tab.index);
  }

  /// The single source of truth for "the user left a tab" — reached both by
  /// [_onTabSelected]'s jump and by a finger-driven page settle.
  ///
  /// Clears any snackbar shown on the tab being left (field feedback B1,
  /// `docs/feedback/2026-08-01-field-feedback.md`): a completion/skip toast
  /// is contextual to the tab the action happened on, so it shouldn't
  /// linger — or, worse, have its UNDO tapped — once the user has moved on
  /// to something else. Independent of the `persist: false` fix in
  /// `lib/app/snackbars.dart` (which stops toasts from sticking around
  /// forever on their OWN tab); this handles leaving the tab before that
  /// duration elapses. Re-tapping the tab you are already on is not leaving
  /// it, never reaches here, and so keeps its snackbar.
  void _onPageChanged(int index) {
    _messengerKey.currentState?.clearSnackBars();
    setState(() => _selected = _AppTab.values[index]);
  }
}

/// One page of the shell's [PageView], kept alive when it scrolls off
/// screen.
///
/// `PageView` builds its pages lazily and discards them once they are far
/// enough away; [AutomaticKeepAliveClientMixin] opts each page out of that,
/// which is what preserves a tab's scroll position and in-flight state
/// across a switch (spec `docs/specs/ui-shopping.md`). Implemented as a
/// wrapper here rather than mixed into the three tab screens so the whole
/// of D-1 stays inside this file.
///
/// A kept-alive page is held outside the sliver's laid-out child list, so it
/// is neither painted nor visited for semantics while off screen — see the
/// note on `allowImplicitScrolling` above.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.scrollController, required this.child});

  /// Published to [child]'s subtree as its [PrimaryScrollController], so the
  /// tab screen's uncontrolled vertical scroll view attaches to it.
  final ScrollController scrollController;

  /// The tab screen this page shows.
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PrimaryScrollController(
      controller: widget.scrollController,
      child: widget.child,
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({required this.selected, required this.onSelected});

  final _AppTab selected;
  final ValueChanged<_AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final famdo = famdoColors(context);
    return Container(
      // A 1px top hairline (spec docs/specs/theme-v2.md §4.5) sits on this
      // outer Container so the inner Material can keep filling its bounds
      // with `navBarBackground` -- Material's own `shape` has no clean way
      // to draw a single-edge border.
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Material(
        color: famdo.navBarBackground,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                for (final tab in _AppTab.values)
                  Expanded(
                    child: semantic(
                      'shell.tab.${tab.name}',
                      // The hand-rolled bar must carry the traits
                      // NavigationBar would have provided: without
                      // `selected`, screen readers can't tell which tab is
                      // active (the visual cue is color/icon only).
                      child: Semantics(
                        button: true,
                        selected: tab == selected,
                        // Field feedback 2026-08-07 C2: a bare InkWell
                        // rippled a grey RECTANGLE across the whole tab
                        // column while the active state is a rounded pill --
                        // the two shapes fought each other. InkResponse with
                        // a bounded radius keeps the splash inside a pill
                        // roughly the size of the active one, and tints it
                        // with the accent instead of the default grey.
                        child: InkResponse(
                          onTap: () => onSelected(tab),
                          radius: 44,
                          containedInkWell: true,
                          highlightShape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(16),
                          splashColor: colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          highlightColor: colorScheme.primary.withValues(
                            alpha: 0.06,
                          ),
                          child: _TabContent(
                            tab: tab,
                            isSelected: tab == selected,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({required this.tab, required this.isSelected});

  final _AppTab tab;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // The active destination's 62x30 pill (spec
        // docs/specs/theme-v2.md §4.5); inactive tabs get an equivalent
        // transparent slot so the icon doesn't jump vertically when
        // selection changes.
        Container(
          width: 62,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(isSelected ? tab.filled : tab.outlined, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          _tabLabel(context, tab),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
