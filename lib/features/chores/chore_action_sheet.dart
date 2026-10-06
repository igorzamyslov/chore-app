/// The action sheet for a chore: a pending occurrence's tile, or a paused
/// chore's row.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The action a user picked from [showChoreActionSheet], or `null` if they
/// dismissed it without picking one.
enum ChoreMenuAction {
  /// Complete the pending occurrence crediting ANOTHER member (A-5, spec
  /// `docs/feedback/2026-08-07-field-feedback.md` B1). Offered only when
  /// `showMarkDoneFor` is true.
  markDoneFor,

  /// Hand the open turn to another member (persona review 2026-10-06 C2).
  /// Offered only when `showReassign` is true.
  reassign,

  /// Skip the pending occurrence.
  skip,

  /// Open the chore in the edit form.
  edit,

  /// Pause the chore (removing its pending occurrence).
  pause,

  /// Resume a paused chore (persona review 2026-10-06 C4). Offered only on
  /// the paused variant of the sheet.
  resume,

  /// Delete the chore, after confirmation.
  delete,
}

/// Shows the chore's bottom sheet and resolves to the chosen
/// [ChoreMenuAction] (or `null` if dismissed).
///
/// Two variants:
///
/// - a pending occurrence (the default): optionally mark-done-for and
///   reassign, then skip/edit/pause/delete;
/// - [paused] (persona review 2026-10-06 C4): resume/edit/delete only — a
///   paused chore has no open turn to skip, mark done or pause again, but
///   it can still be changed or removed without resuming it first.
///
/// Rows are full-width with 22dp icons and a ≥48dp height (spec
/// `docs/specs/theme-v2.md` §4.5); delete sits last, in `error`. The drag
/// handle comes from the app-wide `BottomSheetThemeData`
/// (`lib/app/theme.dart`) -- never hand-rolled here.
///
/// [showMarkDoneFor] adds ONE ordinary row at the top (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1). It is deliberately
/// nothing more than that: the constraint on this feature is that it stays
/// rare — no tile placement, no prompt on the common path, no banner, and
/// completing a chore as yourself stays exactly one tap. The caller
/// computes the gate so this sheet stays Riverpod-free. Ignored when
/// [paused]. [showReassign] adds "Reassign this turn…" right below it, on
/// the same terms (persona review 2026-10-06 C2: somebody else to hand the
/// turn to).
Future<ChoreMenuAction?> showChoreActionSheet(
  BuildContext context, {
  required bool showMarkDoneFor,
  bool showReassign = false,
  bool paused = false,
}) {
  return showModalBottomSheet<ChoreMenuAction>(
    context: context,
    builder: (sheetContext) {
      final errorColor = Theme.of(sheetContext).colorScheme.error;
      final l10n = AppLocalizations.of(sheetContext);
      Widget row(
        ChoreMenuAction action, {
        required String id,
        required IconData icon,
        required String label,
      }) {
        return semantic(
          id,
          child: ListTile(
            leading: Icon(icon, size: 22),
            title: Text(label),
            onTap: () => Navigator.pop(sheetContext, action),
          ),
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (paused)
              row(
                ChoreMenuAction.resume,
                id: 'chores.menu.resume',
                icon: Icons.play_circle_outline,
                label: l10n.choresPausedResume,
              ),
            if (!paused && showMarkDoneFor)
              row(
                ChoreMenuAction.markDoneFor,
                id: 'chores.menu.markDoneFor',
                icon: Icons.how_to_reg_outlined,
                label: l10n.choresMenuMarkDoneFor,
              ),
            if (!paused && showReassign)
              row(
                ChoreMenuAction.reassign,
                id: 'chores.menu.reassign',
                icon: Icons.swap_horiz,
                label: l10n.choresMenuReassign,
              ),
            if (!paused)
              row(
                ChoreMenuAction.skip,
                id: 'chores.menu.skip',
                icon: Icons.skip_next_outlined,
                label: l10n.choresMenuSkip,
              ),
            row(
              ChoreMenuAction.edit,
              id: 'chores.menu.edit',
              icon: Icons.edit_outlined,
              label: l10n.choresMenuEdit,
            ),
            if (!paused)
              row(
                ChoreMenuAction.pause,
                id: 'chores.menu.pause',
                icon: Icons.pause_circle_outlined,
                label: l10n.choresMenuPause,
              ),
            semantic(
              'chores.menu.delete',
              child: ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: errorColor,
                  size: 22,
                ),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: errorColor),
                ),
                onTap: () {
                  Navigator.pop(sheetContext, ChoreMenuAction.delete);
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
