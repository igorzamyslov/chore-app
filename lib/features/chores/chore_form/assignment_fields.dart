/// The chore form's assignment-mode and assignee-picker controls.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';

/// The assignment mode segmented row plus its dependent assignee chips.
///
/// `fixed` shows a single-select chip row (exactly one member must be
/// picked); `rotation` shows a multi-select chip row where each selected
/// chip carries a visible order badge reflecting tap order (at least two
/// members must be picked); `anyone` shows no assignee chips.
class AssignmentFields extends StatelessWidget {
  /// Creates the assignment fields.
  const AssignmentFields({
    required this.mode,
    required this.onModeChanged,
    required this.members,
    required this.selectedMemberIds,
    required this.onMemberTap,
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
  /// `rotation`, in tap order (used for the visible order badges).
  final List<String> selectedMemberIds;

  /// Called when a member chip is tapped; the caller decides how the
  /// selection changes based on [mode].
  final ValueChanged<String> onMemberTap;

  /// Inline validation error, or `null` if the current selection is valid.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final entry in AssignmentMode.values)
              semantic(
                'chore_form.assignment.${entry.name}',
                child: ChoiceChip(
                  label: Text(_modeLabel(entry)),
                  selected: mode == entry,
                  onSelected: (_) => onModeChanged(entry),
                ),
              ),
          ],
        ),
        if (mode != AssignmentMode.anyone) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in members)
                semantic(
                  'chore_form.assignee.${member.id}',
                  child: FilterChip(
                    label: Text(_chipLabel(member)),
                    selected: selectedMemberIds.contains(member.id),
                    onSelected: (_) => onMemberTap(member.id),
                  ),
                ),
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

  String _chipLabel(Member member) {
    if (mode != AssignmentMode.rotation) {
      return member.name;
    }
    final order = selectedMemberIds.indexOf(member.id);
    return order == -1 ? member.name : '${order + 1}. ${member.name}';
  }

  String _modeLabel(AssignmentMode mode) {
    switch (mode) {
      case AssignmentMode.fixed:
        return 'Fixed';
      case AssignmentMode.rotation:
        return 'Rotation';
      case AssignmentMode.anyone:
        return 'Anyone';
    }
  }
}
