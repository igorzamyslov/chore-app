/// The chores list screen (this feature's default tab).
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/acting_member_sheet.dart';
import 'package:chore_app/features/chores/active_chores_presence.dart';
import 'package:chore_app/features/chores/chore_action_sheet.dart';
import 'package:chore_app/features/chores/chore_delete_dialog.dart';
import 'package:chore_app/features/chores/chore_done_section.dart';
import 'package:chore_app/features/chores/chore_form_screen.dart';
import 'package:chore_app/features/chores/chore_occurrence_tile.dart';
import 'package:chore_app/features/chores/chore_paused_section.dart';
import 'package:chore_app/features/chores/chore_section.dart';
import 'package:chore_app/features/chores/chores_filter_bar.dart';
import 'package:chore_app/features/chores/digest_preprompt_banner.dart';
import 'package:chore_app/features/chores/onboarding_name_banner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists the household's pending chore occurrences, grouped into
/// overdue/today/tomorrow/this-week/this-month/later sections, plus the
/// collapsed paused and done-today sections.
class ChoresListScreen extends ConsumerStatefulWidget {
  /// Creates the chores list screen.
  const ChoresListScreen({super.key});

  @override
  ConsumerState<ChoresListScreen> createState() => _ChoresListScreenState();
}

class _ChoresListScreenState extends ConsumerState<ChoresListScreen> {
  String? _memberFilter;
  String? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final occurrencesAsync = ref.watch(pendingOccurrencesProvider);
    final closedToday = ref.watch(closedTodayOccurrencesProvider).value;
    final paused = ref.watch(pausedChoresProvider).value;
    final hasActiveChores = ref.watch(hasActiveChoresProvider).value ?? true;
    final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());

    return Scaffold(
      appBar: AppBar(
        leading: const ActingMemberButton(),
        title: Text(AppLocalizations.of(context).choresTabLabel),
        actions: [
          MemberFilterButton(
            selected: _memberFilter,
            onChanged: (value) => setState(() => _memberFilter = value),
          ),
          CategoryFilterButton(
            selected: _categoryFilter,
            onChanged: (value) => setState(() => _categoryFilter = value),
          ),
        ],
      ),
      // The first-run banners (spec docs/specs/polish-round-1.md A2/A3)
      // render above the list content, never blocking it: both are
      // self-hiding (SizedBox.shrink) when their own conditions don't hold,
      // so this Column adds nothing visible once a household is past both.
      body: Column(
        children: [
          const OnboardingNameBanner(),
          const DigestPrepromptBanner(),
          Expanded(
            child: occurrencesAsync.when(
              data: (occurrences) => _Body(
                occurrences: occurrences,
                closedToday: closedToday ?? const [],
                paused: paused ?? const [],
                hasActiveChores: hasActiveChores,
                today: today,
                memberFilter: _memberFilter,
                categoryFilter: _categoryFilter,
                onComplete: _complete,
                onOpenMenu: _openMenu,
                onReopen: _reopen,
                onResume: _resume,
                onClearFilters: _clearFilters,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorState(
                onRetry: () => ref.invalidate(pendingOccurrencesProvider),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: semantic(
        'chores.add',
        child: FloatingActionButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const ChoreFormScreen()),
          ),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Future<void> _complete(OccurrenceWithChore occurrence) async {
    // Credit goes to whoever ACTUALLY did it — the acting member — never
    // the assignee (user decision 2026-07-31; spec members-management.md
    // §4). Rotation is unaffected: it advances on assigned_member_id, not
    // completed_by. The assignee is only a defensive fallback for the
    // moment before actingMemberProvider has resolved.
    final completedBy =
        ref.read(actingMemberProvider)?.id ?? occurrence.assignedMember?.id;
    if (completedBy == null) {
      return;
    }
    await ref
        .read(choreServiceProvider)
        .completeOccurrence(occurrence.occurrence.id, completedBy: completedBy);
    if (!mounted) {
      return;
    }
    await _showCloseSnackbar(occurrence: occurrence, skipped: false);
  }

  Future<void> _openMenu(OccurrenceWithChore occurrence) async {
    final action = await showChoreActionSheet(context);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ChoreMenuAction.skip:
        await ref
            .read(choreServiceProvider)
            .skipOccurrence(occurrence.occurrence.id);
        if (!mounted) {
          return;
        }
        await _showCloseSnackbar(occurrence: occurrence, skipped: true);
      case ChoreMenuAction.edit:
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ChoreFormScreen(choreId: occurrence.chore.id),
          ),
        );
      case ChoreMenuAction.pause:
        await ref.read(choreServiceProvider).pauseChore(occurrence.chore.id);
      case ChoreMenuAction.delete:
        final confirmed = await showChoreDeleteDialog(
          context,
          choreTitle: occurrence.chore.title,
        );
        if (!mounted || !confirmed) {
          return;
        }
        await ref
            .read(choreRepositoryProvider)
            .softDeleteChore(occurrence.chore.id);
    }
  }

  /// Shows the undo snackbar after [occurrence] was completed or skipped
  /// (per [skipped]): 'Done'/'Skipped' for a one-off chore (no next
  /// occurrence), or '... — next due' plus the next occurrence's due text
  /// for a recurring one. The UNDO action reopens the just-closed
  /// occurrence.
  ///
  /// See `docs/specs/ux-round-2.md` A4.
  Future<void> _showCloseSnackbar({
    required OccurrenceWithChore occurrence,
    required bool skipped,
  }) async {
    final choreId = occurrence.chore.id;
    final occurrenceId = occurrence.occurrence.id;
    final nextPending = await ref
        .read(choreRepositoryProvider)
        .pendingOccurrenceOf(choreId);
    if (!mounted) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final String message;
    if (nextPending == null) {
      message = skipped ? l10n.choresSnackbarSkipped : l10n.choresSnackbarDone;
    } else {
      final localeName = Localizations.localeOf(context).toString();
      final today = PlainDate.fromDateTime(ref.read(clockProvider).now());
      final dueText = futureDueText(
        l10n,
        localeName,
        today: today,
        dueDate: nextPending.dueDate,
      );
      message = skipped
          ? l10n.choresSnackbarSkippedNextDue(dueText)
          : l10n.choresSnackbarDoneNextDue(dueText);
    }

    showAppSnackbar(
      context,
      message: message,
      action: SnackBarAction(
        label: l10n.choresSnackbarUndo,
        onPressed: () {
          unawaited(
            ref.read(choreServiceProvider).reopenOccurrence(occurrenceId),
          );
        },
      ),
    );
  }

  Future<void> _reopen(ClosedOccurrenceWithChore occurrence) {
    return ref
        .read(choreServiceProvider)
        .reopenOccurrence(occurrence.occurrence.id);
  }

  Future<void> _resume(ChoreWithDetails details) {
    return ref.read(choreServiceProvider).unpauseChore(details.chore.id);
  }

  /// Resets both filters (spec `docs/feedback/2026-08-01-ux-audit.md` B1's
  /// "Show everything" action).
  void _clearFilters() {
    setState(() {
      _memberFilter = null;
      _categoryFilter = null;
    });
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.occurrences,
    required this.closedToday,
    required this.paused,
    required this.hasActiveChores,
    required this.today,
    required this.memberFilter,
    required this.categoryFilter,
    required this.onComplete,
    required this.onOpenMenu,
    required this.onReopen,
    required this.onResume,
    required this.onClearFilters,
  });

  final List<OccurrenceWithChore> occurrences;
  final List<ClosedOccurrenceWithChore> closedToday;
  final List<ChoreWithDetails> paused;

  /// Whether the household has any active (non-deleted) chore at all —
  /// unfiltered, unlike [occurrences]/[closedToday]/[paused] above — the
  /// signal that distinguishes the "fresh install" empty state from "all
  /// done" (spec `docs/specs/polish-round-1.md` A1).
  final bool hasActiveChores;
  final PlainDate today;
  final String? memberFilter;
  final String? categoryFilter;
  final ValueChanged<OccurrenceWithChore> onComplete;
  final ValueChanged<OccurrenceWithChore> onOpenMenu;
  final ValueChanged<ClosedOccurrenceWithChore> onReopen;
  final ValueChanged<ChoreWithDetails> onResume;

  /// Resets both filters (spec `docs/feedback/2026-08-01-ux-audit.md` B1's
  /// "Show everything" action, wired to the filtered-empty state below).
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final filtered = occurrences.where((occurrence) {
      if (memberFilter != null &&
          occurrence.assignedMember?.id != memberFilter) {
        return false;
      }
      if (categoryFilter != null && occurrence.category?.id != categoryFilter) {
        return false;
      }
      return true;
    }).toList();

    // Active filters apply to the auxiliary sections too (ux-round-2 C2):
    // a filtered view is a filtered view of EVERYTHING, or the sections
    // contradict each other. Member semantics per section: done rows match
    // the person they display (completer for done, assignee for skipped);
    // paused chores match "member is among the assignees".
    final filteredClosedToday = closedToday.where((row) {
      if (categoryFilter != null && row.category?.id != categoryFilter) {
        return false;
      }
      if (memberFilter != null) {
        final displayedMemberId =
            row.occurrence.completedBy ?? row.assignedMember?.id;
        if (displayedMemberId != memberFilter) {
          return false;
        }
      }
      return true;
    }).toList();
    final filteredPaused = paused.where((details) {
      if (categoryFilter != null && details.category?.id != categoryFilter) {
        return false;
      }
      if (memberFilter != null &&
          !details.assigneeMemberIds.contains(memberFilter)) {
        return false;
      }
      return true;
    }).toList();

    final hasCollapsedSections =
        filteredPaused.isNotEmpty || filteredClosedToday.isNotEmpty;

    if (filtered.isEmpty && !hasCollapsedSections) {
      // B1 (spec docs/feedback/2026-08-01-ux-audit.md): a filter hiding
      // EVERYTHING is not the same as genuinely nothing pending -- the
      // unfiltered lists above (occurrences/closedToday/paused) are the
      // "would something show without the filter" signal; only when a
      // filter is active AND clearing it would actually reveal something
      // does the honest "nothing here for this filter" state replace the
      // fresh/done praise copy.
      final filterActive = memberFilter != null || categoryFilter != null;
      final hasUnfilteredContent =
          occurrences.isNotEmpty || closedToday.isNotEmpty || paused.isNotEmpty;
      if (filterActive && hasUnfilteredContent) {
        return Center(
          child: _ChoresEmptyFilteredState(onClear: onClearFilters),
        );
      }
      return Center(
        child: _ChoresEmptyState(fresh: !hasActiveChores),
      );
    }

    final bySection = <ChoreSection, List<OccurrenceWithChore>>{};
    for (final occurrence in filtered) {
      final section = sectionFor(
        today: today,
        dueDate: occurrence.occurrence.dueDate,
      );
      bySection.putIfAbsent(section, () => []).add(occurrence);
    }

    return ListView(
      // Clears the FAB: at large text sizes the FAB otherwise covers the
      // last section header (visual QA finding at AX2).
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: _ChoresEmptyState(fresh: !hasActiveChores)),
          )
        else
          for (final section in ChoreSection.values)
            if (bySection[section] case final tiles? when tiles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  section.label(AppLocalizations.of(context)),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final occurrence in tiles)
                ChoreOccurrenceTile(
                  occurrence: occurrence,
                  today: today,
                  section: section,
                  onComplete: () => onComplete(occurrence),
                  onOpenMenu: () => onOpenMenu(occurrence),
                ),
            ],
        if (filteredPaused.isNotEmpty)
          ChorePausedSection(chores: filteredPaused, onResume: onResume),
        if (filteredClosedToday.isNotEmpty)
          ChoreDoneSection(
            occurrences: filteredClosedToday,
            // Computed from the UNFILTERED closedToday (see that
            // function's doc comment on why filters mustn't affect it).
            reopenableOccurrenceIds: latestClosedTodayOccurrenceIds(
              closedToday,
            ),
            onReopen: onReopen,
          ),
      ],
    );
  }
}

