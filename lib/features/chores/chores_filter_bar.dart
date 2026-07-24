/// The chores list's member/category filter buttons.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
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
    return semantic(
      'chores.filter.member',
      child: PopupMenuButton<String?>(
        icon: const Icon(Icons.person_outline),
        tooltip: 'Filter by member',
        onSelected: onChanged,
        itemBuilder: (context) => [
          PopupMenuItem(
            child: semantic(
              'chores.filter.member.all',
              child: _entryLabel('All members', isSelected: selected == null),
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
    return semantic(
      'chores.filter.category',
      child: PopupMenuButton<String?>(
        icon: const Icon(Icons.label_outline),
        tooltip: 'Filter by category',
        onSelected: onChanged,
        itemBuilder: (context) => [
          PopupMenuItem(
            child: semantic(
              'chores.filter.category.all',
              child: _entryLabel(
                'All categories',
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

/// A popup menu entry's label, with a leading check mark when
/// [isSelected].
Widget _entryLabel(String text, {required bool isSelected}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        isSelected ? Icons.check : null,
        size: 18,
      ),
      const SizedBox(width: 8),
      Text(text),
    ],
  );
}
