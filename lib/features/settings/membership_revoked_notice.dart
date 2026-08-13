/// The membership-revoked notice (spec
/// `docs/specs/household-lifecycle.md` §3.5): what this device shows once
/// a pull discovers it was removed from its online household. Without it,
/// the device keeps displaying a complete, healthy-looking household that
/// silently stopped updating -- the §0.1 trap.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/features/settings/exit_confirm_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A banner shown while `settings.membershipRevoked` is set.
///
/// Renders nothing at all in the normal case, so it is safe to place
/// unconditionally in the Account section.
class MembershipRevokedNotice extends ConsumerWidget {
  /// Creates the notice.
  const MembershipRevokedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final revoked =
        ref.watch(settingsProvider).valueOrNull?.membershipRevoked ?? false;
    if (!revoked) {
      return const SizedBox.shrink();
    }

    return semantic(
      'membership.revoked.banner',
      child: Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.membershipRevokedTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.membershipRevokedBody,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: semantic(
                  'membership.revoked.acknowledge',
                  child: FilledButton(
                    onPressed: () => _acknowledge(context, ref, l10n),
                    child: Text(l10n.membershipRevokedAction),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acknowledge(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final result = await showExitConfirmSheet(
      context,
      title: l10n.membershipRevokedTitle,
      body: l10n.membershipRevokedBody,
      // Distinct from the banner's own button label: once the sheet is
      // open both are mounted, so sharing a label makes them ambiguous to
      // a widget test and to a screen reader.
      actionLabel: l10n.membershipRevokedConfirm,
      semanticPrefix: 'membership.revoked',
    );
    if (!result.confirmed) {
      return;
    }
    final database = ref.read(appDatabaseProvider);
    await ref.read(settingsRepositoryProvider).clearMembershipRevoked();
    if (result.alsoDeleteLocalData) {
      await resetAppData(database);
      ref.invalidate(settingsProvider);
    }
  }
}
