/// The app's three-tab bottom navigation shell.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/chores/chores_list_screen.dart';
import 'package:chore_app/features/shopping/shopping_list_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The three top-level tabs, in display order.
enum _AppTab {
  /// The chores list (this spec's feature).
  chores(filled: Icons.checklist, outlined: Icons.checklist_outlined),

  /// The shopping list (built in a separate spec; a placeholder here).
  shopping(
    filled: Icons.shopping_cart,
    outlined: Icons.shopping_cart_outlined,
  ),

  /// Household settings (built later; a placeholder here).
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selected.index,
        children: [
          const ChoresListScreen(),
          const ShoppingListScreen(),
          _PlaceholderScreen(
            title: AppLocalizations.of(context).settingsTabLabel,
          ),
        ],
      ),
      bottomNavigationBar: _BottomTabBar(
        selected: _selected,
        onSelected: (tab) => setState(() => _selected = tab),
      ),
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

/// A minimal placeholder tab body for a feature built in a later spec.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  /// The tab's display title.
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(AppLocalizations.of(context).settingsComingSoon(title)),
      ),
    );
  }
}
