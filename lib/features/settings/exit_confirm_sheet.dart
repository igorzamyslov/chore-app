/// The shared confirmation sheet for every household exit (spec
/// `docs/specs/household-lifecycle.md` §3.3, decision D-L3): leaving,
/// being removed, and deleting an account all keep this phone's data by
/// default and offer one explicit opt-in to wipe it.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// What the user chose in [showExitConfirmSheet].
class ExitConfirmResult {
  /// Creates a result.
  const ExitConfirmResult({
    required this.confirmed,
    required this.alsoDeleteLocalData,
  });

  /// Whether the user confirmed the exit at all.
  final bool confirmed;

  /// Whether the user additionally opted into wiping this device's data.
  /// Always `false` when [confirmed] is `false`.
  final bool alsoDeleteLocalData;
}

/// Shows the exit confirmation and resolves to the user's choice.
///
/// Dismissing resolves to a declined, non-deleting result -- never null,
/// so callers need no null handling.
Future<ExitConfirmResult> showExitConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  required String semanticPrefix,
}) async {
  final result = await showModalBottomSheet<ExitConfirmResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ExitConfirmSheet(
      title: title,
      body: body,
      actionLabel: actionLabel,
      semanticPrefix: semanticPrefix,
    ),
  );
  return result ??
      const ExitConfirmResult(confirmed: false, alsoDeleteLocalData: false);
}

class _ExitConfirmSheet extends StatefulWidget {
  const _ExitConfirmSheet({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.semanticPrefix,
  });

  final String title;
  final String body;
  final String actionLabel;
  final String semanticPrefix;

  @override
  State<_ExitConfirmSheet> createState() => _ExitConfirmSheetState();
}

class _ExitConfirmSheetState extends State<_ExitConfirmSheet> {
  /// Unchecked in every exit (D-L3): the safe default is the same one
  /// everywhere, including delete-account.
  bool _alsoDeleteLocalData = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(widget.body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          semantic(
            '${widget.semanticPrefix}.deleteLocal',
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _alsoDeleteLocalData,
              title: Text(l10n.exitConfirmDeleteLocalLabel),
              subtitle: Text(l10n.exitConfirmDeleteLocalExplanation),
              onChanged: (value) =>
                  setState(() => _alsoDeleteLocalData = value ?? false),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              semantic(
                '${widget.semanticPrefix}.cancel',
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const ExitConfirmResult(
                      confirmed: false,
                      alsoDeleteLocalData: false,
                    ),
                  ),
                  child: Text(l10n.exitConfirmCancel),
                ),
              ),
              const SizedBox(width: 8),
              semantic(
                '${widget.semanticPrefix}.confirm',
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    ExitConfirmResult(
                      confirmed: true,
                      alsoDeleteLocalData: _alsoDeleteLocalData,
                    ),
                  ),
                  child: Text(widget.actionLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
