/// Shared snackbar-presentation helper.
library;

import 'package:flutter/material.dart';

/// Shows a snackbar with [message] (and optional [action]) via the nearest
/// [ScaffoldMessenger].
///
/// Latest-wins: [ScaffoldMessengerState.showSnackBar] normally QUEUES
/// snackbars, so completing several chores (or quick-adding several
/// shopping items) in quick succession would otherwise present one
/// snackbar after another rather than replacing the message — reading as
/// "it never goes away". Calling [ScaffoldMessengerState.clearSnackBars]
/// first drops anything queued or showing, so only the most recent action's
/// snackbar is ever presented.
///
/// **`persist: false` is load-bearing, not decorative** (field feedback B1,
/// `docs/feedback/2026-08-01-field-feedback.md`): [SnackBar.persist]
/// defaults to `true` whenever [SnackBar.action] is non-null (Flutter's own
/// default, not a bug in this app), which makes the `duration` timer a
/// no-op — the bar then only closes when the user taps the action or
/// another snackbar replaces it. Every close/skip toast here carries an
/// UNDO action, so without this override they persisted forever — the
/// exact "Done snackbar never goes away" report. This was verified by
/// reproduction (see `test/app/sticky_snackbar_test.dart`): a plain
/// `IndexedStack`/tab-switch theory was ruled out first (it did not
/// reproduce), then this was found to reproduce even with no tab switch at
/// all, isolating the true cause to this flag.
///
/// Uses [SnackBarBehavior.floating] with a modest uniform margin: paired
/// with the app shell's nested [ScaffoldMessenger] (see
/// `lib/app/app_shell.dart`), this keeps the snackbar within the current
/// tab's own inner `Scaffold` — above the hand-rolled bottom tab bar, with
/// comfortable spacing, rather than flush against it.
void showAppSnackbar(
  BuildContext context, {
  required String message,
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        // Matches SnackBar's own default — spelled out because it's a
        // deliberate choice this helper documents, not an incidental one.
        // ignore: avoid_redundant_argument_values
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: action,
        // See the doc comment above: without this, an action snackbar
        // never auto-dismisses.
        persist: false,
      ),
    );
}
