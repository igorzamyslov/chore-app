/// The P2c "Join an existing household" sheet (spec
/// `docs/specs/sync-backend.md` §7.4, amended 2026-08-01), opened from the
/// Settings Account section's join row: a small stepper -- code entry,
/// "Are you Anna?"/"I'm new here" chooser, the in-flow import offer, then a
/// working/result state -- ending in `HouseholdJoinService.join`
/// (`lib/application/household_join_service.dart`).
///
/// [showReconnectHouseholdSheet] reuses this exact same sheet for the P2d
/// reconnect flow (spec §7.6): the Account section's reconnect row already
/// knows which household/member it's reconnecting to (from the
/// `findMyMembership` probe), so it opens the sheet pre-loaded with a
/// [ReconnectChoice], starting directly at the import-offer step -- code
/// entry and the claim/new-member chooser never apply to reconnect and are
/// skipped entirely.
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/features/settings/join_flow_steps.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Opens the join sheet. Resolves to the archive file's name on a
/// successful join (for the caller's post-join snackbar), or `null` if the
/// sheet was dismissed without completing.
Future<String?> showJoinHouseholdSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => semantic(
      'settings.account.join.sheet',
      child: const _JoinHouseholdSheet(),
    ),
  );
}

/// Opens the join sheet pre-loaded with [choice] (a [ReconnectChoice], per
/// this library's doc comment), starting directly at the import-offer step.
/// Resolves the same way [showJoinHouseholdSheet] does.
Future<String?> showReconnectHouseholdSheet(
  BuildContext context, {
  required JoinChoice choice,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => semantic(
      'settings.account.reconnect.sheet',
      child: _JoinHouseholdSheet(initialChoice: choice),
    ),
  );
}

enum _Step { code, chooser, newMemberName, importOffer, working }

class _JoinHouseholdSheet extends ConsumerStatefulWidget {
  const _JoinHouseholdSheet({this.initialChoice});

  /// When set (the P2d reconnect flow, via [showReconnectHouseholdSheet]),
  /// the sheet starts directly at [_Step.importOffer] with this choice
  /// already made, skipping code entry and the claim/new-member chooser.
  final JoinChoice? initialChoice;

  @override
  ConsumerState<_JoinHouseholdSheet> createState() =>
      _JoinHouseholdSheetState();
}

class _JoinHouseholdSheetState extends ConsumerState<_JoinHouseholdSheet> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  late _Step _step;
  bool _busy = false;
  String? _inlineError;

  String _code = '';
  List<ClaimableMember> _claimableMembers = const [];
  JoinChoice? _choice;

  @override
  void initState() {
    super.initState();
    final initialChoice = widget.initialChoice;
    _choice = initialChoice;
    _step = initialChoice == null ? _Step.code : _Step.importOffer;
    _codeController.addListener(_onFieldChanged);
    _nameController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
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
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_buildStep(context)],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case _Step.code:
        return _buildCodeStep(context);
      case _Step.chooser:
        return _buildChooserStep(context);
      case _Step.newMemberName:
        return _buildNewMemberNameStep(context);
      case _Step.importOffer:
        return _buildImportOfferStep(context);
      case _Step.working:
        return _buildWorkingStep(context);
    }
  }

  // -------------------------------------------------------------------
  // Step 1: code entry.

  Widget _buildCodeStep(BuildContext context) {
    return JoinCodeStep(
      controller: _codeController,
      busy: _busy,
      inlineError: _inlineError,
      onContinue: _submitCode,
    );
  }

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
        _step = _Step.chooser;
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

  // -------------------------------------------------------------------
  // Step 2: chooser ("Are you Anna?" + "I'm new here").

  Widget _buildChooserStep(BuildContext context) {
    return JoinChooserStep(
      claimableMembers: _claimableMembers,
      onClaim: _chooseExistingMember,
      onNewMember: () => setState(() => _step = _Step.newMemberName),
    );
  }

  void _chooseExistingMember(ClaimableMember member) {
    setState(() {
      _choice = ClaimMemberChoice(member.memberId);
      _step = _Step.importOffer;
    });
  }

  // -------------------------------------------------------------------
  // Step 2b: "I'm new here" name prompt.

  Widget _buildNewMemberNameStep(BuildContext context) {
    return JoinNewMemberNameStep(
      controller: _nameController,
      onContinue: _confirmNewMember,
    );
  }

  void _confirmNewMember() {
    final name = _nameController.text.trim();
    setState(() {
      // The uuid is minted HERE, once per confirmed choice -- not inside
      // the join service -- so a retry after an interrupted join re-sends
      // the same id and the server's idempotent join_as_new_member
      // (migration 20260801130000) recognizes it. See
      // NewMemberChoice.memberId.
      _choice = NewMemberChoice(
        memberId: const Uuid().v4(),
        name: name,
        color: autoJoinColor(_claimableMembers),
      );
      _step = _Step.importOffer;
    });
  }

  // -------------------------------------------------------------------
  // Step 3: the in-flow import offer (spec §7.4 step 2).

  Widget _buildImportOfferStep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.joinHouseholdImportTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.joinHouseholdImportBody),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            semantic(
              'settings.account.join.import.decline',
              child: TextButton(
                onPressed: () => _startJoin(importAccepted: false),
                child: Text(l10n.joinHouseholdImportDecline),
              ),
            ),
            const SizedBox(width: 8),
            semantic(
              'settings.account.join.import.accept',
              child: FilledButton(
                onPressed: () => _startJoin(importAccepted: true),
                child: Text(l10n.joinHouseholdImportAccept),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Step 4: working / result.

  bool _importAccepted = false;

  void _startJoin({required bool importAccepted}) {
    _importAccepted = importAccepted;
    setState(() {
      _step = _Step.working;
      _inlineError = null;
      _busy = true;
    });
    unawaited(_runJoin());
  }

  Future<void> _runJoin() async {
    final choice = _choice;
    if (choice == null) {
      throw StateError('No join choice selected.');
    }
    try {
      final oldHouseholdId = await ref.read(bootstrapProvider.future);
      final result = await ref
          .read(householdJoinServiceProvider)
          .join(
            oldHouseholdId: oldHouseholdId,
            // Reconnect (ReconnectChoice) carries no invite code at all --
            // see HouseholdJoinService.join's doc comment.
            code: choice is ReconnectChoice ? null : _code,
            choice: choice,
            importAccepted: _importAccepted,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result.archiveFileName);
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

  Widget _buildWorkingStep(BuildContext context) {
    return JoinWorkingStep(
      busy: _busy,
      inlineError: _inlineError,
      retrySemanticId: 'settings.account.join.retry',
      onRetry: () => _startJoin(importAccepted: _importAccepted),
    );
  }
}
