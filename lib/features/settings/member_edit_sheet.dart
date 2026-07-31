/// The member add/edit bottom sheet: rename, recolor, save. No delete
/// affordance (spec `docs/specs/members-management.md` §3: member deletion
/// is out of scope until a reassignment story exists for chores
/// referencing the member).
library;

import 'package:chore_app/app/color_swatch_picker.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
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
          Row(
            children: [
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
}
