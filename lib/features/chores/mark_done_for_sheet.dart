/// The "Mark done for…" member picker (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks which member to CREDIT for one occurrence, and resolves to that
/// member (or `null` if the sheet was dismissed).
///
/// [excludeMemberId] drops one row — the claimed member, i.e. the person
/// holding the phone: this action exists for "I finished something for
/// ANOTHER person", and completing something as yourself is the tile's
/// one-tap path.
///
/// Riverpod-free by design, exactly like `chore_action_sheet.dart`: the
/// caller (`ChoresListScreen`) owns provider reads, so this file stays a
/// pure presentation widget. Picking a member does NOT write
/// `settings.actingMemberId` — crediting somebody is not becoming them.
Future<Member?> showMarkDoneForSheet(
  BuildContext context, {
  required List<Member> members,
  required String? excludeMemberId,
}) {
  return showModalBottomSheet<Member>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return semantic(
        'chores.markDoneFor.sheet',
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.choresMarkDoneForTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final member in members)
                if (member.id != excludeMemberId)
                  semantic(
                    'chores.markDoneFor.row.${member.id}',
                    child: ListTile(
                      leading: MemberAvatar(member: member, radius: 14),
                      title: Text(member.name),
                      onTap: () => Navigator.pop(sheetContext, member),
                    ),
                  ),
            ],
          ),
        ),
      );
    },
  );
}
