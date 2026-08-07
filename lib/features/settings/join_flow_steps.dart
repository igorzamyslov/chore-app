/// Shared step widgets for the P2c join flow's code-entry, claim/"I'm new
/// here" chooser, and new-member-name steps -- used by BOTH the Settings
/// Account section's join sheet (`lib/features/settings/join_household_sheet.dart`)
/// and the welcome screen's join subpage
/// (`lib/features/onboarding/welcome_join_page.dart`, spec
/// `docs/specs/onboarding-v2.md` §1). Extracted here (rather than
/// duplicated) so both surfaces render the exact same widgets, semantic
/// ids, and copy for the part of the flow they share; only what surrounds
/// them (a modal bottom sheet vs a full welcome subpage, archive/import
/// steps that only apply once local data exists) differs by caller.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// The first of [CategoryRepository.seedColors] not already used by a
/// claimable member -- the "first free color" pattern
/// `_MemberEditSheetState._firstFreeColor` uses, applied to the only
/// roster a joining client can see before downloading the joined
/// household (spec `docs/specs/sync-backend.md` §7.4: "auto color").
int autoJoinColor(List<ClaimableMember> claimableMembers) {
  final usedColors = claimableMembers.map((m) => m.color).toSet();
  const seedColors = CategoryRepository.seedColors;
  return seedColors.firstWhere(
    (color) => !usedColors.contains(color),
    orElse: () => seedColors[claimableMembers.length % seedColors.length],
  );
}

/// Maps a `listClaimableMembers` failure to the right code-entry inline
/// error (T1.6 -- `docs/research/persona-ben.md` finding 9,
/// `docs/research/triage.md` T1.6).
///
/// Read from source (`supabase/migrations/20260731120000_initial_schema.sql`
/// `_valid_invite`): a mistyped code, an expired code, and a revoked code
/// all fail the SAME single query (`code = p_code and revoked_at is null
/// and expires_at > now()`) and raise the SAME plain exception with no
/// distinguishing detail -- so those three are genuinely NOT distinguishable
/// from here, and this deliberately does not pretend otherwise. What IS
/// real and worth separating: whether the server ever got to evaluate the
/// code at all. A [PostgrestException] means it did (and rejected it) --
/// every other exception (no connectivity, a timeout, ...) means it didn't,
/// so blaming the code itself would be misleading.
String joinCodeErrorMessage(AppLocalizations l10n, Object error) {
  return error is PostgrestException
      ? l10n.joinHouseholdCodeError
      : l10n.joinHouseholdCodeUnknownError;
}

/// [MemberAvatar] takes a full [Member]; the chooser step only has a
/// [ClaimableMember] (id/name/color). [MemberAvatar] only ever reads
/// `name`/`color`, so this fills every other field with an inert
/// placeholder purely to satisfy [Member]'s constructor.
Member memberForAvatar(ClaimableMember member) => Member(
  id: member.memberId,
  householdId: '',
  name: member.name,
  color: member.color,
  role: MemberRole.member,
  createdAt: '',
  updatedAt: '',
  syncDirty: false,
);

/// The invite-code entry step (ids `settings.account.join.code`/
/// `settings.account.join.continue`).
class JoinCodeStep extends StatelessWidget {
  /// Creates the code-entry step.
  const JoinCodeStep({
    required this.controller,
    required this.busy,
    required this.inlineError,
    required this.onContinue,
    super.key,
  });

  /// The invite-code text field's controller.
  final TextEditingController controller;

  /// Whether `listClaimableMembers` is in flight -- disables the continue
  /// button and shows a spinner in its place.
  final bool busy;

  /// An error message to show below the field (e.g. an invalid/expired
  /// code), or `null` for none.
  final String? inlineError;

  /// Called when the continue button is tapped with a non-empty code.
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canContinue = !busy && controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.joinHouseholdCodeTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.joinHouseholdCodeBody),
        const SizedBox(height: 16),
        semantic(
          'settings.account.join.code',
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.joinHouseholdCodeLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (inlineError != null) ...[
          const SizedBox(height: 12),
          Text(inlineError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: semantic(
            'settings.account.join.continue',
            child: FilledButton(
              onPressed: canContinue ? onContinue : null,
              child: busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.joinHouseholdContinue),
            ),
          ),
        ),
      ],
    );
  }
}

/// The claim/"I'm new here" chooser step (ids
/// `settings.account.join.claim.<memberId>`/`settings.account.join.newMember`).
class JoinChooserStep extends StatelessWidget {
  /// Creates the chooser step.
  const JoinChooserStep({
    required this.claimableMembers,
    required this.onClaim,
    required this.onNewMember,
    super.key,
  });

  /// The unclaimed member profiles `listClaimableMembers` returned.
  final List<ClaimableMember> claimableMembers;

  /// Called with the tapped member when the caller claims an existing
  /// profile.
  final ValueChanged<ClaimableMember> onClaim;

  /// Called when the caller picks "I'm new here" instead.
  final VoidCallback onNewMember;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.joinHouseholdChooserTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final member in claimableMembers)
          semantic(
            'settings.account.join.claim.${member.memberId}',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MemberAvatar(
                member: memberForAvatar(member),
                radius: 16,
              ),
              title: Text(l10n.joinHouseholdChooserAreYou(member.name)),
              onTap: () => onClaim(member),
            ),
          ),
        semantic(
          'settings.account.join.newMember',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_add_outlined)),
            title: Text(l10n.joinHouseholdChooserNewMember),
            onTap: onNewMember,
          ),
        ),
      ],
    );
  }
}

/// The "I'm new here" name prompt step (ids
/// `settings.account.join.newMember.name`/
/// `settings.account.join.newMember.continue`).
class JoinNewMemberNameStep extends StatelessWidget {
  /// Creates the new-member name step.
  const JoinNewMemberNameStep({
    required this.controller,
    required this.onContinue,
    super.key,
  });

  /// The new member's name field controller.
  final TextEditingController controller;

  /// Called when the continue button is tapped with a non-empty name.
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canContinue = controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.joinHouseholdNewMemberTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        semantic(
          'settings.account.join.newMember.name',
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.joinHouseholdNewMemberNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: semantic(
            'settings.account.join.newMember.continue',
            child: FilledButton(
              onPressed: canContinue ? onContinue : null,
              child: Text(l10n.joinHouseholdContinue),
            ),
          ),
        ),
      ],
    );
  }
}

/// The working/result step: a centered spinner while [busy], else
/// [inlineError] with a retry button (id [retrySemanticId]).
class JoinWorkingStep extends StatelessWidget {
  /// Creates the working step.
  const JoinWorkingStep({
    required this.busy,
    required this.inlineError,
    required this.retrySemanticId,
    required this.onRetry,
    super.key,
  });

  /// Whether the join/reconnect call is still in flight.
  final bool busy;

  /// The error message to show once [busy] is false, or `null` (unused --
  /// this step is only ever shown after a failure once not busy).
  final String? inlineError;

  /// The semantic id for the retry button -- callers use distinct ids
  /// (`settings.account.join.retry` vs `welcome.join.retry`) since the two
  /// surfaces are otherwise-identical but separately selectable in tests.
  final String retrySemanticId;

  /// Called when the retry button is tapped.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            height: 32,
            width: 32,
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          inlineError ?? '',
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: semantic(
            retrySemanticId,
            child: FilledButton(
              onPressed: onRetry,
              child: Text(l10n.commonRetry),
            ),
          ),
        ),
      ],
    );
  }
}
