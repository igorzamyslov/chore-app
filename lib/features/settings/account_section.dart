/// The settings screen's 'Account' section (spec
/// `docs/specs/sync-backend.md` §5, §7.3, §7.6): magic-link sign-in when
/// signed out; when signed in, the account email + sign-out, plus (while
/// unlinked) the P2d reconnect row (only when this account is already a
/// claimed member elsewhere), the P2b adopt row, and the P2c join row, or
/// (once linked) a subtitle naming the household; and a static 'coming
/// soon' row when Supabase isn't configured ([NoopAuthGateway]).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/features/settings/account_validation.dart';
import 'package:chore_app/features/settings/join_household_sheet.dart';
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
/// configured); the signed-out form or, when signed in, the signed-in tile
/// -- joined by the P2d reconnect row (spec §7.6, only when
/// `myMembershipProvider` finds a membership), the P2b adopt row (spec
/// §7.3), and the P2c join row while `settings.syncHouseholdId` is still
/// `null`.
class AccountSectionBody extends ConsumerWidget {
  /// Creates the section body.
  const AccountSectionBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authGatewayProvider) is NoopAuthGateway) {
      return const _ComingSoonTile();
    }
    final user = ref.watch(currentAuthUserProvider).valueOrNull;
    if (user == null) {
      return const _SignedOutForm();
    }
    final householdId = ref
        .watch(settingsProvider)
        .valueOrNull
        ?.syncHouseholdId;
    if (householdId == null) {
      // Spec §7.6 (P2d reconnect): probe BEFORE showing adopt/join -- when
      // the signed-in account already has a membership elsewhere, the
      // reconnect row goes FIRST, above both.
      final membership = ref.watch(myMembershipProvider).valueOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SignedInTile(user: user),
          if (membership != null) _ReconnectRow(membership: membership),
          const _AdoptRow(),
          const _JoinRow(),
        ],
      );
    }
    final householdName = ref.watch(currentHouseholdProvider).valueOrNull?.name;
    return _SignedInTile(user: user, householdName: householdName);
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

/// The signed-in row: account email (plus, once linked, a subtitle naming
/// the household -- spec §7.3 last paragraph), with a 'Sign out' action
/// that opens a confirmation dialog first.
class _SignedInTile extends ConsumerWidget {
  const _SignedInTile({required this.user, this.householdName});

  final AuthUser user;

  /// The linked household's name, or `null` while unlinked (or while it
  /// hasn't loaded yet).
  final String? householdName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final householdName = this.householdName;
    return semantic(
      'settings.account.signedIn',
      child: ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(user.email),
        subtitle: householdName == null
            ? null
            : Text(l10n.settingsAccountLinkedSubtitle(householdName)),
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

/// The P2d reconnect row (spec §7.6), shown ABOVE [_AdoptRow]/[_JoinRow]
/// whenever this device is signed in, unlinked, AND
/// `myMembershipProvider` resolves to a non-null `MyMembership` -- the
/// signed-in account is already a claimed member of a household this
/// DEVICE isn't currently linked to (a returning device: phone reset, new
/// phone). Tapping it opens the join sheet
/// (`lib/features/settings/join_household_sheet.dart`'s
/// `showReconnectHouseholdSheet`) pre-loaded with a `ReconnectChoice` --
/// skipping code entry and the claim/new-member chooser entirely, straight
/// to the same in-flow import offer [_JoinRow] uses. Success mirrors
/// [_JoinRow] exactly: `bootstrapProvider` invalidation (the household id
/// changed) + the archive-naming snackbar.
class _ReconnectRow extends ConsumerWidget {
  const _ReconnectRow({required this.membership});

  /// The already-claimed membership `myMembershipProvider` resolved to.
  final MyMembership membership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.account.reconnect',
      child: ListTile(
        leading: const Icon(Icons.sync_outlined),
        title: Text(
          l10n.settingsAccountReconnectTitle(membership.householdName),
        ),
        subtitle: Text(l10n.settingsAccountReconnectIntro),
        onTap: () => _reconnect(context, ref),
      ),
    );
  }

  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    final archiveFileName = await showReconnectHouseholdSheet(
      context,
      choice: ReconnectChoice(
        householdId: membership.householdId,
        memberId: membership.memberId,
      ),
    );
    if (archiveFileName == null) {
      return;
    }
    ref.invalidate(bootstrapProvider);
    if (context.mounted) {
      showAppSnackbar(
        context,
        message: AppLocalizations.of(
          context,
        ).settingsAccountJoinSuccessSnackbar(archiveFileName),
      );
    }
  }
}

