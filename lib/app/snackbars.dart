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
      ),
    );
}
