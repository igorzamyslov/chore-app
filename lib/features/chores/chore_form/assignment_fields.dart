/// The chore form's assignment-mode and assignee-picker controls.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/member_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The assignment mode segmented row plus its dependent assignee chips.
///
/// `fixed` shows a single-select chip row (exactly one member must be
/// picked); `rotation` shows a multi-select chip row where each selected
/// chip carries a visible order badge reflecting tap order (at least two
/// members must be picked); `anyone` shows no assignee chips. Every
/// assignee chip leads with the member's `MemberAvatar` (field feedback
/// F3, `docs/feedback/2026-08-01-field-feedback.md`). A trailing 'Add
/// member…' chip (spec `docs/feedback/2026-08-01-ux-audit.md` B2) closes
/// the assignee row, opening the new-member sheet inline so a missing
/// person can be added without abandoning the form -- the chip row
/// refreshes automatically once they're saved, since the caller
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
                  label: Text(_modeLabel(context, entry)),
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
                    // The selection checkmark would otherwise paint over
                    // the avatar (Flutter darkens+overlays it), hiding the
                    // exact thing this chip most needs to show once
                    // picked; the chip's own selected styling already
                    // conveys the state without it.
                    showCheckmark: false,
                    avatar: MemberAvatar(member: member, radius: 12),
                    label: Text(_chipLabel(context, member)),
                    selected: selectedMemberIds.contains(member.id),
                    onSelected: (_) => onMemberTap(member.id),
                  ),
                ),
              semantic(
                'chore_form.assignee.add',
                child: ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(AppLocalizations.of(context).choreFormAddMember),
                  onPressed: () => showMemberEditSheet(context),
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

  String _chipLabel(BuildContext context, Member member) {
    if (mode != AssignmentMode.rotation) {
      return member.name;
    }
    final order = selectedMemberIds.indexOf(member.id);
    if (order == -1) {
      return member.name;
    }
    return AppLocalizations.of(
      context,
    ).choreFormAssigneeOrderLabel(order + 1, member.name);
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
