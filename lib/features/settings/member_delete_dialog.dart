/// The delete-confirmation dialog for a household member (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog for deleting the member named [memberName],
/// resolving to whether the user confirmed (defaults to `false` if
/// dismissed).
///
/// States the referential consequences plainly, per spec: rotation chores
/// drop them from the turn order (converting to a fixed assignee, or
/// 'anyone', if too few people are left), fixed chores assigned to them
/// open up to anyone, and anything currently assigned to them becomes
/// unassigned -- history (`completedBy`, closed occurrences) is untouched.
///
/// [claimed] picks the body. An unclaimed profile gets that original
/// referential-consequences copy; a CLAIMED profile gets the variant which
/// also states what happens on that person's own phone (spec
/// `docs/specs/household-lifecycle.md` §3.2) -- the one consequence the
/// person tapping Delete cannot see from here. The title is deliberately
/// shared: "Delete {memberName}?" is right either way.
///
/// Stays a ONE-step confirm, and so does Leave -- spec
/// `docs/specs/household-lifecycle.md` §3.3 gives every exit one confirm
/// shape, and only delete-account adds a second gate after it (D-L6). (An
/// earlier version of this comment said Leave uses the two-step
/// `confirmTwoStepDestructiveAction` chain in `destructive_confirm.dart`;
/// it does not, and 'Reset app data' remains that builder's only caller.)
/// Removal is recoverable either way -- the person can be re-invited, and
/// their profile and history stay in the household -- and the existing
/// `members.edit.delete.cancel`/`.confirm` semantic ids stay load-bearing.
///
/// This dialog is deliberately NOT the shared §3.3 exit SHEET either: that
/// sheet's D-L3 checkbox asks what happens to THIS device, which is the
/// wrong question for an action taken on somebody else's profile.
Future<bool> showMemberDeleteDialog(
  BuildContext context, {
  required String memberName,
  required bool claimed,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        // AlertDialog only puts its content in a scroll view when asked;
        // otherwise a long body in a `Flexible` overflows at a large text
        // scale on a small surface -- the same class of bug Task 12 fixed in
        // `exit_confirm_sheet.dart`. Both bodies here are long paragraphs,
        // and the claimed one is the longest copy in this dialog, so the
        // scroll view is not optional.
        scrollable: true,
        title: Text(l10n.memberDeleteDialogTitle(memberName)),
        content: Text(
          claimed
              ? l10n.memberRemoveDialogBodyClaimed(memberName)
              : l10n.memberDeleteDialogBody(memberName),
        ),
        actions: [
          semantic(
            'members.edit.delete.cancel',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
          ),
          semantic(
            'members.edit.delete.confirm',
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.commonDelete),
            ),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
