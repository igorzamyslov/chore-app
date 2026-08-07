/// The chores list screen (this feature's default tab).
library;

import 'dart:async';

import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
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
import 'package:chore_app/features/chores/chore_progress_card.dart';
import 'package:chore_app/features/chores/chore_section.dart';
import 'package:chore_app/features/chores/chores_filter_bar.dart';
import 'package:chore_app/features/chores/digest_preprompt_banner.dart';
import 'package:chore_app/features/chores/onboarding_name_banner.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // C1 (spec docs/specs/sync-freshness.md §2.3): the pull-to-refresh
    // indicator is shown only when there's actually a remote to pull from --
    // the same linked-AND-signed-in gate `syncEngineProvider` itself applies
    // (see its doc comment, lib/app/providers.dart). A local-only household
    // has no remote, so an indicator that provably does nothing would be
    // exactly the dishonest affordance waves M and R removed.
    final syncLinked = ref.watch(syncEngineProvider) is! NoopSyncEngine;

    // Day-progress card counts (spec docs/specs/theme-v2.md §4.1 item 1),
    // derived from data this screen already watches -- deliberately
    // UNFILTERED (household-wide), like hasActiveChores above: the card is
    // a summary of the day, not of whatever member/category filter happens
    // to be active.
    final completedToday = (closedToday ?? const [])
        .where(
          (occurrence) => occurrence.occurrence.status == OccurrenceStatus.done,
        )
        .length;
    final pendingDueOrOverdue = (occurrencesAsync.value ?? const [])
        .where((occurrence) => !occurrence.occurrence.dueDate.isAfter(today))
        .length;

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
          // Only once occurrences have actually loaded -- avoids a
          // zero-count flash while pendingOccurrencesProvider's stream is
          // still resolving. ChoreProgressCard hides itself when M == 0.
          if (occurrencesAsync.hasValue)
            ChoreProgressCard(
              completedToday: completedToday,
              pendingDueOrOverdue: pendingDueOrOverdue,
              today: today,
            ),
          Expanded(
            child: occurrencesAsync.when(
              data: (occurrences) {
                final body = _Body(
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
                );
                if (!syncLinked) {
                  return body;
                }
                // Success is silent (spec §2.3): the list simply updates,
                // which is the platform convention -- no snackbar here.
                return semantic(
                  'chores.refresh',
                  child: RefreshIndicator(
                    // Field feedback 2026-08-07 C1: the spinner read as too
                    // eager. Flutter draws it from the first pixel of
                    // over-scroll and fires at a fixed 25% of viewport
                    // extent -- the trigger distance is not a parameter --
                    // so `displacement` (default 40) is the only lever: it
                    // sets how far down the indicator settles, and a larger
                    // value means more drag before it reads as present.
                    displacement: 88,
                    onRefresh: () => ref.read(syncEngineProvider).pushDirty(),
                    child: body,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorState(
                onRetry: () => ref.invalidate(pendingOccurrencesProvider),
              ),
            ),
          ),
        ],
      ),
      // The theme already sets the FAB's 20dp RoundedSuperellipseBorder
      // shape and primary/onPrimary colors (lib/app/theme.dart); this
      // Container just adds FamdoColors.fabShadow underneath so it reads as
      // raised (spec docs/specs/theme-v2.md §4.1 item 6) -- the FAB itself
      // stays elevation: 0 (spec §7.7).
      floatingActionButton: semantic(
        'chores.add',
        child: Container(
          decoration: ShapeDecoration(
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            shadows: famdoColors(context).fabShadow,
          ),
          child: FloatingActionButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ChoreFormScreen()),
            ),
            child: const Icon(Icons.add),
          ),
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
    // C3 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
    // haptic feedback, not animation -- doesn't touch the "no custom
    // animation" rule (design-language.md's Motion bullet) or E2E
    // determinism, so a future reader shouldn't "fix" this away. Fired here,
    // once the write is confirmed, rather than in the tile's onTap, so it
    // fires exactly once per real completion.
    unawaited(HapticFeedback.mediumImpact());
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
      final empty = filterActive && hasUnfilteredContent
          ? _ChoresEmptyFilteredState(onClear: onClearFilters)
          : _ChoresEmptyState(fresh: !hasActiveChores);
      // Scrollable (not a bare Center): a RefreshIndicator higher up the
      // tree (C1, spec docs/specs/sync-freshness.md §2.3) needs a
      // Scrollable descendant to detect the pull gesture, and that must
      // hold even when there's nothing to show -- an indicator that only
      // "works" on a populated list would be exactly the kind of
      // provably-does-nothing affordance waves M and R removed.
      return _ScrollableEmptyState(child: empty);
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
      // C8 (conventions audit): dismisses the keyboard on a scroll drag --
      // this screen has no text field of its own today, but the filter
      // sheets/menus it opens can leave one focused, and this is the
      // convention every scrollable list in the app follows.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: _ChoresEmptyState(fresh: !hasActiveChores)),
          )
        else
          for (final section in ChoreSection.values)
            if (bySection[section] case final tiles? when tiles.isNotEmpty) ...[
              _SectionHeader(section: section, count: tiles.length),
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

/// Wraps an empty-state [child] in a scrollable that fills the available
/// height (`SliverFillRemaining(hasScrollBody: false)`), so the
/// [RefreshIndicator] wrapping this screen's list (C1, spec
/// `docs/specs/sync-freshness.md` §2.3) still has a `Scrollable` descendant
/// to detect a pull gesture even when there is nothing to show -- otherwise
/// the indicator would silently do nothing on every empty/filtered-empty
/// state, exactly the dishonest affordance waves M and R removed.
class _ScrollableEmptyState extends StatelessWidget {
  const _ScrollableEmptyState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
      ],
    );
  }
}

