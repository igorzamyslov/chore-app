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
/// it is deliberately action-agnostic: adding another two-step destructive
/// action means composing a [DestructiveConfirmStep] pair, NOT copying a
/// dialog builder.
///
/// 'Reset app data' is currently the only caller, and an earlier version of
/// this comment predicted the household exits would be the next. They are
/// NOT, and that is settled rather than pending:
/// `docs/specs/household-lifecycle.md` §3.3 gives all three exits ONE
/// confirm shape — the shared sheet in `exit_confirm_sheet.dart`, whose
/// body is followed by D-L3's unchecked "also delete this phone's copy"
/// checkbox, which a [DestructiveConfirmStep] has nowhere to put. Leave and
/// member-removal have exactly one confirmation each. Delete-account is the
/// one exit that also gets a second gate (D-L6), and it gets it as a single
/// final dialog AFTER that sheet — so if a one-step variant of this builder
/// is ever wanted, that is the caller that wants it.
///
/// Semantic ids are passed in per step rather than derived from a prefix on
/// purpose: the existing reset ids are irregular
/// (`settings.reset.cancel1`/`confirm1`, then `settings.reset.cancel`/
/// `confirm2`) and they are load-bearing for `reset_flow_test.dart` and
/// `test/widget_test.dart`, which select only by id. (An earlier version of
/// this comment said Maestro; no E2E flow references them —
/// `grep -rn "settings.reset" e2e/` is empty.) A prefix scheme would have to
/// either break them or encode the irregularity, so the ids stay explicit
/// and greppable.
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
        // An `AlertDialog` puts its content in a bare `Flexible` unless
        // asked to be scrollable, so a body taller than the dialog is
        // silently CLIPPED -- no exception, no scrollbar, and the rest of
        // the sentence simply unreachable. `settingsResetConfirm1BodyLinked`
        // in German already reaches that at a large text scale on a small
        // phone. Same class of bug Task 12 fixed in `exit_confirm_sheet.dart`
        // and Task 16 in `member_delete_dialog.dart`; guarded by
        // `test/features/settings/destructive_confirm_test.dart`.
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
