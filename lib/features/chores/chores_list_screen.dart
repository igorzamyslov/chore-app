/// The chores list screen (this feature's default tab).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/chore_action_sheet.dart';
import 'package:chore_app/features/chores/chore_delete_dialog.dart';
import 'package:chore_app/features/chores/chore_form_screen.dart';
import 'package:chore_app/features/chores/chore_occurrence_tile.dart';
import 'package:chore_app/features/chores/chore_section.dart';
import 'package:chore_app/features/chores/chores_filter_bar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists the household's pending chore occurrences, grouped into
/// overdue/today/tomorrow/this-week/later sections.
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
    final today = PlainDate.fromDateTime(ref.watch(clockProvider).now());

    return Scaffold(
      appBar: AppBar(
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
      body: occurrencesAsync.when(
        data: (occurrences) => _Body(
          occurrences: occurrences,
          today: today,
          memberFilter: _memberFilter,
          categoryFilter: _categoryFilter,
          onComplete: _complete,
          onOpenMenu: _openMenu,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          onRetry: () => ref.invalidate(pendingOccurrencesProvider),
        ),
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
    final completedBy =
        occurrence.assignedMember?.id ?? ref.read(actingMemberProvider)?.id;
    if (completedBy == null) {
      return;
    }
    await ref
        .read(choreServiceProvider)
        .completeOccurrence(occurrence.occurrence.id, completedBy: completedBy);
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
}

class _Body extends StatelessWidget {
  const _Body({
    required this.occurrences,
    required this.today,
    required this.memberFilter,
    required this.categoryFilter,
    required this.onComplete,
    required this.onOpenMenu,
  });

  final List<OccurrenceWithChore> occurrences;
  final PlainDate today;
  final String? memberFilter;
  final String? categoryFilter;
  final ValueChanged<OccurrenceWithChore> onComplete;
  final ValueChanged<OccurrenceWithChore> onOpenMenu;

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

    if (filtered.isEmpty) {
      return Center(
        child: semantic(
          'chores.empty',
          child: Text(AppLocalizations.of(context).choresEmptyState),
        ),
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
      children: [
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
                isOverdue: section == ChoreSection.overdue,
                onComplete: () => onComplete(occurrence),
                onOpenMenu: () => onOpenMenu(occurrence),
              ),
          ],
      ],
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
