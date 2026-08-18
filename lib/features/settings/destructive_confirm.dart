/// The shared two-step confirmation used by every irreversible action in
/// Settings (spec `docs/specs/polish-round-1.md` B2).
///
/// Two chained dialogs, not one: the first states what will be lost and is
/// state-aware where that matters, the second is a bare "last chance". A
/// cancel at either step is a no-op — the caller has not started its work
/// yet when [confirmTwoStepDestructiveAction] returns `false`, so there is
/// nothing to undo.
///
/// This lives in its own file rather than inside `reset_flow.dart` because
/// it is deliberately action-agnostic: 'Reset app data' was the first
/// caller, and leave-household / delete-account are the next
/// (`docs/specs/household-lifecycle.md`). Adding a second destructive
/// action means composing a [DestructiveConfirmStep] pair, NOT copying a
/// dialog builder.
///
/// Semantic ids are passed in per step rather than derived from a prefix on
/// purpose: the existing reset ids are irregular
/// (`settings.reset.cancel1`/`confirm1`, then `settings.reset.cancel`/
/// `confirm2`) and they are load-bearing for the Maestro E2E flows, which
/// select only by id. A prefix scheme would have to either break them or
/// encode the irregularity, so the ids stay explicit and greppable.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:flutter/material.dart';

/// One dialog in a [confirmTwoStepDestructiveAction] chain.
class DestructiveConfirmStep {
  /// Creates a confirmation step.
  const DestructiveConfirmStep({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.confirmSemanticId,
    required this.cancelSemanticId,
  });

  /// The dialog's title.
  final String title;

  /// The dialog's body: what exactly is about to be lost.
  final String body;

  /// Label of the destructive confirm action, drawn in `error`.
  final String confirmLabel;

  /// Label of the non-destructive cancel action.
  final String cancelLabel;

  /// Semantic id of the confirm button.
  final String confirmSemanticId;

  /// Semantic id of the cancel button.
  final String cancelSemanticId;
}

/// Shows [first] and, only if it is confirmed, [second]; returns `true`
/// only when BOTH were confirmed.
///
/// Returns `false` for a cancel, a barrier dismiss, or an unmounted
/// [context] between the two dialogs — every path that is not an explicit
/// double confirmation, so a caller can treat `true` as the user's
/// unambiguous go-ahead and needs no checks of its own.
Future<bool> confirmTwoStepDestructiveAction(
  BuildContext context, {
  required DestructiveConfirmStep first,
  required DestructiveConfirmStep second,
}) async {
  if (!await _showStep(context, first)) {
    return false;
  }
  if (!context.mounted) {
    return false;
  }
  return _showStep(context, second);
}

Future<bool> _showStep(
  BuildContext context,
  DestructiveConfirmStep step,
) async {
  final errorColor = Theme.of(context).colorScheme.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(step.title),
        content: Text(step.body),
        actions: [
          semantic(
            step.cancelSemanticId,
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(step.cancelLabel),
            ),
          ),
          semantic(
            step.confirmSemanticId,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: errorColor),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(step.confirmLabel),
            ),
          ),
        ],
      );
    },
  );
  // A barrier dismiss pops with no value; treat it as a cancel.
  return confirmed ?? false;
}
