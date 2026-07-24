/// Read-only category badge (icon + name in the category's color).
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// A small, non-interactive pill showing [category]'s icon and name, both
/// drawn in the category's own color.
///
/// Used in occurrence tile subtitles; unlike the selectable category
/// picker, this is never tappable.
class CategoryBadge extends StatelessWidget {
  /// Creates a badge for [category].
  const CategoryBadge({required this.category, super.key});

  /// The category to display.
  final Category category;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(categoryIcon(category.icon), color: color, size: 16),
        const SizedBox(width: 4),
        Text(category.name, style: TextStyle(color: color)),
      ],
    );
  }
}
