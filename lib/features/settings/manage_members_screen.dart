/// The member management screen (spec
/// `docs/specs/members-management.md` §3): list, add, rename, and recolor
/// household members. No delete affordance in this version — see the
/// spec's §1 scope note (deletion needs a reassignment story for chores
/// referencing the member).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/features/settings/member_edit_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists every household member (creation-time order — see
/// `HouseholdRepository.watchMembers`), each tappable to rename/recolor,
/// plus a FAB to add a new one.
class ManageMembersScreen extends ConsumerWidget {
  /// Creates the manage-members screen.
  const ManageMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageMembersTitle)),
      body: membersAsync.when(
        data: (members) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];
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
        leading: MemberAvatar(member: member, radius: 16),
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