/// A due-date section's header (spec `docs/specs/theme-v2.md` §4.1 item 2,
/// amending `docs/specs/design-language.md`'s whitespace-only header):
/// `labelSmall` uppercase in `onSurfaceVariant` (`error` for Overdue) --
/// produced by the widget via `.toUpperCase()`, never by an already-
/// uppercase ARB string, so German capitalization stays natural in the
/// translator's source -- a 1px `outlineVariant` hairline rule filling the
/// remaining width, then the section's item [count] in `labelMedium`.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.count});

  final ChoreSection section;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = section == ChoreSection.overdue;
    final labelColor = isOverdue
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    final label = section.label(AppLocalizations.of(context));

    // Addressable by id, not by text: the header's own label and its count
    // merge into ONE accessibility node ("Today\n1"), and Maestro matches
    // node text exactly -- so a text assertion on a section header breaks
    // the moment the header gains (or loses) anything alongside the label.
    // Proven live 2026-08-06 when the count landed. Ids are this suite's
    // contract; text is presentation.
    return semantic(
      'chores.section.${section.name}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            // Uppercase is TYPOGRAPHY, not content: the accessibility label
            // keeps the natural-case string, so TalkBack announces "Today"
            // rather than shouting/spelling "TODAY", and so the Maestro flows
            // keep matching meaning instead of casing (Maestro's text
            // matching is case-sensitive -- proven live 2026-08-06, when
            // uppercasing alone broke four chores flows).
            Semantics(
              label: label,
              child: ExcludeSemantics(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: labelColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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

    return semantic(
      'chores.empty',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EmptyStateIcon(
            icon: fresh ? Icons.add_task_outlined : Icons.task_alt_outlined,
          ),
          const SizedBox(height: 16),
          Text(
            fresh
                ? l10n.choresEmptyFreshHeadline
                : l10n.choresEmptyDoneHeadline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          semantic(
            fresh ? 'chores.empty.fresh' : 'chores.empty.done',
            child: Text(
              fresh ? l10n.choresEmptyFresh : l10n.choresEmptyState,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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

    return semantic(
      'chores.empty.filtered',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _EmptyStateIcon(icon: Icons.filter_alt_off_outlined),
          const SizedBox(height: 16),
          Text(
            l10n.choresEmptyFilteredHeadline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.choresEmptyFiltered,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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

/// The empty state's 76dp icon tile (spec `docs/specs/theme-v2.md` §4.1
/// item 6): `primaryContainer` fill, a `FamdoColors.primaryOutline` border,
/// and a centered glyph.
class _EmptyStateIcon extends StatelessWidget {
  const _EmptyStateIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: famdoColors(context).primaryOutline),
      ),
      child: Icon(
        icon,
        size: 36,
        color: theme.colorScheme.onPrimaryContainer,
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