/// The P2b adopt row (spec §7.3), shown below [_SignedInTile] (and,
/// while a reconnect option exists, below [_ReconnectRow]) whenever this
/// device is signed in but unlinked: one line of explanatory copy, a
/// progress state while `HouseholdLinkService.adopt`
/// (`lib/application/household_link_service.dart`) runs, and an inline
/// error + 'Try again' state on failure -- rerunning is always safe (the
/// service tolerates a half-succeeded previous attempt).
///
/// [_JoinRow] (spec §7.4's P2c slice) is the sibling choice row, shown
/// right below this one.
class _AdoptRow extends ConsumerStatefulWidget {
  const _AdoptRow();

  @override
  ConsumerState<_AdoptRow> createState() => _AdoptRowState();
}

class _AdoptRowState extends ConsumerState<_AdoptRow> {
  bool _running = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.account.adopt',
      child: ListTile(
        leading: _running
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload_outlined),
        title: Text(
          _failed
              ? l10n.settingsAccountAdoptRetry
              : l10n.settingsAccountAdoptTitle,
        ),
        subtitle: Text(
          _failed
              ? l10n.settingsAccountAdoptError
              : l10n.settingsAccountAdoptIntro,
          style: _failed
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
        enabled: !_running,
        onTap: _running ? null : _adopt,
      ),
    );
  }

  Future<void> _adopt() async {
    // Unreachable in practice: by the time the Account section can show
    // this row, the household is already bootstrapped and has an acting
    // member (spec `docs/specs/members-management.md`) -- a `null` here
    // would be a programming bug, not an expected runtime failure, so it's
    // left to crash rather than folded into the inline error state below.
    final actingMemberId = ref.read(actingMemberProvider)?.id;
    if (actingMemberId == null) {
      throw StateError('No acting member to adopt with.');
    }
    setState(() {
      _running = true;
      _failed = false;
    });
    try {
      final householdId = await ref.read(bootstrapProvider.future);
      await ref
          .read(householdLinkServiceProvider)
          .adopt(householdId: householdId, actingMemberId: actingMemberId);
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }
}

/// The P2c join row (spec §7.4), shown below [_AdoptRow] whenever this
/// device is signed in but unlinked: one line of explanatory copy; tapping
/// it opens [showJoinHouseholdSheet]'s stepper. On a successful join, the
/// household id `bootstrapProvider` resolves to has changed, so this
/// invalidates it (spec §7.4 step 3's last sentence: "the post-replace UI
/// must re-resolve the bootstrap household") and shows a snackbar naming
/// the archive file the old data was saved to -- both done here, in the UI
/// layer, rather than inside `HouseholdJoinService.join` itself, which has
/// no `BuildContext`/`Ref` of its own to invalidate providers or show a
/// snackbar with.
class _JoinRow extends ConsumerWidget {
  const _JoinRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return semantic(
      'settings.account.join',
      child: ListTile(
        leading: const Icon(Icons.group_add_outlined),
        title: Text(l10n.settingsAccountJoinTitle),
        subtitle: Text(l10n.settingsAccountJoinIntro),
        onTap: () => _join(context, ref),
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final archiveFileName = await showJoinHouseholdSheet(context);
    if (archiveFileName == null) {
      return;
    }
    ref.invalidate(bootstrapProvider);
    if (context.mounted) {
      showAppSnackbar(
        context,
        message: AppLocalizations.of(
          context,
        ).settingsAccountJoinSuccessSnackbar(archiveFileName),
      );
    }
  }
}
