/// The welcome screen's "Join my family's household" subpage (spec
/// `docs/specs/onboarding-v2.md` §1), pushed from
/// `lib/features/onboarding/welcome_screen.dart`'s secondary card: inline
/// email + magic-link sign-in (reusing the Account section's gateway calls,
/// validation, and copy -- new compact widgets, not its widget), then --
/// once signed in -- a membership probe deciding between the P2d reconnect
/// offer and code entry -> claim/"I'm new here" (the join sheet's shared
/// chooser widgets, `lib/features/settings/join_flow_steps.dart`) -> a
/// no-archive/no-import `HouseholdJoinService.joinFresh` call.
///
/// Every step here watches provider state directly rather than caching a
/// step decided once in `initState` -- this is what makes "sign-in
/// completed but join not finished -> restores to the signed-in step"
/// (spec §1) work for free: re-opening this page (or resuming it after the
/// magic-link deep link returns and the Supabase session updates) simply
/// re-evaluates [currentAuthUserProvider] and [myMembershipProvider] on the
/// next build, with no separate "where was I" state to restore.
library;

import 'dart:async';

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/features/settings/account_validation.dart';
import 'package:chore_app/features/settings/join_flow_steps.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// The sub-steps reachable only once signed in and past the membership
/// probe (spec §1: claim/"I'm new here" -> download). `null` (the
/// `_subStep` field's initial/resting value) means "not there yet" -- the
/// build method then falls through to the reconnect-offer-or-code-entry
/// branch, computed straight from [myMembershipProvider].
enum _SubStep { chooser, newMemberName, working }

/// The welcome-join subpage.
class WelcomeJoinPage extends ConsumerStatefulWidget {
  /// Creates the welcome-join subpage.
  const WelcomeJoinPage({super.key});

  @override
  ConsumerState<WelcomeJoinPage> createState() => _WelcomeJoinPageState();
}

class _WelcomeJoinPageState extends ConsumerState<WelcomeJoinPage> {
  // Email sign-in step.
  final _emailController = TextEditingController();
  String? _sentToEmail;
  bool _sendingEmail = false;

