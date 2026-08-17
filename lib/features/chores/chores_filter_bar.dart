/// The chores list's member/category filter buttons.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filters the chores list to [selected]'s member (or all, if `null`),
/// reporting a new choice via [onChanged].
class MemberFilterButton extends ConsumerWidget {
  /// Creates the member filter button.
  const MemberFilterButton({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected member id, or `null` for all members.
  final String? selected;

  /// Called with the newly-selected member id (`null` for all members).
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value ?? const [];
    final l10n = AppLocalizations.of(context);
    return semantic(
      'chores.filter.member',
      child: PopupMenuButton<String?>(
        icon: _FilterIcon(
          icon: Icons.person_outline,
          isActive: selected != null,
        ),
        tooltip: l10n.choresFilterMemberTooltip,
        onSelected: onChanged,
        itemBuilder: (context) => [
          // A PopupMenuItem without a value pops `null`, which
          // PopupMenuButton treats as "menu dismissed" and never forwards
          // to onSelected — so the reset entry must fire via onTap instead.
          PopupMenuItem(
            onTap: () => onChanged(null),
            child: semantic(
              'chores.filter.member.all',
              child: _entryLabel(
                l10n.choresFilterMemberAll,
                isSelected: selected == null,
              ),
            ),
          ),
          for (final member in members)
            PopupMenuItem(
              value: member.id,
              child: semantic(
                'chores.filter.member.${member.id}',
                child: _entryLabel(
                  member.name,
                  isSelected: selected == member.id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filters the chores list to [selected]'s category (or all, if `null`),
/// reporting a new choice via [onChanged].
class CategoryFilterButton extends ConsumerWidget {
  /// Creates the category filter button.
  const CategoryFilterButton({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected category id, or `null` for all categories.
  final String? selected;

  /// Called with the newly-selected category id (`null` for all
  /// categories).
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(choreCategoriesProvider).value ?? const [];
    final l10n = AppLocalizations.of(context);
    return semantic(
      'chores.filter.category',
      child: PopupMenuButton<String?>(
        icon: _FilterIcon(
          icon: Icons.label_outline,
          isActive: selected != null,
        ),
        tooltip: l10n.choresFilterCategoryTooltip,
        onSelected: onChanged,
        itemBuilder: (context) => [
          // Same null-value gotcha as the member button above: the reset
          // entry must use onTap, or selecting it is a silent no-op.
          PopupMenuItem(
            onTap: () => onChanged(null),
            child: semantic(
              'chores.filter.category.all',
              child: _entryLabel(
                l10n.choresFilterCategoryAll,
                isSelected: selected == null,
              ),
            ),
          ),
          for (final category in categories)
            PopupMenuItem(
              value: category.id,
              child: semantic(
                'chores.filter.category.${category.id}',
                child: _entryLabel(
                  category.name,
                  isSelected: selected == category.id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A filter button's icon: badge-dotted and primary-tinted while its
/// filter is active (ux-round-2 C1 — two signals, never color alone), the
/// plain outlined icon otherwise.
class _FilterIcon extends StatelessWidget {
  const _FilterIcon({required this.icon, required this.isActive});

  final IconData icon;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!isActive) {
      return Icon(icon);
    }
    return Badge(
      smallSize: 8,
      backgroundColor: colorScheme.primary,
      child: Icon(icon, color: colorScheme.primary),
    );
  }
}

/// A popup menu entry's label, with a leading check mark when
/// [isSelected].
Widget _entryLabel(String text, {required bool isSelected}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(isSelected ? Icons.check : null, size: 18),
      const SizedBox(width: 8),
      Text(text),
    ],
  );
}
