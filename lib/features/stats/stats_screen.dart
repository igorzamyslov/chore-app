/// The chore-history overview (spec `docs/specs/stats.md` §3).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:chore_app/features/stats/chore_history_screen.dart';
import 'package:chore_app/features/stats/stats_share_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// "Who actually does the chores": a household share for the last 30 days,
/// then every chore that has ever been completed, then a collapsed section
/// of deleted chores whose history is still kept.
///
/// The anti-leaderboard rules that govern this screen are in spec
/// `docs/specs/stats.md` §0 and are binding: only `done` is attributed, the
/// share is roster-ordered rather than ranked, the chore list is
/// alphabetical rather than sorted by count, and there is no per-member
/// drill-down.
class StatsScreen extends ConsumerWidget {
  /// Creates the chore-history overview.
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overviewAsync = ref.watch(statsOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: overviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.statsErrorMessage),
              const SizedBox(height: 8),
              semantic(
                'stats.error.retry',
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(statsOverviewProvider),
                  child: Text(l10n.commonRetry),
                ),
              ),
            ],
          ),
        ),
        data: (overview) => _Body(overview: overview),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.overview});

  final StatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (overview.activeChores.isEmpty && overview.deletedChores.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        if (overview.shares.length >= 2)
          StatsShareCard(
            shares: overview.shares,
            totalDone: overview.totalDone,
            windowStart: overview.windowStart,
            clampedToHouseholdStart: overview.windowClampedToHouseholdStart,
          )
        else
          semantic(
            'stats.total',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 16, 8),
              child: Text(
                l10n.statsTotalDone(overview.totalDone),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
        _SectionHeader(label: l10n.statsChoresSectionTitle),
        for (final rollup in overview.activeChores) _ChoreRow(rollup: rollup),
        if (overview.deletedChores.isNotEmpty)
          DepthCard(
            child: semantic(
              'stats.deleted',
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  l10n.statsDeletedSectionHeader(overview.deletedChores.length),
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  for (final rollup in overview.deletedChores)
                    _ChoreRow(rollup: rollup, insideCard: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// One chore's row: title, category badge, and "{n} times · last {date}" --
/// both figures all-time (spec §3.2), never windowed.
class _ChoreRow extends StatelessWidget {
  const _ChoreRow({required this.rollup, this.insideCard = false});

  final ChoreDoneRollup rollup;

  /// When true the row is already inside the deleted section's card, so it
  /// does not wrap itself in another [DepthCard].
  final bool insideCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final last = DateFormat.yMMMd(localeName).format(
      DateTime(
        rollup.lastDoneOn.year,
        rollup.lastDoneOn.month,
        rollup.lastDoneOn.day,
      ),
    );

    final tile = semantic(
      'stats.chore.${rollup.chore.id}',
      child: ListTile(
        title: Text(rollup.chore.title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          '${l10n.statsChoreTimesDone(rollup.doneAllTime)} · '
          '${l10n.statsChoreLastDone(last)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: rollup.category == null
            ? null
            : CategoryBadge(category: rollup.category!),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChoreHistoryScreen(choreId: rollup.chore.id),
          ),
        ),
      ),
    );

    return insideCard ? tile : DepthCard(child: tile);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final famdo = famdoColors(context);
    return semantic(
      'stats.empty',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: famdo.primaryOutline),
                ),
                child: Icon(
                  Icons.history_outlined,
                  size: 34,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.statsEmptyTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                l10n.statsEmptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
