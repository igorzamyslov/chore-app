/// The invite-code bottom sheet (spec `docs/specs/sync-backend.md` §7.3),
/// opened from either the Members screen's 'Invite' row or the Account
/// section's 'Invite a member' row (spec
/// `docs/feedback/2026-08-01-ux-audit.md` B3) once a code has been created
/// via `runInviteFlow` (`lib/features/settings/invite_flow.dart`): shows
/// the 8-char code in large type, plus a share button -- and, when
/// re-showing the household's still-active code, its expiry and a confirmed
/// "New code" button (persona review D5).
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the modal bottom sheet showing [code].
///
/// [expiresAt] set means [code] is the household's ALREADY ACTIVE code being
/// re-shown (persona review D5): the sheet then states its expiry instead of
/// the "replaces any earlier code" line, and offers a "New code" button that
/// confirms first and then calls [onReplace] for the replacement code.
Future<void> showInviteCodeSheet(
  BuildContext context, {
  required String code,
  DateTime? expiresAt,
  Future<String> Function()? onReplace,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => semantic(
      'settings.members.invite.sheet',
      child: _InviteCodeSheet(
        code: code,
        expiresAt: expiresAt,
        onReplace: onReplace,
      ),
    ),
  );
}

class _InviteCodeSheet extends StatefulWidget {
  const _InviteCodeSheet({
    required this.code,
    required this.expiresAt,
    required this.onReplace,
  });

  final String code;
  final DateTime? expiresAt;
  final Future<String> Function()? onReplace;

  @override
  State<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends State<_InviteCodeSheet> {
  late String _code = widget.code;

  /// Non-null while showing a re-used active code; cleared once replaced (a
  /// fresh code gets the plain "expires in 7 days" body instead).
  late DateTime? _expiresAt = widget.expiresAt;
  bool _replacing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final expiresAt = _expiresAt;
    final canReplace = expiresAt != null && widget.onReplace != null;
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
          if (expiresAt == null)
            Text(l10n.settingsMembersInviteSheetBody)
          else
            semantic(
              'settings.members.invite.validUntil',
              child: Text(
                l10n.settingsMembersInviteValidUntil(
                  DateFormat.yMMMd(
                    Localizations.localeOf(context).toString(),
                  ).format(expiresAt.toLocal()),
                ),
              ),
            ),
          const SizedBox(height: 8),
          semantic(
            'settings.members.invite.hint',
            child: Text(
              l10n.settingsMembersInviteHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: semantic(
              'settings.members.invite.code',
              child: Text(
                _code,
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
                onPressed: _replacing ? null : () => _share(context),
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(l10n.settingsMembersInviteShare),
              ),
            ),
          ),
          if (canReplace) ...[
            const SizedBox(height: 8),
            Center(
              child: semantic(
                'settings.members.invite.newCode',
                child: TextButton(
                  onPressed: _replacing ? null : _confirmReplace,
                  child: Text(l10n.settingsMembersInviteNewCode),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmReplace() async {
    final onReplace = widget.onReplace;
    if (onReplace == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsMembersInviteReplaceTitle),
          content: Text(l10n.settingsMembersInviteReplaceBody),
          actions: [
            semantic(
              'settings.members.invite.replace.cancel',
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.members.invite.replace.confirm',
              child: FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.settingsMembersInviteReplaceConfirm),
              ),
            ),
          ],
        );
      },
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }
    setState(() => _replacing = true);
    try {
      final code = await onReplace();
      if (!mounted) {
        return;
      }
      setState(() {
        _code = code;
        _expiresAt = null;
        _replacing = false;
      });
    } on Exception catch (e, s) {
      AppLog.error('ui.inviteReplace', e, s);
      if (!mounted) {
        return;
      }
      setState(() => _replacing = false);
      showAppErrorSnackbar(
        context,
        message: AppLocalizations.of(context).settingsMembersInviteError,
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    final text = AppLocalizations.of(
      context,
    ).settingsMembersInviteShareText(_code);
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
