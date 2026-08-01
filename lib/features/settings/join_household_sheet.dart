/// The P2c "Join an existing household" sheet (spec
/// `docs/specs/sync-backend.md` §7.4, amended 2026-08-01), opened from the
/// Settings Account section's join row: a small stepper -- code entry,
/// "Are you Anna?"/"I'm new here" chooser, the in-flow import offer, then a
/// working/result state -- ending in `HouseholdJoinService.join`
/// (`lib/application/household_join_service.dart`).
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
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

enum _Step { code, chooser, newMemberName, importOffer, working }

class _JoinHouseholdSheet extends ConsumerStatefulWidget {
  const _JoinHouseholdSheet();

  @override
  ConsumerState<_JoinHouseholdSheet> createState() =>
      _JoinHouseholdSheetState();
}

class _JoinHouseholdSheetState extends ConsumerState<_JoinHouseholdSheet> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  _Step _step = _Step.code;
  bool _busy = false;
  String? _inlineError;

  String _code = '';
  List<ClaimableMember> _claimableMembers = const [];
  JoinChoice? _choice;

  @override
  void initState() {
    super.initState();
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canContinue = !_busy && _codeController.text.trim().isNotEmpty;
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
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.joinHouseholdCodeLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_inlineError != null) ...[
          const SizedBox(height: 12),
          Text(
            _inlineError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: semantic(
            'settings.account.join.continue',
            child: FilledButton(
              onPressed: canContinue ? _submitCode : null,
              child: _busy
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
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _inlineError = AppLocalizations.of(context).joinHouseholdCodeError;
      });
    }
  }

  // -------------------------------------------------------------------
  // Step 2: chooser ("Are you Anna?" + "I'm new here").

  Widget _buildChooserStep(BuildContext context) {
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
        for (final member in _claimableMembers)
          semantic(
            'settings.account.join.claim.${member.memberId}',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MemberAvatar(
                member: _memberForAvatar(member),
                radius: 16,
              ),
              title: Text(l10n.joinHouseholdChooserAreYou(member.name)),
              onTap: () => _chooseExistingMember(member),
            ),
          ),
        semantic(
          'settings.account.join.newMember',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person_add_outlined)),
            title: Text(l10n.joinHouseholdChooserNewMember),
            onTap: () => setState(() => _step = _Step.newMemberName),
          ),
        ),
      ],
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canContinue = _nameController.text.trim().isNotEmpty;
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
            controller: _nameController,
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
              onPressed: canContinue ? _confirmNewMember : null,
              child: Text(l10n.joinHouseholdContinue),
            ),
          ),
        ),
      ],
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
        color: _autoColor(),
      );
      _step = _Step.importOffer;
    });
  }

  /// The first of [CategoryRepository.seedColors] not already used by a
  /// claimable member -- the same "first free color" pattern
  /// `_MemberEditSheetState._firstFreeColor` uses, applied to the only
  /// roster this client can see before downloading the joined household
  /// (spec §7.4: "auto color").
  int _autoColor() {
    final usedColors = _claimableMembers.map((m) => m.color).toSet();
    const seedColors = CategoryRepository.seedColors;
    return seedColors.firstWhere(
      (color) => !usedColors.contains(color),
      orElse: () => seedColors[_claimableMembers.length % seedColors.length],
    );
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
            code: _code,
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_busy) {
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
          _inlineError ?? '',
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: semantic(
            'settings.account.join.retry',
            child: FilledButton(
              onPressed: () => _startJoin(importAccepted: _importAccepted),
              child: Text(l10n.commonRetry),
            ),
          ),
        ),
      ],
    );
  }
}

/// [MemberAvatar] takes a full [Member]; the chooser step only has a
/// [ClaimableMember] (id/name/color). [MemberAvatar] only ever reads
/// `name`/`color`, so this fills every other field with an inert
/// placeholder purely to satisfy [Member]'s constructor.
Member _memberForAvatar(ClaimableMember member) => Member(
  id: member.memberId,
  householdId: '',
  name: member.name,
  color: member.color,
  role: MemberRole.member,
  createdAt: '',
  updatedAt: '',
);
