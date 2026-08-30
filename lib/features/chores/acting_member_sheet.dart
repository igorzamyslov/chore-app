/// The chores app bar's acting-member avatar button and switcher sheet
/// (spec `docs/specs/members-management.md` §4).
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/manage_members_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chores app bar's leading slot, in the three
/// [MemberIdentityMode] states (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1):
///
/// - [MemberIdentityMode.switching] (local-only, or linked but signed out):
///   the acting-member switcher exactly as spec
///   `docs/specs/members-management.md` §4 has always described it — an
///   avatar button opening [showActingMemberSheet]. On a local-only
///   household standing in for others IS the model.
/// - [MemberIdentityMode.pinned] (linked AND signed in): a NON-interactive
///   avatar of the claimed member. There is no switcher and no sheet:
///   offering "become Anna" in the app bar of a synced household inverts
///   the common case, and `settings.actingMemberId` is device-scoped, so
///   acting on it makes multi-device data wrong. Crediting someone else
///   moves to the chore action sheet's "Mark done for…" row.
/// - [MemberIdentityMode.unknown] (either state still resolving): the plain
///   disabled icon, which is also what every state renders before
///   [actingMemberProvider] resolves.
///
/// The `chores.actingMember` semantic id is present in ALL THREE states, so
/// no existing selector (widget test or Maestro flow) ever loses its
/// target.
class ActingMemberButton extends ConsumerWidget {
  /// Creates the acting-member button.
  const ActingMemberButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(memberIdentityModeProvider);
    final member = ref.watch(actingMemberProvider);

    if (mode == MemberIdentityMode.pinned && member != null) {
      return semantic(
        'chores.actingMember',
        child: Tooltip(
          message: l10n.actingMemberSignedInAs(member.name),
          child: Center(child: MemberAvatar(member: member)),
        ),
      );
    }

    final canSwitch = mode == MemberIdentityMode.switching && member != null;
    return semantic(
      'chores.actingMember',
      child: IconButton(
        tooltip: l10n.actingMemberButtonTooltip,
        onPressed: canSwitch ? () => showActingMemberSheet(context) : null,
        icon: member == null || mode != MemberIdentityMode.switching
            ? const Icon(Icons.account_circle_outlined)
            : MemberAvatar(member: member),
      ),
    );
  }
}

/// Opens the acting-member switcher: one row per household member (avatar +
/// name + a check on the current one). Selecting a row persists it via
/// `SettingsRepository.setActingMember` and closes the sheet.
Future<void> showActingMemberSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _ActingMemberSheet(),
  );
}

class _ActingMemberSheet extends ConsumerWidget {
  const _ActingMemberSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final currentId = ref.watch(actingMemberProvider)?.id;

    return semantic(
      'actingMember.sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.actingMemberSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final member in members)
              semantic(
                'actingMember.sheet.row.${member.id}',
                child: ListTile(
                  leading: MemberAvatar(member: member),
                  title: Text(member.name),
                  trailing: member.id == currentId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () async {
                    await ref
                        .read(settingsRepositoryProvider)
                        .setActingMember(member.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            semantic(
              'acting.manage',
              child: ListTile(
                leading: const Icon(Icons.people_outline),
                title: Text(l10n.actingManageMembers),
                onTap: () {
                  // Close the sheet first, then push -- both calls resolve
                  // against the same underlying Navigator (a modal bottom
                  // sheet route lives on it, not a separate one), and this
                  // context stays valid across the pair since nothing
                  // `await`s in between (spec
                  // docs/feedback/2026-08-01-ux-audit.md B2's "Manage
                  // members" row).
                  Navigator.of(context).pop();
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const ManageMembersScreen(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
