/// The member add/edit bottom sheet: rename, recolor, save, delete (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1). Delete is visible only when
/// the member is deletable: unclaimed (no `userId`) AND not the
/// household's last active member.
library;

import 'package:chore_app/app/color_swatch_picker.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/features/settings/member_delete_dialog.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the modal bottom sheet for adding a new member (when [member] is
/// omitted) or editing an existing [member] (rename/recolor).
///
/// A new member defaults to the first of
/// [CategoryRepository.seedColors] — the same fixed palette the category
/// edit sheet uses — not already used by another current member (wrapping
/// back to the first color if every seed color is taken).
Future<void> showMemberEditSheet(BuildContext context, {Member? member}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _MemberEditSheet(member: member),
  );
}

class _MemberEditSheet extends ConsumerStatefulWidget {
  const _MemberEditSheet({this.member});

  final Member? member;

  @override
  ConsumerState<_MemberEditSheet> createState() => _MemberEditSheetState();
}

class _MemberEditSheetState extends ConsumerState<_MemberEditSheet> {
  late final TextEditingController _nameController;
  late int _color;

  bool get _isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _nameController = TextEditingController(text: member?.name ?? '')
      ..addListener(_onNameChanged);
    _color = member?.color ?? _firstFreeColor();
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  List<Member> get _currentMembers =>
      ref.read(membersProvider).value ?? const <Member>[];

  /// Whether the delete action should be shown at all (spec: HIDDEN, not
  /// disabled, for a claimed or last-remaining member).
  ///
  /// [membersProvider] is already the roster query (soft-deleted members
  /// excluded, `HouseholdRepository.watchMembers`), so its current length
  /// already reflects "active members" -- if the member being edited is
  /// one of only one, deleting it would leave zero.
  bool get _canDelete {
    final member = widget.member;
    if (member == null || member.userId != null) {
      return false;
    }
    final activeMembers = ref.watch(membersProvider).value ?? const <Member>[];
    return activeMembers.length > 1;
  }

  /// The reason [canDelete] (the current build's [_canDelete] value, passed
  /// in rather than re-read to avoid a second [membersProvider] watch) is
  /// `false`, for the explanation that replaces the vanished Delete button
  /// (T1.7 -- `docs/research/persona-anna.md` finding 6,
  /// `docs/research/triage.md` T1.7): `null` while adding a new member (no
  /// delete affordance applies at all, so there's nothing to explain) or
  /// while genuinely deletable.
  ///
  /// Worded as an accident prevented, not a permission (spec D1,
  /// `docs/specs/sync-backend.md` §2: the household is flat by design --
  /// this is "removing this profile would break something", never "you
  /// aren't allowed to").
  String? _deleteBlockedReason(
    AppLocalizations l10n, {
    required bool canDelete,
  }) {
    final member = widget.member;
    if (member == null || canDelete) {
      return null;
    }
    if (member.userId != null) {
      return l10n.memberEditDeleteBlockedClaimed;
    }
    return l10n.memberEditDeleteBlockedLastMember;
  }

  int _firstFreeColor() {
    final usedColors = _currentMembers.map((m) => m.color).toSet();
    const seedColors = CategoryRepository.seedColors;
    return seedColors.firstWhere(
      (color) => !usedColors.contains(color),
      orElse: () => seedColors[_currentMembers.length % seedColors.length],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final canDelete = _canDelete;
    final deleteBlockedReason = _deleteBlockedReason(
      l10n,
      canDelete: canDelete,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? l10n.memberEditEditTitle : l10n.memberEditNewTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          semantic(
            'members.edit.name',
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.memberEditNameLabel),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.memberEditColorLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          ColorSwatchPicker(
            colors: CategoryRepository.seedColors,
            selected: _color,
            onSelected: (value) => setState(() => _color = value),
            semanticIdPrefix: 'members.edit.color',
          ),
          const SizedBox(height: 24),
          // T1.7: a claimed or last-remaining member gets no Delete button
          // (see _canDelete) -- previously nothing took its place, a quiet
          // dead end where the (already-shipped) A1 audit item told the
          // user deletion would now work. This explanation takes the
          // button's place instead, on its own line (never squeezed into
          // the Row below, which visual QA already flagged for overflow at
          // large text scales -- see settings_group.dart's stacking fix).
          if (deleteBlockedReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: semantic(
                'members.edit.deleteBlockedReason',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        deleteBlockedReason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              if (canDelete)
                semantic(
                  'members.edit.delete',
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(l10n.commonDelete),
                  ),
                ),
              const Spacer(),
              semantic(
                'members.edit.save',
                child: FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(l10n.commonSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final repo = ref.read(householdRepositoryProvider);
    final existing = widget.member;
    if (existing != null) {
      await repo.renameMember(existing.id, name);
      await repo.recolorMember(existing.id, _color);
    } else {
      final householdId = ref.read(bootstrapProvider).requireValue;
      await repo.addMember(householdId, name: name, color: _color);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.member;
    if (existing == null) {
      return;
    }
    final confirmed = await showMemberDeleteDialog(
      context,
      memberName: existing.name,
    );
    if (!confirmed || !mounted) {
      return;
    }
    // Unreachable in practice TODAY: `_canDelete` above still hides this
    // action for a claimed (`userId != null`) or last-remaining member, so
    // `MemberService.deleteMember` throwing here would be a genuine bug (or
    // an exceedingly rare cross-device race), not an expected runtime
    // failure -- left to crash rather than folded into an inline error
    // state, mirroring `_AdoptRow._adopt` (`account_section.dart`)'s
    // identical reasoning.
    //
    // WHOEVER UNHIDES THIS FOR CLAIMED MEMBERS (F10, backlog C-2) MUST
    // REVISIT THE LINE ABOVE. `deleteMember` now routes by claim state and
    // the claimed path throws `ClaimedMemberRemovalFailure`, which is an
    // EXPECTED failure, not a bug: it needs the network, it changed nothing
    // locally, and the person the user tried to remove is still in the
    // household. That exception's own doc comment requires it be shown
    // inline. "Left to crash" is correct only while `_canDelete` keeps the
    // claimed path unreachable; relax that gate without adding the inline
    // error state and a real network failure on a destructive action is
    // silently lost.
    await ref.read(memberServiceProvider).deleteMember(existing.id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
