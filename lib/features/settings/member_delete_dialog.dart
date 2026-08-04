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
Future<bool> showMemberDeleteDialog(
  BuildContext context, {
  required String memberName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.memberDeleteDialogTitle(memberName)),
        content: Text(l10n.memberDeleteDialogBody(memberName)),
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
