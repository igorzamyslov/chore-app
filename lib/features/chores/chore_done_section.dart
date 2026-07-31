/// The collapsed-by-default 'Done today (N)' section: occurrences closed
/// (done or skipped) today, each with a Reopen action.
library;

import 'package:chore_app/app/depth_variant.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Done today' section: a collapsed-by-default [ExpansionTile] headed
/// 'Done today (N)', holding one row per closed-today [occurrences] entry.
///
/// See `docs/specs/ux-round-2.md` A3. The caller only mounts this widget
/// while there's at least one closed-today occurrence, so every row always
/// has a visible Reopen action.
class ChoreDoneSection extends StatelessWidget {
  /// Creates the section for [occurrences], closed today.
  const ChoreDoneSection({
    required this.occurrences,
    required this.onReopen,
    super.key,
  });

  /// The occurrences closed (done or skipped) today, to list.
  final List<ClosedOccurrenceWithChore> occurrences;

  /// Called with the tapped row's occurrence when its Reopen action fires.
  final ValueChanged<ClosedOccurrenceWithChore> onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Whole-section card (not per-row): the ExpansionTile already groups
    // these rows visually, so a card per row would double up with the
    // section's own chrome once expanded — one card wrapping the header +
    // rows reads cleaner (judgment call, see the #6 plan report).
    return DepthCard(
      child: ExpansionTile(
        title: semantic(
          'chores.done.header',
          child: Text(l10n.choresDoneHeader(occurrences.length)),
        ),
        children: [
          for (final occurrence in occurrences)
            _DoneRow(
              occurrence: occurrence,
              onReopen: () => onReopen(occurrence),
            ),
        ],
      ),
    );
  }
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.occurrence, required this.onReopen});

  final ClosedOccurrenceWithChore occurrence;
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
      trailing: semantic(
        'chores.done.${occurrence.occurrence.id}.reopen',
        child: TextButton(
          onPressed: onReopen,
          child: Text(l10n.choresDoneReopen),
        ),
      ),
    );
  }
}
