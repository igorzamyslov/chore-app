/// The chore form's assignment-mode and assignee-picker controls.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/member_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The assignment mode segmented control (spec `docs/specs/theme-v2.md`
/// §4.4 item 2) plus its dependent assignee controls.
///
/// `fixed` shows a single-select chip row (exactly one member must be
/// picked) and `anyone` shows none. `rotation` (backlog B-4 / triage
/// T2.5, `docs/plans/2026-08-08-rotation-reorder.md`) shows two parts:
/// already-selected members as a compact reorderable list — drag handle,
/// avatar, tap-order label, remove button — so the order can be edited
/// directly instead of only rebuilt by deselect-then-reselect; and
/// not-yet-selected members as a plain tap-to-add chip row underneath,
/// same as before. A trailing 'Add member…' chip (spec
/// `docs/feedback/2026-08-01-ux-audit.md` B2) closes the not-yet-selected
/// row, opening the new-member sheet inline so a missing person can be
/// added without abandoning the form -- the chip row refreshes
/// automatically once they're saved, since the caller
/// (`ChoreFormScreen`) watches `membersProvider` and passes the live
/// [members] list down.
class AssignmentFields extends StatelessWidget {
  /// Creates the assignment fields.
  const AssignmentFields({
    required this.mode,
    required this.onModeChanged,
    required this.members,
    required this.selectedMemberIds,
    required this.onMemberTap,
    required this.onReorder,
    this.errorText,
    super.key,
  });

  /// The currently-selected assignment mode.
  final AssignmentMode mode;

  /// Called when a different assignment mode is picked.
  final ValueChanged<AssignmentMode> onModeChanged;

  /// Every household member, selectable as an assignee.
  final List<Member> members;

  /// The currently-selected member ids. For `fixed`, 0 or 1 entries; for
  /// `rotation`, in rotation order (used for the visible order badges and
  /// the reorderable list's row order).
  final List<String> selectedMemberIds;

  /// Called when a member chip (unselected, or the selected row's remove
  /// button) is tapped; the caller decides how the selection changes
  /// based on [mode]. Selecting an unselected member always appends it to
  /// the end of [selectedMemberIds]; tapping a selected row's remove
  /// button removes it -- identical net effect to today's re-tap-to
  /// -remove chip gesture.
  final ValueChanged<String> onMemberTap;

  /// Called when the rotation reorder list moves an item, with the SAME
  /// already-adjusted-for-removal indices `ReorderableListView.builder`'s
  /// `onReorderItem` provides (no manual off-by-one correction needed by
  /// the caller). Unused outside [AssignmentMode.rotation].
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Inline validation error, or `null` if the current selection is valid.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AssignmentMode>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: [
            for (final entry in AssignmentMode.values)
              ButtonSegment(
                value: entry,
                label: semantic(
                  'chore_form.assignment.${entry.name}',
                  child: Text(_modeLabel(context, entry)),
                ),
              ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) => onModeChanged(selection.first),
        ),
        if (mode == AssignmentMode.rotation) ...[
          const SizedBox(height: 8),
          _RotationAssigneeControls(
            members: members,
            selectedMemberIds: selectedMemberIds,
            onMemberTap: onMemberTap,
            onReorder: onReorder,
          ),
        ] else if (mode == AssignmentMode.fixed) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in members)
                semantic(
                  'chore_form.assignee.${member.id}',
                  child: FilterChip(
                    // The selection checkmark would otherwise paint over
                    // the avatar (Flutter darkens+overlays it), hiding the
                    // exact thing this chip most needs to show once
                    // picked; the chip's own selected styling already
                    // conveys the state without it.
                    showCheckmark: false,
                    avatar: MemberAvatar(member: member, radius: 12),
                    label: Text(member.name),
                    selected: selectedMemberIds.contains(member.id),
                    onSelected: (_) => onMemberTap(member.id),
                  ),
                ),
              _addMemberChip(context),
            ],
          ),
        ],
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  String _modeLabel(BuildContext context, AssignmentMode mode) {
    final l10n = AppLocalizations.of(context);
    switch (mode) {
      case AssignmentMode.fixed:
        return l10n.choreFormAssignmentFixed;
      case AssignmentMode.rotation:
        return l10n.choreFormAssignmentRotation;
      case AssignmentMode.anyone:
        return l10n.choreFormAssignmentAnyone;
    }
  }
}