  // Code entry / chooser / new-member-name / working steps.
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  _SubStep? _subStep;
  bool _busy = false;
  String? _inlineError;
  String _code = '';
  List<ClaimableMember> _claimableMembers = const [];
  JoinChoice? _choice;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onFieldChanged);
    _codeController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _emailController
      ..removeListener(_onFieldChanged)
      ..dispose();
    _codeController
      ..removeListener(_onFieldChanged)
      ..dispose();
    _nameController
      ..removeListener(_onFieldChanged)
      ..dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.welcomeJoinTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [_buildBody(context)],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Reactive, not a one-time initState decision (see the class doc
    // comment): re-evaluated on every build, which is exactly what lets a
    // returning deep link (or a re-opened page after a kill+relaunch with a
    // still-valid Supabase session) resume at the right step.
    final user = ref.watch(currentAuthUserProvider).valueOrNull;
    if (user == null) {
      return _buildEmailStep(context);
    }

    final subStep = _subStep;
    if (subStep != null) {
      switch (subStep) {
        case _SubStep.chooser:
          return JoinChooserStep(
            claimableMembers: _claimableMembers,
            onClaim: (member) => _runJoin(ClaimMemberChoice(member.memberId)),
            onNewMember: () =>
                setState(() => _subStep = _SubStep.newMemberName),
          );
        case _SubStep.newMemberName:
          return JoinNewMemberNameStep(
            controller: _nameController,
            onContinue: _confirmNewMember,
          );
        case _SubStep.working:
          return JoinWorkingStep(
            busy: _busy,
            inlineError: _inlineError,
            retrySemanticId: 'welcome.join.retry',
            onRetry: () {
              setState(() {
                _busy = true;
                _inlineError = null;
              });
              unawaited(_performJoin());
            },
          );
      }
    }

    // Spec §1/§7.6: probe BEFORE showing code entry -- mirrors
    // AccountSectionBody's identical "probe first, default to the other
    // branch until it resolves" pattern
    // (`lib/features/settings/account_section.dart`).
    final membership = ref.watch(myMembershipProvider).valueOrNull;
    if (membership != null) {
      return _buildReconnectOffer(context, membership);
    }
    return JoinCodeStep(
      controller: _codeController,
      busy: _busy,
      inlineError: _inlineError,
      onContinue: _submitCode,
    );
  }

  // -------------------------------------------------------------------
  // Email sign-in step.

  Widget _buildEmailStep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    final canSend = !_sendingEmail && isPlausibleEmail(email);
    final sentToEmail = _sentToEmail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.settingsAccountIntro),
        const SizedBox(height: 12),
        semantic(
          'welcome.join.email',
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
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: semantic(
            'welcome.join.send',
            child: FilledButton(
              onPressed: canSend ? () => _sendMagicLink(email) : null,
              child: Text(
                sentToEmail != null
                    ? l10n.settingsAccountSendAgain
                    : l10n.settingsAccountSendLink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _sendMagicLink(String email) async {
    setState(() => _sendingEmail = true);
    try {
      await ref.read(authGatewayProvider).sendMagicLink(email);
      if (mounted) {
        setState(() => _sentToEmail = email);
      }
    } on Exception {
      if (mounted) {
        showAppSnackbar(
          context,
          message: AppLocalizations.of(context).settingsAccountSendError,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingEmail = false);
      }
    }
  }

  // -------------------------------------------------------------------
  // Reconnect offer (spec §1/§7.6): tapping runs joinFresh directly with a
  // ReconnectChoice -- no code entry, no chooser, no archive/import (there
  // is nothing local to preserve on this path).

  Widget _buildReconnectOffer(BuildContext context, MyMembership membership) {
    final l10n = AppLocalizations.of(context);
    return DepthCard(
      margin: EdgeInsets.zero,
      child: semantic(
        'welcome.join.reconnect',
        child: ListTile(
          leading: const Icon(Icons.sync_outlined),
          title: Text(
            l10n.settingsAccountReconnectTitle(membership.householdName),
          ),
          subtitle: Text(l10n.welcomeJoinReconnectSubtitle),
          onTap: () => _runJoin(
            ReconnectChoice(
              householdId: membership.householdId,
              memberId: membership.memberId,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Code entry -> chooser -> new-member-name (shared widgets).

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final members = await ref
          .read(householdGatewayProvider)
          .listClaimableMembers(code);
      if (!mounted) {
        return;
      }
      setState(() {
        _code = code;
        _claimableMembers = members;
        _subStep = _SubStep.chooser;
        _busy = false;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _inlineError = joinCodeErrorMessage(
          AppLocalizations.of(context),
          error,
        );
      });
    }
  }

  void _confirmNewMember() {
    final name = _nameController.text.trim();
    // The uuid is minted HERE, once per confirmed choice -- see
    // NewMemberChoice.memberId's own doc comment (retry-idempotency).
    _runJoin(
      NewMemberChoice(
        memberId: const Uuid().v4(),
        name: name,
        color: autoJoinColor(_claimableMembers),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Join (no archive, no import -- HouseholdJoinService.joinFresh).

  void _runJoin(JoinChoice choice) {
    setState(() {
      _choice = choice;
      _subStep = _SubStep.working;
      _busy = true;
      _inlineError = null;
    });
    unawaited(_performJoin());
  }

  Future<void> _performJoin() async {
    final choice = _choice;
    if (choice == null) {
      throw StateError('No join choice selected.');
    }
    try {
      await ref
          .read(householdJoinServiceProvider)
          .joinFresh(
            choice: choice,
            // Reconnect (ReconnectChoice) carries no invite code at all --
            // see HouseholdJoinService.join's doc comment.
            code: choice is ReconnectChoice ? null : _code,
          );
      if (mounted) {
        // Pop back to the welcome screen's own base route: by now
        // householdGateProvider's stream has flipped (or is about to), so
        // that base route is already -- or is about to be -- the tab
        // shell rather than WelcomeScreen's cards. Popping THIS pushed
        // page is what reveals it; unlike WelcomeScreen's own inline
        // create form, this page sits on top of the Navigator stack, so
        // the reactive `MaterialApp.home` swap alone wouldn't surface
        // anything here without this pop.
        Navigator.of(context).pop();
      }
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _inlineError = AppLocalizations.of(context).joinHouseholdWorkingError;
      });
    }
  }
}
