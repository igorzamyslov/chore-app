/// The household-rename bottom sheet (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A2), opened from the Members
/// screen's household-name row. Mirrors `member_edit_sheet.dart`'s rename
/// shape exactly: a prefilled name field, disabled-on-empty save.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the modal bottom sheet for renaming the household, prefilled with
/// [currentName].
Future<void> showHouseholdRenameSheet(
  BuildContext context, {
  required String currentName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => semantic(
      'members.household.rename.sheet',
      child: _HouseholdRenameSheet(currentName: currentName),
    ),
  );
}

class _HouseholdRenameSheet extends ConsumerStatefulWidget {
  const _HouseholdRenameSheet({required this.currentName});

  final String currentName;

  @override
  ConsumerState<_HouseholdRenameSheet> createState() =>
      _HouseholdRenameSheetState();
}

class _HouseholdRenameSheetState extends ConsumerState<_HouseholdRenameSheet> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName)
      ..addListener(_onNameChanged);
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
          Text(l10n.householdRenameTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          semantic(
            'members.household.rename.name',
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.householdRenameNameLabel,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Spacer(),
              semantic(
                'members.household.rename.save',
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
    final householdId = ref.read(bootstrapProvider).requireValue;
    await ref
        .read(householdRepositoryProvider)
        .renameHousehold(householdId, name);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}
