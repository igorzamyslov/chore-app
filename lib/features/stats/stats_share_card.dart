/// The household share card on the chore-history overview (spec
/// `docs/specs/stats.md` §3.1).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// How one month's completed chores divided across the household.
///
/// **This is deliberately not a leaderboard** (spec `docs/specs/stats.md`
/// §0): entries render in the order given -- household roster order, which
/// the service guarantees -- and are NEVER re-sorted by count here. No rank
/// numbers, no winner styling, no streaks. Only `done` occurrences are
/// counted; `skipped` and `missed` never reach this widget.
///
/// Semantic id `stats.share`. Like `ChoreProgressCard`, the card carries one
/// [Semantics] label made of the sentences already on screen and excludes
/// every descendant text node, so a screen reader announces it once.
class StatsShareCard extends StatelessWidget {
  /// Creates the share card.
  const StatsShareCard({
    required this.shares,
    required this.totalDone,
    required this.windowStart,
    required this.clampedToHouseholdStart,
    super.key,
  });

  /// Share entries, already in roster order (see the class doc).
  final List<MemberShare> shares;

  /// Total completions across [shares].
  final int totalDone;

  /// First day of the window, used only when [clampedToHouseholdStart].
  final PlainDate windowStart;

  /// Whether the window was shortened to the household's own start date.
  final bool clampedToHouseholdStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final percentFormat = NumberFormat.percentPattern(localeName);

    final windowLabel = clampedToHouseholdStart
        ? l10n.statsWindowSinceStart(
            DateFormat.MMMMd(localeName).format(
              DateTime(windowStart.year, windowStart.month, windowStart.day),
            ),
          )
        : l10n.statsWindowLast30Days;
    final totalLabel = l10n.statsTotalDone(totalDone);

    String nameOf(MemberShare share) =>
        share.member?.name ?? l10n.statsShareUnknownMember;

    // Extracted rather than inlined into the row below: at four levels of
    // widget nesting the interpolation runs past the 80-column limit, and
    // `dart format` cannot break a string literal to fix it.
    String countAndPercent(MemberShare share) {
      final fraction = totalDone == 0 ? 0.0 : share.doneCount / totalDone;
      return '${share.doneCount} · ${percentFormat.format(fraction)}';
    }

    return semantic(
      'stats.share',
      child: Semantics(
        label: [
          windowLabel,
          totalLabel,
          for (final share in shares) '${nameOf(share)}: ${share.doneCount}',
        ].join('. '),
        child: ExcludeSemantics(
          child: DepthCard(
            shadow: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    windowLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(totalLabel, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          for (final share in shares)
                            if (share.doneCount > 0)
                              Expanded(
                                flex: share.doneCount,
                                child: ColoredBox(
                                  color: share.member == null
                                      ? theme.colorScheme.outlineVariant
                                      : categoryTone(
                                          context,
                                          share.member!.color,
                                        ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final share in shares)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          if (share.member case final Member member)
                            MemberAvatar(member: member, radius: 12)
                          else
                            Icon(
                              Icons.help_outline,
                              size: 24,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nameOf(share),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          Text(
                            countAndPercent(share),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
