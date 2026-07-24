/// A single pending occurrence's list tile.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The localized due text for a non-overdue [dueDate] (on or after
/// [today]): 'Today'/'Tomorrow' near the boundary, 'In N days' for 2-7 days
/// out, else the locale-formatted weekday + month + day (e.g. 'Fri, Jul
/// 31') via `package:intl` — never a hardcoded weekday/month name.
///
/// [dueDate] must not be before [today]; an overdue tile uses
/// [overdueDueText] instead.
String futureDueText(
  AppLocalizations l10n,
  String localeName, {
  required PlainDate today,
  required PlainDate dueDate,
}) {
  final diff = today.daysUntil(dueDate);
  if (diff == 0) {
    return l10n.choresDueToday;
  }
  if (diff == 1) {
    return l10n.choresDueTomorrow;
  }
  if (diff <= 7) {
    return l10n.choresDueInDays(diff);
  }
  return DateFormat.MMMEd(
    localeName,
  ).format(DateTime.utc(dueDate.year, dueDate.month, dueDate.day));
}

/// The localized due text for an overdue [dueDate] (strictly before
/// [today]): 'Overdue · N days', pluralized.
String overdueDueText(
  AppLocalizations l10n, {
  required PlainDate today,
  required PlainDate dueDate,
}) {
  return l10n.choresDueOverdue(dueDate.daysUntil(today));
}

/// A tile for one pending [OccurrenceWithChore].
///
/// Layout (see `docs/specs/ux-round-2.md` A1 and
/// `docs/specs/design-language.md`): a leading 48dp complete circle,
/// vertically centered against a text block of the chore's title (titleMedium),
/// a metadata row (bodySmall, onSurfaceVariant) showing the assignee's
/// avatar + first name (when assigned), the category chip (when
/// categorized), and the due text — shown on every tile, relative for near
/// dates and locale-formatted beyond, in the theme's error color when
/// overdue — and, only when the chore has a note, a one-line ellipsized
/// note row. Tapping the trailing menu button or long-pressing anywhere on
/// the tile opens the skip/edit/pause/delete action sheet via [onOpenMenu].
class ChoreOccurrenceTile extends StatelessWidget {
  /// Creates a tile for [occurrence].
  const ChoreOccurrenceTile({
    required this.occurrence,
    required this.today,
    required this.isOverdue,
    required this.onComplete,
    required this.onOpenMenu,
    super.key,
  });

  /// The occurrence (and its joined chore/category/assignee) to display.
  final OccurrenceWithChore occurrence;

  /// The current local calendar day, per the app's injected clock — used to
  /// compute the tile's relative due text.
  final PlainDate today;

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
    final theme = Theme.of(context);
    final notes = chore.notes;
    return semantic(
      'chores.occurrence.${chore.id}',
      child: InkWell(
        onLongPress: onOpenMenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              semantic(
                'chores.occurrence.${chore.id}.complete',
                child: IconButton(
                  icon: const Icon(Icons.circle_outlined),
                  tooltip: l10n.choresOccurrenceCompleteTooltip,
                  onPressed: onComplete,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(chore.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      _MetadataRow(
                        occurrence: occurrence,
                        today: today,
                        isOverdue: isOverdue,
                      ),
                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _NoteLine(note: notes),
                      ],
                    ],
                  ),
                ),
              ),
              semantic(
                'chores.occurrence.${chore.id}.menu',
                child: IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: l10n.choresOccurrenceMoreActionsTooltip,
                  onPressed: onOpenMenu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The metadata row: assignee avatar + first name (if assigned), category
/// chip (if categorized), and the due text (always).
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.occurrence,
    required this.today,
    required this.isOverdue,
  });

  final OccurrenceWithChore occurrence;
  final PlainDate today;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final category = occurrence.category;
    final assignee = occurrence.assignedMember;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final dueDate = occurrence.occurrence.dueDate;

    return DefaultTextStyle.merge(
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (assignee != null) _MemberAvatarName(member: assignee),
          if (category != null) CategoryBadge(category: category),
          Text(
            isOverdue
                ? overdueDueText(l10n, today: today, dueDate: dueDate)
                : futureDueText(
                    l10n,
                    localeName,
                    today: today,
                    dueDate: dueDate,
                  ),
            style: isOverdue ? TextStyle(color: theme.colorScheme.error) : null,
          ),
        ],
      ),
    );
  }
}

/// A 20dp circular avatar in [member]'s color with their initial, followed
/// by their first name.
class _MemberAvatarName extends StatelessWidget {
  const _MemberAvatarName({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final color = Color(member.color);
    final trimmedName = member.name.trim();
    final initial = trimmedName.isEmpty
        ? '?'
        : trimmedName.substring(0, 1).toUpperCase();
    final firstName = trimmedName.isEmpty
        ? member.name
        : trimmedName.split(RegExp(r'\s+')).first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: color,
          child: Text(
            initial,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(firstName),
      ],
    );
  }
}

/// The note row: a small icon followed by [note], truncated to one
/// ellipsized line.
class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.notes_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
