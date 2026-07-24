/// A single pending occurrence's list tile.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats [date] as e.g. `'Jul 20'` in [localeName], via `package:intl`'s
/// locale-aware month abbreviations — never a hardcoded month name list.
String formatShortDate(PlainDate date, String localeName) {
  return DateFormat.MMMd(
    localeName,
  ).format(DateTime.utc(date.year, date.month, date.day));
}

/// A tile for one pending [OccurrenceWithChore].
///
/// Leading circular button completes it; the title/subtitle show the
/// chore's title, category (if any), and assignee (if any); tapping the
/// trailing menu button or long-pressing anywhere on the tile opens the
/// skip/edit/pause/delete action sheet via [onOpenMenu]. Overdue tiles show
/// their due date in the theme's error color.
class ChoreOccurrenceTile extends StatelessWidget {
  /// Creates a tile for [occurrence].
  const ChoreOccurrenceTile({
    required this.occurrence,
    required this.isOverdue,
    required this.onComplete,
    required this.onOpenMenu,
    super.key,
  });

  /// The occurrence (and its joined chore/category/assignee) to display.
  final OccurrenceWithChore occurrence;

  /// Whether this occurrence's due date is before today.
  final bool isOverdue;

  /// Called when the leading complete button is tapped.
  final VoidCallback onComplete;

  /// Called when the trailing menu button is tapped, or the tile is
  /// long-pressed.
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final chore = occurrence.chore;
    final l10n = AppLocalizations.of(context);
    return semantic(
      'chores.occurrence.${chore.id}',
      child: ListTile(
        onLongPress: onOpenMenu,
        leading: semantic(
          'chores.occurrence.${chore.id}.complete',
          child: IconButton(
            icon: const Icon(Icons.circle_outlined),
            tooltip: l10n.choresOccurrenceCompleteTooltip,
            onPressed: onComplete,
          ),
        ),
        title: Text(chore.title),
        subtitle: _Subtitle(occurrence: occurrence, isOverdue: isOverdue),
        trailing: semantic(
          'chores.occurrence.${chore.id}.menu',
          child: IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.choresOccurrenceMoreActionsTooltip,
            onPressed: onOpenMenu,
          ),
        ),
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.occurrence, required this.isOverdue});

  final OccurrenceWithChore occurrence;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final category = occurrence.category;
    final assignee = occurrence.assignedMember;
    final localeName = Localizations.localeOf(context).toString();
    final parts = <Widget>[
      if (category != null) CategoryBadge(category: category),
      if (assignee != null) Text(assignee.name),
      if (isOverdue)
        Text(
          AppLocalizations.of(context).choresOccurrenceDueLabel(
            formatShortDate(occurrence.occurrence.dueDate, localeName),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(spacing: 12, children: parts);
  }
}
