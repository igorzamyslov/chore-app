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
import 'package:chore_app/features/chores/catch_up_banner.dart';
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
import 'package:chore_app/features/chores/mark_done_for_sheet.dart';
import 'package:chore_app/features/chores/onboarding_name_banner.dart';
import 'package:chore_app/features/sync/sync_health_banner.dart';
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
    // todayProvider, not a one-shot clock read: this is what re-buckets the
    // list at local midnight while the app stays open (backlog A-2 / audit
    // P1). It flows down to ChoreSection, every tile's due text, and the
    // progress card as a plain parameter, so this single watch covers them.
    final today = ref.watch(todayProvider);
    // C1 (spec docs/specs/sync-freshness.md §2.3): the pull-to-refresh
    // indicator is shown only when there's actually a remote to pull from --
    // the same linked-AND-signed-in gate `syncEngineProvider` itself applies
    // (see its doc comment, lib/app/providers.dart). A local-only household
    // has no remote, so an indicator that provably does nothing would be
    // exactly the dishonest affordance waves M and R removed.
    final syncLinked = ref.watch(syncEngineProvider) is! NoopSyncEngine;

    // Day-progress card counts (spec docs/specs/theme-v2.md §4.1 item 1).
    // Changed 2026-08-07 (triage T1.1/D3): these used to be computed
    // UNFILTERED (household-wide) on the theory that the card is a summary
    // of the day, not of whatever member/category filter happens to be
    // active. That's reversed now -- it let the card read "3 of 8 done
    // today" while a member filter showed a list of 2 underneath, which is
    // exactly the "a number disagrees with the list beneath it" failure
    // mode this app exists to avoid. `_filterOccurrences`/
    // `_filterClosedToday` below are the SAME functions `_Body` uses to
    // build the sections themselves, so the card's numbers and the list can
    // never disagree -- and when a filter is active, the card says so (see
    // ChoreProgressCard.filterActive).
    final filterActive = _memberFilter != null || _categoryFilter != null;
    final filteredOccurrencesForCount = _filterOccurrences(
      occurrencesAsync.value ?? const [],
      memberFilter: _memberFilter,
      categoryFilter: _categoryFilter,
    );
    final filteredClosedTodayForCount = _filterClosedToday(
      closedToday ?? const [],
      memberFilter: _memberFilter,
      categoryFilter: _categoryFilter,
    );
    final completedToday = filteredClosedTodayForCount
        .where(
          (occurrence) => occurrence.occurrence.status == OccurrenceStatus.done,
        )
        .length;
    final pendingDueOrOverdue = filteredOccurrencesForCount
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
      body: Column(
        children: [
          const _BannerRegion(),
          // Only once occurrences have actually loaded -- avoids a
          // zero-count flash while pendingOccurrencesProvider's stream is
          // still resolving. ChoreProgressCard hides itself when M == 0.
          if (occurrencesAsync.hasValue)
            ChoreProgressCard(
              completedToday: completedToday,
              pendingDueOrOverdue: pendingDueOrOverdue,
              today: today,
              filterActive: filterActive,
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
                    onRefresh: () => _refresh(context, ref),
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
      // Reachable since T1.3: pinned mode with no claim resolved yet (e.g.
      // right after adopting, before the first pull -- spec
      // `docs/specs/members-management.md` §4.2) and no assignee to fall
      // back on. Before T1.3, actingMemberProvider could never be null
      // while members existed, so this was a silent no-op; now it must say
      // something rather than let the tap vanish with no feedback.
      if (!mounted) {
        return;
      }
      showAppSnackbar(
        context,
        message: AppLocalizations.of(context).choresSnackbarNoActingMember,
      );
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

  /// The rare "I finished something for someone else" path (A-5, spec
  /// `docs/feedback/2026-08-07-field-feedback.md` B1): pick a member, then
  /// close the occurrence crediting THEM.
  ///
  /// Deliberately NOT a new `ChoreService` method: `completeOccurrence`
  /// already takes the credited member, and rotation advances on
  /// `assigned_member_id` rather than `completed_by`, so this differs from
  /// [_complete] only in which id it passes. It also never writes
  /// `settings.actingMemberId` — crediting somebody is not becoming them.
  Future<void> _markDoneFor(OccurrenceWithChore occurrence) async {
    final members = ref.read(membersProvider).value ?? const <Member>[];
    final picked = await showMarkDoneForSheet(
      context,
      members: members,
      excludeMemberId: ref.read(claimedMemberProvider)?.id,
    );
    if (!mounted || picked == null) {
      return;
    }
    await ref
        .read(choreServiceProvider)
        .completeOccurrence(occurrence.occurrence.id, completedBy: picked.id);
    unawaited(HapticFeedback.mediumImpact());
    if (!mounted) {
      return;
    }
    await _showCloseSnackbar(
      occurrence: occurrence,
      skipped: false,
      creditedTo: picked,
    );
  }

  Future<void> _openMenu(OccurrenceWithChore occurrence) async {
    // A-5 gate (spec docs/feedback/2026-08-07-field-feedback.md B1):
    // "Mark done for…" replaces the app-bar switcher, so it is offered in
    // exactly the state where that switcher is gone -- and only when there
    // is somebody else to credit.
    final pinned =
        ref.read(memberIdentityModeProvider) == MemberIdentityMode.pinned;
    final memberCount = ref.read(membersProvider).value?.length ?? 0;
    final action = await showChoreActionSheet(
      context,
      showMarkDoneFor: pinned && memberCount > 1,
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case ChoreMenuAction.markDoneFor:
        await _markDoneFor(occurrence);
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
        await _pause(occurrence);
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

  /// Pauses [occurrence]'s chore and confirms it with a snackbar whose
  /// UNDO action resumes it (T1.5, triage.md): every other state-changing
  /// action here (complete, skip, delete) already snackbars, but pause used
  /// to change state silently, leaving a collapsed "Paused" section as its
  /// only -- easy to miss -- recovery path. Built the same way as
  /// [_showCloseSnackbar]: [showAppSnackbar] with an action, which is
  /// `persist: false` internally so the bar still auto-dismisses.
  Future<void> _pause(OccurrenceWithChore occurrence) async {
    final choreId = occurrence.chore.id;
    await ref.read(choreServiceProvider).pauseChore(choreId);
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    showAppSnackbar(
      context,
      message: l10n.choresSnackbarPaused,
      action: SnackBarAction(
        label: l10n.choresSnackbarUndo,
        onPressed: () {
          unawaited(ref.read(choreServiceProvider).unpauseChore(choreId));
        },
      ),
    );
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
    Member? creditedTo,
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
    // A-5: on the "Mark done for…" path the credited member is NOT the
    // person holding the phone, so the confirmation says whose credit it
    // was. The next-due variants are skipped here deliberately — WHO got
    // the credit is the fact worth confirming on this path, and the chore's
    // next occurrence is visible in the list behind the bar anyway.
    if (creditedTo != null) {
      showAppSnackbar(
        context,
        message: l10n.choresSnackbarDoneBy(creditedTo.name),
        action: SnackBarAction(
          label: l10n.choresSnackbarUndo,
          onPressed: () {
            unawaited(
              ref.read(choreServiceProvider).reopenOccurrence(occurrenceId),
            );
          },
        ),
      );
      return;
    }
    final String message;
    if (nextPending == null) {
      message = skipped ? l10n.choresSnackbarSkipped : l10n.choresSnackbarDone;
    } else {
      final localeName = Localizations.localeOf(context).toString();
      // The same "today" the list itself is bucketing on, so the snackbar's
      // "next due …" text can never contradict the section the chore lands
      // in a frame later.
      final today = ref.read(todayProvider);
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

/// The chores list's banner stack: everything that may appear above the list
/// content without ever blocking it.
///
/// **Adding a banner?** Add it here, and only here. Every member of this
/// region must be self-hiding — returning `SizedBox.shrink()` when its own
/// condition doesn't hold — so the region collapses to nothing at all in the
/// ordinary case, which is what lets them be listed unconditionally.
///
/// Order is by urgency to the person looking at the screen right now, not by
/// age of the feature:
///
/// 1. [SyncHealthBanner] — this device hasn't reached the household in a
///    while (backlog D-5, spec `docs/specs/sync-freshness.md` §2.5). First
///    because it is the only member that QUALIFIES everything else on the
///    screen: if sync is not getting through, the list may be missing other
///    members' changes and this person's own completions may not have
///    arrived, so reading it changes how you read the tiles — and it is the
///    only member naming an action the user can take right now. The other
///    three are, in their different ways, retrospective or evergreen.
/// 2. [CatchUpBanner] — what just happened to your chores (backlog B-1).
///    Somebody returning after a lapse needs the explanation for the overdue
///    tiles they are already looking at before anything evergreen, but that
///    explanation is retrospective and needs no action.
/// 3. [OnboardingNameBanner] — first-run name prompt (spec
///    `docs/specs/polish-round-1.md` A2).
/// 4. [DigestPrepromptBanner] — first-run digest prompt (spec A3, which
///    requires it to sit below A2).
///
/// `MainAxisSize.min` is load-bearing: this sits inside the screen's own
/// unbounded [Column], so a max-height nested column would overflow.
class _BannerRegion extends StatelessWidget {
  const _BannerRegion();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SyncHealthBanner(),
        CatchUpBanner(),
        OnboardingNameBanner(),
        DigestPrepromptBanner(),
      ],
    );
  }
}

/// Runs a USER-INITIATED sync and reports failure (spec
/// `docs/specs/sync-freshness.md` §2.3).
///
/// Uses `refreshNow()`, not `pushDirty()`: the latter swallows every error
/// by contract (spec `sync-backend.md` §8.3), so the indicator used to spin
/// and stop identically whether the sync worked or the phone was offline --
/// found by the 2026-08-07 persona walkthrough. Success stays silent; the
/// list simply updates, which is the platform convention.
Future<void> _refresh(BuildContext context, WidgetRef ref) async {
  final ok = await ref.read(syncEngineProvider).refreshNow();
  if (ok || !context.mounted) {
    return;
  }
  // WHEN THIS BRANCH IS ACTUALLY REACHED, which is narrower than it looks:
  // `syncEngineProvider` is gated on `settings.syncHouseholdId`, and the
  // engine's own startup pull and 60s poll run this same revocation probe. So
  // in the common case the ENGINE notices first, calls `clearSyncLink()`, and
  // `syncEngineProvider` becomes a `NoopSyncEngine` whose `refreshNow()`
  // returns true -- meaning a later pull-to-refresh reports success and says
  // nothing. That is not a gap: a device that has been revoked is told so by
  // the revocation notice (spec `docs/specs/household-lifecycle.md` §3.5),
  // which is the primary surface. This string covers the narrower race where
  // the user's own gesture is the first probe after the server-side removal,
  // and it exists because in exactly that case `syncRefreshError`'s "will
  // sync later" is a promise the app has already made false.
  // refreshNow() returns false for two different situations, and only one of
  // them is a delay. If the failure was a revocation, `_pullSinceInner` has
  // ALREADY called setMembershipRevoked() and clearSyncLink() before
  // returning -- so syncRefreshError's "will sync later" is not optimism, it
  // is false. Read the just-written row with a one-shot query rather than
  // settingsProvider's stream, which may not have re-emitted the write yet.
  final revoked = (await ref.read(settingsRepositoryProvider).ensureSettings())
      .membershipRevoked;
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  showAppSnackbar(
    context,
    message: revoked ? l10n.syncRefreshErrorRevoked : l10n.syncRefreshError,
  );
}

/// Filters [occurrences] to the active member/category filter (`null` for
/// either means "no restriction") -- shared by the day-progress card's
/// counts (`_ChoresListScreenState.build`) and the sections `_Body` renders
/// (T1.1/D3, spec `docs/specs/theme-v2.md` §4.1 item 1), so both are
/// computed from literally the same rule and can never disagree.
List<OccurrenceWithChore> _filterOccurrences(
  List<OccurrenceWithChore> occurrences, {
  required String? memberFilter,
  required String? categoryFilter,
}) {
  return occurrences.where((occurrence) {
    if (memberFilter != null && occurrence.assignedMember?.id != memberFilter) {
      return false;
    }
    if (categoryFilter != null && occurrence.category?.id != categoryFilter) {
      return false;
    }
    return true;
  }).toList();
}

/// Filters [closedToday] the same way (see [_filterOccurrences]), matching
/// each row's DISPLAYED member -- the completer for a done row, the
/// assignee for a skipped one (skipping doesn't record a dedicated closer).
List<ClosedOccurrenceWithChore> _filterClosedToday(
  List<ClosedOccurrenceWithChore> closedToday, {
  required String? memberFilter,
  required String? categoryFilter,
}) {
  return closedToday.where((row) {
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
    // These call the SAME top-level functions the day-progress card's
    // counts use (T1.1/D3, spec docs/specs/theme-v2.md §4.1 item 1), so the
    // card and these sections are provably filtered by the same rule.
    final filtered = _filterOccurrences(
      occurrences,
      memberFilter: memberFilter,
      categoryFilter: categoryFilter,
    );

    // Active filters apply to the auxiliary sections too (ux-round-2 C2):
    // a filtered view is a filtered view of EVERYTHING, or the sections
    // contradict each other. Member semantics per section: done rows match
    // the person they display (completer for done, assignee for skipped);
    // paused chores match "member is among the assignees".
    final filteredClosedToday = _filterClosedToday(
      closedToday,
      memberFilter: memberFilter,
      categoryFilter: categoryFilter,
    );
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
