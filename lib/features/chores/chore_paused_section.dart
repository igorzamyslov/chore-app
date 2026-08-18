/// The collapsed-by-default 'Paused (N)' section: paused chores, each with
/// a Resume action.
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The 'Paused' section: a collapsed-by-default [ExpansionTile] headed
/// 'Paused (N)', holding one row per paused chore in [chores].
///
/// See `docs/specs/ux-round-2.md` A5. The caller only mounts this widget
/// while there's at least one paused chore.
class ChorePausedSection extends StatelessWidget {
  /// Creates the section for the given paused [chores].
  const ChorePausedSection({
    required this.chores,
    required this.onResume,
    super.key,
  });

  /// The paused chores to list.
  final List<ChoreWithDetails> chores;

  /// Called with the tapped row's chore when its Resume action fires.
  final ValueChanged<ChoreWithDetails> onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Whole-section card (not per-row): matches ChoreDoneSection's choice —
    // see that file's comment and the #6 plan report. surfaceContainerHigh
    // ground + a leading icon (spec docs/specs/theme-v2.md §4.1 item 5);
    // the trailing chevron is ExpansionTile's own default.
    return DepthCard(
      color: theme.colorScheme.surfaceContainerHigh,
      child: ExpansionTile(
        leading: Icon(
          Icons.pause_circle_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: semantic(
          'chores.paused.header',
          child: Text(l10n.choresPausedHeader(chores.length)),
        ),
        children: [
          for (var i = 0; i < chores.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1),
            _PausedRow(
              details: chores[i],
              onResume: () => onResume(chores[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PausedRow extends StatelessWidget {
  const _PausedRow({required this.details, required this.onResume});

  final ChoreWithDetails details;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final category = details.category;

    return ListTile(
      title: Text(details.chore.title),
      subtitle: DefaultTextStyle.merge(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (category != null) CategoryBadge(category: category),
            Text(l10n.choresPausedBadge),
          ],
        ),
      ),
      trailing: semantic(
        'chores.paused.${details.chore.id}.resume',
        child: TextButton(
          onPressed: onResume,
          child: Text(l10n.choresPausedResume),
        ),
      ),
    );
  }
}
