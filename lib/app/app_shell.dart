/// The app's three-tab bottom navigation shell.
library;

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
/// Uses an [IndexedStack] so switching tabs preserves each tab's scroll
/// position and in-flight state instead of rebuilding it from scratch.
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

  /// Keyed so [_onTabSelected] can reach the nested [ScaffoldMessenger]'s
  /// state directly (it has no `BuildContext` of its own to look up via
  /// `ScaffoldMessenger.of`).
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A nested ScaffoldMessenger so tab screens' `ScaffoldMessenger.of
      // (context)` lookups resolve to it instead of the root one:
      // ScaffoldMessenger only ever presents in the topmost Scaffold among
      // its registered descendants, so without this the root messenger
      // would present tab-screen snackbars in THIS Scaffold (the one below,
      // owning `bottomNavigationBar`) — flush against `_BottomTabBar` with
      // no room to breathe. Nesting it here makes each tab's own inner
      // Scaffold the topmost one instead, so its snackbars present above
      // the tab bar with margin (see `lib/app/snackbars.dart`).
      body: ScaffoldMessenger(
        key: _messengerKey,
        child: IndexedStack(
          index: _selected.index,
          children: const [
            ChoresListScreen(),
            ShoppingListScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomTabBar(
        selected: _selected,
        onSelected: _onTabSelected,
      ),
    );
  }

  /// Switches the visible tab, clearing any snackbar shown on the tab being
  /// left (field feedback B1, `docs/feedback/2026-08-01-field-feedback.md`):
  /// a completion/skip toast is contextual to the tab the action happened
  /// on, so it shouldn't linger — or, worse, have its UNDO tapped — once
  /// the user has moved on to something else. Independent of the
  /// `persist: false` fix in `lib/app/snackbars.dart` (which stops toasts
  /// from sticking around forever on their OWN tab); this handles leaving
  /// the tab before that duration elapses.
  void _onTabSelected(_AppTab tab) {
    _messengerKey.currentState?.clearSnackBars();
    setState(() => _selected = tab);
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({required this.selected, required this.onSelected});

  final _AppTab selected;
  final ValueChanged<_AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
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
                      child: InkWell(
                        onTap: () => onSelected(tab),
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
        Icon(isSelected ? tab.filled : tab.outlined, color: color),
        const SizedBox(height: 2),
        Text(
          _tabLabel(context, tab),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}