/// The chores list's empty state — two distinct copies/icons sharing one
/// outer `chores.empty` container id (spec `docs/specs/polish-round-1.md`
/// A1): [fresh] (zero non-deleted chores in the household) invites adding
/// the first chore, child id `chores.empty.fresh`; otherwise the existing
/// "all done" praise copy, child id `chores.empty.done`. E2E flows that
/// assert the shared `chores.empty` id (e.g. after deleting the only
/// chore) keep passing regardless of which child renders.
class _ChoresEmptyState extends StatelessWidget {
  const _ChoresEmptyState({required this.fresh});

  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return semantic(
      'chores.empty',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            fresh ? Icons.add_task_outlined : Icons.task_alt_outlined,
            size: 48,
            color: color,
          ),
          const SizedBox(height: 8),
          semantic(
            fresh ? 'chores.empty.fresh' : 'chores.empty.done',
            child: Text(
              fresh ? l10n.choresEmptyFresh : l10n.choresEmptyState,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// The B1 filtered-empty state (spec
/// `docs/feedback/2026-08-01-ux-audit.md`): shown instead of
/// [_ChoresEmptyState] when a member/category filter is the reason nothing
/// is visible -- distinct copy plus a "Show everything" action, rather than
/// the unqualified "No chores pending" praise, which used to read as "my
/// chores are gone".
class _ChoresEmptyFilteredState extends StatelessWidget {
  const _ChoresEmptyFilteredState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return semantic(
      'chores.empty.filtered',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 48, color: color),
          const SizedBox(height: 8),
          Text(
            l10n.choresEmptyFiltered,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          semantic(
            'chores.filter.clear',
            child: TextButton(
              onPressed: onClear,
              child: Text(l10n.choresFilterClear),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.choresErrorMessage),
          const SizedBox(height: 8),
          semantic(
            'chores.error.retry',
            child: OutlinedButton(
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ),
        ],
      ),
    );
  }
}
