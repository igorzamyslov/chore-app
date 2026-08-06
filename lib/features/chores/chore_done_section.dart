/// The collapsed-by-default 'Done today (N)' section: occurrences closed
/// (done or skipped) today, each with a Reopen action.
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Done today' section: a collapsed-by-default [ExpansionTile] headed
/// 'Done today (N)', holding one row per closed-today [occurrences] entry.
///
/// See `docs/specs/ux-round-2.md` A3. The caller only mounts this widget
/// while there's at least one closed-today occurrence.
///
/// **LIFO amendment (2026-08-01, field feedback B2 —
/// `docs/feedback/2026-08-01-field-feedback.md`):** a row only gets a
/// Reopen action if its occurrence id is in [reopenableOccurrenceIds] —
/// each chore's LATEST closed-today row, per
/// `ChoreService.reopenOccurrence`'s LIFO contract. The affordance
/// reappears on the next-latest row once the chain unwinds.
class ChoreDoneSection extends StatelessWidget {
  /// Creates the section for [occurrences], closed today.
  const ChoreDoneSection({
    required this.occurrences,
    required this.reopenableOccurrenceIds,
    required this.onReopen,
    super.key,
  });

  /// The occurrences closed (done or skipped) today, to list.
  final List<ClosedOccurrenceWithChore> occurrences;

  /// The ids of the rows that may show the Reopen action — see
  /// [latestClosedTodayOccurrenceIds].
  final Set<String> reopenableOccurrenceIds;

  /// Called with the tapped row's occurrence when its Reopen action fires.
  final ValueChanged<ClosedOccurrenceWithChore> onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Whole-section card (not per-row): the ExpansionTile already groups
    // these rows visually, so a card per row would double up with the
    // section's own chrome once expanded — one card wrapping the header +
    // rows reads cleaner (judgment call, see the #6 plan report).
    // surfaceContainerHigh ground + a leading icon (spec
    // docs/specs/theme-v2.md §4.1 item 5); the trailing chevron is
    // ExpansionTile's own default.
    return DepthCard(
      color: theme.colorScheme.surfaceContainerHigh,
      child: ExpansionTile(
        leading: Icon(
          Icons.check_circle_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: semantic(
          'chores.done.header',
          child: Text(l10n.choresDoneHeader(occurrences.length)),
        ),
        children: [
          for (var i = 0; i < occurrences.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1),
            _DoneRow(
              occurrence: occurrences[i],
              showReopen: reopenableOccurrenceIds.contains(
                occurrences[i].occurrence.id,
              ),
              onReopen: () => onReopen(occurrences[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The ids of each chore's LATEST closed-today occurrence in [occurrences]
/// — ordered by due date, then `updatedAt` as tiebreak, matching the LIFO
/// rule `ChoreService.reopenOccurrence` enforces (see its doc comment and
/// `docs/specs/occurrence-lifecycle.md` §reopenOccurrence).
///
/// Deliberately computed over the FULL closed-today list, not whatever
/// member/category-filtered subset the caller displays: an active filter
/// can hide a chore's true latest row (e.g. it was closed by a different
/// member than the one filtered on) without changing which row the service
/// will actually accept — computing from the filtered list could offer
/// Reopen on a row that then throws `StateError` when tapped.
Set<String> latestClosedTodayOccurrenceIds(
  List<ClosedOccurrenceWithChore> occurrences,
) {
  final latestByChore = <String, ClosedOccurrenceWithChore>{};
  for (final row in occurrences) {
    final current = latestByChore[row.chore.id];
    if (current == null || _isLaterClosedToday(row, current)) {
      latestByChore[row.chore.id] = row;
    }
  }
  return {for (final row in latestByChore.values) row.occurrence.id};
}

/// Whether [a] closed later than [b]: by due date first, then `updatedAt`
/// (ISO-8601 UTC, so lexical order matches chronological order) as the
/// tiebreak — the same ordering `ChoreService.reopenOccurrence` uses.
bool _isLaterClosedToday(
  ClosedOccurrenceWithChore a,
  ClosedOccurrenceWithChore b,
) {
  final dueCompare = a.occurrence.dueDate.compareTo(b.occurrence.dueDate);
  if (dueCompare != 0) {
    return dueCompare > 0;
  }
  return a.occurrence.updatedAt.compareTo(b.occurrence.updatedAt) > 0;
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({
    required this.occurrence,
    required this.showReopen,
    required this.onReopen,
  });

  final ClosedOccurrenceWithChore occurrence;

  /// Whether this row is its chore's latest closed-today occurrence — see
  /// [ChoreDoneSection]'s LIFO doc comment.
  final bool showReopen;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDone = occurrence.occurrence.status == OccurrenceStatus.done;
    // Skipping doesn't record a dedicated closer (`completedBy` stays
    // null); the assignee is the closest available stand-in for "who this
    // was on".
    final closerName = isDone
        ? occurrence.completedByMember?.name
        : occurrence.assignedMember?.name;

    return ListTile(
      title: Text(
        occurrence.chore.title,
        style: theme.textTheme.titleMedium?.copyWith(
          decoration: TextDecoration.lineThrough,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: DefaultTextStyle.merge(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle_outline
                      : Icons.skip_next_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  isDone
                      ? l10n.choresDoneStatusDone
                      : l10n.choresDoneStatusSkipped,
                ),
              ],
            ),
            if (closerName != null)
              Text(l10n.choresDoneClosedByLabel(closerName)),
          ],
        ),
      ),
      // LIFO amendment: plain absence (no placeholder) on every row except
      // the chore's latest closed-today one — see the class doc comment.
      trailing: showReopen
          ? semantic(
              'chores.done.${occurrence.occurrence.id}.reopen',
              child: TextButton(
                onPressed: onReopen,
                child: Text(l10n.choresDoneReopen),
              ),
            )
          : null,
    );
  }
}
