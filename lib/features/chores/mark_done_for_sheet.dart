/// The member pickers opened from the chore action sheet: "Mark done for…"
/// (A-5, spec `docs/feedback/2026-08-07-field-feedback.md` B1) and
/// "Reassign this turn…" (persona review 2026-10-06 C2).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks which member to CREDIT for one occurrence, and resolves to that
/// member (or `null` if the sheet was dismissed).
///
/// [excludeMemberId] drops one row — the person holding the phone: this
/// action exists for "I finished something for ANOTHER person", and
/// completing something as yourself is the tile's one-tap path.
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
  return _showMemberPicker(
    context,
    idPrefix: 'chores.markDoneFor',
    title: (l10n) => l10n.choresMarkDoneForTitle,
    members: members,
    excludeMemberId: excludeMemberId,
  );
}

/// Asks who takes over one open turn (persona review 2026-10-06 C2), and
/// resolves to that member (or `null` if dismissed). Same layout as
/// [showMarkDoneForSheet]; [currentHolderId] — the member the turn is with
/// now — is left out, since handing it to them changes nothing.
Future<Member?> showReassignTurnSheet(
  BuildContext context, {
  required List<Member> members,
  required String? currentHolderId,
}) {
  return _showMemberPicker(
    context,
    idPrefix: 'chores.reassign',
    title: (l10n) => l10n.choresReassignTitle,
    members: members,
    excludeMemberId: currentHolderId,
  );
}

/// The shared picker: a titled sheet with one avatar row per member except
/// [excludeMemberId]. Ids: `<idPrefix>.sheet` and `<idPrefix>.row.<id>`.
Future<Member?> _showMemberPicker(
  BuildContext context, {
  required String idPrefix,
  required String Function(AppLocalizations l10n) title,
  required List<Member> members,
  required String? excludeMemberId,
}) {
  return showModalBottomSheet<Member>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return semantic(
        '$idPrefix.sheet',
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  title(l10n),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final member in members)
                if (member.id != excludeMemberId)
                  semantic(
                    '$idPrefix.row.${member.id}',
                    child: ListTile(
                      leading: MemberAvatar(member: member),
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
