/// The settings screen's 'Account' section (spec
/// `docs/specs/sync-backend.md` §5): magic-link sign-in when signed out,
/// the account email + sign-out when signed in, and a static 'coming soon'
/// row when Supabase isn't configured ([NoopAuthGateway]).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/features/settings/account_validation.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Section header above the Account rows, matching every other Settings
/// section header's style (labelLarge, onSurfaceVariant, 24/8 padding, no
/// divider line), placed above the About section.
class AccountSectionHeader extends StatelessWidget {
  /// Creates the section header.
  const AccountSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        AppLocalizations.of(context).settingsAccountSectionTitle,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The Account section's body: a static disabled row when
/// [authGatewayProvider] resolves to [NoopAuthGateway] (Supabase not
/// configured), else the signed-in or signed-out state per
/// [currentAuthUserProvider].
class AccountSectionBody extends ConsumerWidget {
  /// Creates the section body.
  const AccountSectionBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authGatewayProvider) is NoopAuthGateway) {
      return const _ComingSoonTile();
    }
    final user = ref.watch(currentAuthUserProvider).valueOrNull;
    return user != null ? _SignedInTile(user: user) : const _SignedOutForm();
  }
}

/// The disabled placeholder row shown when Supabase isn't configured.
class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile();

  @override
  Widget build(BuildContext context) {
    return semantic(
      'settings.account.comingSoon',
      child: ListTile(
        enabled: false,
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(
          AppLocalizations.of(context).settingsAccountComingSoonTitle,
        ),
      ),
    );
  }
}

/// The signed-in row: account email, with a 'Sign out' action that opens a
/// confirmation dialog first.
class _SignedInTile extends ConsumerWidget {
  const _SignedInTile({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.account.signedIn',
      child: ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(user.email),
        trailing: semantic(
          'settings.account.signOut',
          child: TextButton(
            onPressed: () => _confirmAndSignOut(context, ref),
            child: Text(l10n.settingsAccountSignOut),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsAccountSignOutConfirmTitle),
          content: Text(l10n.settingsAccountSignOutConfirmBody),
          actions: [
            semantic(
              'settings.account.signOut.cancel',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.account.signOut.confirm',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.settingsAccountSignOutConfirmAction),
              ),
            ),
          ],
        );
      },
    );
    if ((confirmed ?? false) && context.mounted) {
      await _signOut(context, ref);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authGatewayProvider).signOut();
    } on Exception catch (_) {
      if (context.mounted) {
        showAppSnackbar(
          context,
          message: AppLocalizations.of(context).settingsAccountSignOutError,
        );
      }
    }
  }
}

/// The signed-out form: an intro line, an email field, and a submit button
/// that sends a magic-link email and switches into an inline confirmation
/// state.
class _SignedOutForm extends ConsumerStatefulWidget {
  const _SignedOutForm();

  @override
  ConsumerState<_SignedOutForm> createState() => _SignedOutFormState();
}

class _SignedOutFormState extends ConsumerState<_SignedOutForm> {
  final _emailController = TextEditingController();

  /// The address the last successful [AuthGateway.sendMagicLink] call was
  /// sent to, `null` before the first send. Non-null switches the section
  /// into its inline "check your email" confirmation state and relabels
  /// the submit button "Send again".
  String? _sentToEmail;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    _emailController
      ..removeListener(_onEmailChanged)
      ..dispose();
    super.dispose();
  }

  void _onEmailChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    final canSend = !_sending && isPlausibleEmail(email);
    final sentToEmail = _sentToEmail;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsAccountIntro),
          const SizedBox(height: 12),
          semantic(
            'settings.account.email',
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.settingsAccountEmailLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (sentToEmail != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.settingsAccountCheckEmail(sentToEmail),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: semantic(
              'settings.account.sendLink',
              child: FilledButton(
                onPressed: canSend ? () => _send(email) : null,
                child: Text(
                  sentToEmail != null
                      ? l10n.settingsAccountSendAgain
                      : l10n.settingsAccountSendLink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(String email) async {
    setState(() => _sending = true);
    try {
      await ref.read(authGatewayProvider).sendMagicLink(email);
      if (mounted) {
        setState(() => _sentToEmail = email);
      }
    } on Exception catch (_) {
      if (mounted) {
        showAppSnackbar(
          context,
          message: AppLocalizations.of(context).settingsAccountSendError,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}
