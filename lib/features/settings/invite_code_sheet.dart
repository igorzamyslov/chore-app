/// The invite-code bottom sheet (spec `docs/specs/sync-backend.md` §7.3),
/// opened from the Members screen's 'Invite' row once a code has been
/// created: shows the 8-char code in large type, plus a share button.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the modal bottom sheet showing [code].
Future<void> showInviteCodeSheet(BuildContext context, {required String code}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => semantic(
      'settings.members.invite.sheet',
      child: _InviteCodeSheet(code: code),
    ),
  );
}

class _InviteCodeSheet extends StatelessWidget {
  const _InviteCodeSheet({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsMembersInviteSheetTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.settingsMembersInviteSheetBody),
          const SizedBox(height: 24),
          Center(
            child: semantic(
              'settings.members.invite.code',
              child: Text(
                code,
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: semantic(
              'settings.members.invite.share',
              child: FilledButton.icon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(l10n.settingsMembersInviteShare),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final text = AppLocalizations.of(
      context,
    ).settingsMembersInviteShareText(code);
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
