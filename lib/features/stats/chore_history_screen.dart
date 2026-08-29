/// One chore's completion log (spec `docs/specs/stats.md` §5).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Every recorded completion of one chore, newest first, capped at
/// [choreHistoryLimit] with an honest total above it.
///
/// Read-only by design: nothing here mutates an occurrence. Reopening a
/// completion lives where it always has (the chores list's Done-today
/// section, LIFO-restricted -- `docs/specs/occurrence-lifecycle.md`).
///
/// Reachable for a SOFT-DELETED chore too -- that is the entire point of
/// this screen (`docs/research/triage.md` D2): every other read path in the
/// app filters `deleted_at IS NULL`, which is what made "its history is
/// kept" unverifiable.
class ChoreHistoryScreen extends ConsumerWidget {
  /// Creates the log screen for [choreId].
  const ChoreHistoryScreen({required this.choreId, super.key});

  /// The chore whose completions are listed.
  final String choreId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final historyAsync = ref.watch(choreHistoryProvider(choreId));

    return Scaffold(
      appBar: AppBar(title: Text(historyAsync.valueOrNull?.chore.title ?? '')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.statsErrorMessage),
              const SizedBox(height: 8),
              semantic(
                'stats.history.error.retry',
                child: OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(choreHistoryProvider(choreId)),
                  child: Text(l10n.commonRetry),
                ),
              ),
            ],
          ),
        ),
        data: (history) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (history.chore.deletedAt != null)
              semantic(
                'stats.history.deletedNotice',
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.statsDeletedNotice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Text(
              l10n.statsTotalDone(history.totalDone),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final completion in history.recent)
              semantic(
                'stats.history.row.${completion.occurrence.id}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      if (completion.completedByMember case final member?)
                        MemberAvatar(member: member)
                      else
                        Icon(
                          Icons.help_outline,
                          size: 24,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          completion.completedByMember?.name ??
                              l10n.statsShareUnknownMember,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        completion.occurrence.closedOn == null
                            ? ''
                            : DateFormat.yMMMd(localeName).format(
                                DateTime(
                                  completion.occurrence.closedOn!.year,
                                  completion.occurrence.closedOn!.month,
                                  completion.occurrence.closedOn!.day,
                                ),
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (history.totalDone > history.recent.length)
              semantic(
                'stats.history.truncated',
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.statsHistoryTruncated(
                      history.recent.length,
                      history.totalDone,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