/// Builds the "Add member…" chip shared by the fixed-mode chip row and the
/// rotation-mode not-yet-selected chip row.
Widget _addMemberChip(BuildContext context) {
  return semantic(
    'chore_form.assignee.add',
    child: ActionChip(
      avatar: const Icon(Icons.add, size: 18),
      label: Text(AppLocalizations.of(context).choreFormAddMember),
      onPressed: () => showMemberEditSheet(context),
    ),
  );
}

/// Rotation mode's assignee controls: a reorderable list of already
/// -selected members, then a chip row of not-yet-selected ones.
class _RotationAssigneeControls extends StatelessWidget {
  const _RotationAssigneeControls({
    required this.members,
    required this.selectedMemberIds,
    required this.onMemberTap,
    required this.onReorder,
  });

  final List<Member> members;
  final List<String> selectedMemberIds;
  final ValueChanged<String> onMemberTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final member in members) member.id: member};
    // Resolve-and-skip rather than `members.firstWhere(...)`: a selected id
    // with no matching row in [members] is rare but genuinely reachable --
    // `ChoreFormScreen` reads `membersProvider` as `.value ?? const []`, so
    // an edit-an-existing-rotation build can land in a frame where the
    // assignee ids are loaded but the roster stream has not emitted yet;
    // and `chore_assignees` has no tombstones (`docs/specs/sync-backend.md`
    // §8.5), so a pulled assignee row can outlive its member until the next
    // full edit converges it. Throwing there would take the whole form
    // down; dropping the unresolvable row degrades the same way the old
    // chip row did (it simply rendered nothing for such an id).
    final selected = [
      for (final id in selectedMemberIds)
        if (byId[id] case final member?) member,
    ];
    final unselected = [
      for (final member in members)
        if (!selectedMemberIds.contains(member.id)) member,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isNotEmpty)
          // Embedding a ReorderableListView inside the form's outer,
          // already-scrollable ListView (chore_form_screen.dart) needs
          // shrinkWrap + disabled physics, same as any nested list in a
          // scrollable -- this list is always short (household member
          // count), so there's no lost scroll performance from sizing it
          // to content.
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: selected.length,
            itemBuilder: (context, index) {
              final member = selected[index];
              return _RotationRow(
                key: ValueKey(member.id),
                member: member,
                index: index,
                order: index + 1,
                onRemove: () => onMemberTap(member.id),
              );
            },
            onReorderItem: onReorder,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final member in unselected)
              semantic(
                'chore_form.assignee.${member.id}',
                child: FilterChip(
                  avatar: MemberAvatar(member: member, radius: 12),
                  label: Text(member.name),
                  selected: false,
                  onSelected: (_) => onMemberTap(member.id),
                ),
              ),
            _addMemberChip(context),
          ],
        ),
      ],
    );
  }
}

/// One row of the rotation reorder list: drag handle, avatar, tap-order
/// label, remove button.
///
/// The drag handle is a sibling of the row's other content, not an
/// ancestor/descendant of any tappable widget -- nesting it inside one
/// would put an `ImmediateMultiDragGestureRecognizer` and a tap recognizer
/// in the same gesture arena for the same pointer (same reasoning as
/// `manage_categories_screen.dart`'s `_CategoryRow`).
class _RotationRow extends StatelessWidget {
  const _RotationRow({
    required this.member,
    required this.index,
    required this.order,
    required this.onRemove,
    super.key,
  });

  final Member member;
  final int index;
  final int order;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'chore_form.assignee.${member.id}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            semantic(
              'chore_form.assignee.${member.id}.drag',
              child: ReorderableDragStartListener(
                index: index,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.drag_indicator),
                ),
              ),
            ),
            MemberAvatar(member: member, radius: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.choreFormAssigneeOrderLabel(order, member.name)),
            ),
            semantic(
              'chore_form.assignee.${member.id}.remove',
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.choreFormAssigneeRemoveTooltip(member.name),
                onPressed: onRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
