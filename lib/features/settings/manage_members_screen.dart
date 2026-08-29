/// The member management screen (spec
/// `docs/specs/members-management.md` §3, extended by spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1/A2): list, add, rename,
/// recolor, and delete household members; an editable household-name row
/// at the top. Once linked (spec `docs/specs/sync-backend.md` §7.3), also
/// gains an 'Invite' row above the member list.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/household_rename_sheet.dart';
import 'package:chore_app/features/settings/invite_flow.dart';
import 'package:chore_app/features/settings/member_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists the household name (tappable to rename, spec A2), then every
/// household member (creation-time order — see
/// `HouseholdRepository.watchMembers`), each tappable to rename/recolor/
/// delete, plus a FAB to add a new one.
class ManageMembersScreen extends ConsumerWidget {
  /// Creates the manage-members screen.
  const ManageMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final membersAsync = ref.watch(membersProvider);
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageMembersTitle)),
      body: membersAsync.when(
        data: (members) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: members.length + 1 + (linked ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const _HouseholdNameRow();
            }
            final afterHeader = index - 1;
            if (linked && afterHeader == 0) {
              return const _InviteRow();
            }
            final member = members[linked ? afterHeader - 1 : afterHeader];
            return _MemberRow(
              member: member,
              onTap: () => showMemberEditSheet(context, member: member),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _ErrorState(onRetry: () => ref.invalidate(membersProvider)),
      ),
      floatingActionButton: semantic(
        'members.add',
        child: FloatingActionButton(
          onPressed: () => showMemberEditSheet(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

/// The editable household-name row (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A2), always shown first: tapping
/// it opens [showHouseholdRenameSheet]. Disabled (no `onTap`) while the
/// household name hasn't loaded yet -- `currentHouseholdProvider` awaits
/// `bootstrapProvider` first, so this is only ever momentary.
class _HouseholdNameRow extends ConsumerWidget {
  const _HouseholdNameRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final name = ref.watch(currentHouseholdProvider).valueOrNull?.name;
    return semantic(
      'members.household.rename',
      child: ListTile(
        leading: const Icon(Icons.home_outlined),
        title: Text(name ?? ''),
        subtitle: Text(l10n.manageMembersHouseholdSubtitle),
        trailing: const Icon(Icons.edit_outlined),
        onTap: name == null
            ? null
            : () => showHouseholdRenameSheet(context, currentName: name),
      ),
    );
  }
}

/// The 'Invite' row (spec `docs/specs/sync-backend.md` §7.3), shown only
/// once linked: runs [runInviteFlow] (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A3/B3 -- shared with the Account
/// section's equivalent row).
class _InviteRow extends ConsumerWidget {
  const _InviteRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.members.invite',
      child: ListTile(
        leading: const Icon(Icons.person_add_alt_outlined),
        title: Text(l10n.settingsMembersInviteEntry),
        onTap: () => _invite(context, ref),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final householdId = ref.read(settingsProvider).value?.syncHouseholdId;
    if (householdId == null) {
      return;
    }
    await runInviteFlow(context, ref, householdId);
  }
}

/// One member row: avatar + name, tappable to open the edit sheet.
///
/// Row semantic id is `members.row.<memberId>`, not `members.row.<name>` —
/// names aren't unique (duplicates are allowed by design, spec §3) — so
/// E2E flows select rows by their visible name text instead, matching the
/// manage-categories screen's convention.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return semantic(
      'members.row.${member.id}',
      child: ListTile(
        // 42px, the design canvas's members-row avatar (G-4).
        leading: MemberAvatar(member: member, radius: 21),
        title: Text(member.name),
        onTap: onTap,
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
          Text(l10n.manageMembersErrorMessage),
          const SizedBox(height: 8),
          semantic(
            'settings.members.error.retry',
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
