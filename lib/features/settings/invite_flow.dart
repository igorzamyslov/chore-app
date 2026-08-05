/// Shared create-invite handler for both entry points that offer inviting a
/// household member once linked (spec
/// `docs/feedback/2026-08-01-ux-audit.md` B3): the Members screen's
/// 'Invite' row (`manage_members_screen.dart`) and the Account section's
/// 'Invite a member' row (`account_section.dart`). Both call this, rather
/// than duplicating the create-invite-then-open-sheet dance.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/features/settings/invite_code_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Revokes [householdId]'s previously active invites (spec A3: "one live
/// code per household" -- creating a new one is how you revoke the old
/// one), creates a fresh code, and opens [showInviteCodeSheet] with it. A
/// failure at either step (revoke or create) shows a generic error
/// snackbar instead and never opens the sheet.
Future<void> runInviteFlow(
  BuildContext context,
  WidgetRef ref,
  String householdId,
) async {
  try {
    final gateway = ref.read(householdGatewayProvider);
    await gateway.revokeActiveInvites(householdId);
    final code = await gateway.createInvite(householdId);
    if (context.mounted) {
      await showInviteCodeSheet(context, code: code);
    }
  } on Exception catch (_) {
    if (context.mounted) {
      showAppSnackbar(
        context,
        message: AppLocalizations.of(context).settingsMembersInviteError,
      );
    }
  }
}
