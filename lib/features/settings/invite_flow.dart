/// Shared create-invite handler for both entry points that offer inviting a
/// household member once linked (spec
/// `docs/feedback/2026-08-01-ux-audit.md` B3): the Members screen's
/// 'Invite' row (`manage_members_screen.dart`) and the Account section's
/// 'Invite a member' row (`account_section.dart`). Both call this, rather
/// than duplicating the create-invite-then-open-sheet dance.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/features/settings/invite_code_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the invite sheet for [householdId].
///
/// If the household already has an active code ([HouseholdGateway.activeInvite]
/// -- not revoked, not expired), the sheet re-shows THAT code with its expiry
/// and a "New code" button (persona review D5: every Invite tap used to
/// silently revoke the code already shared with someone). Only that button,
/// after its own confirm, revokes and replaces it -- via
/// [replaceInviteCode], the same revoke-then-create pair as before (spec A3:
/// one live code per household).
///
/// With no active code it creates one directly, as before. A failure at any
/// step shows a generic error snackbar instead and never opens the sheet.
Future<void> runInviteFlow(
  BuildContext context,
  WidgetRef ref,
  String householdId,
) async {
  try {
    final gateway = ref.read(householdGatewayProvider);
    final active = await gateway.activeInvite(householdId);
    if (active != null) {
      if (context.mounted) {
        await showInviteCodeSheet(
          context,
          code: active.code,
          expiresAt: active.expiresAt,
          onReplace: () => replaceInviteCode(ref, householdId),
        );
      }
      return;
    }
    final code = await replaceInviteCode(ref, householdId);
    if (context.mounted) {
      await showInviteCodeSheet(context, code: code);
    }
  } on Exception catch (e, s) {
    AppLog.error('ui.inviteFlow', e, s);
    if (context.mounted) {
      showAppSnackbar(
        context,
        message: AppLocalizations.of(context).settingsMembersInviteError,
      );
    }
  }
}

/// Revokes [householdId]'s active invites, then creates a fresh code and
/// returns it (spec A3: one live code per household -- creating a new one is
/// how you revoke the old one). Throws whatever the gateway throws.
Future<String> replaceInviteCode(WidgetRef ref, String householdId) async {
  final gateway = ref.read(householdGatewayProvider);
  await gateway.revokeActiveInvites(householdId);
  return gateway.createInvite(householdId);
}
