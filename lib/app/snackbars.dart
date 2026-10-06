/// Shared snackbar-presentation helper.
library;

import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shows a snackbar with [message] (and optional [action]) via the nearest
/// [ScaffoldMessenger], for [duration] (default 4 s).
///
/// Bulk actions (Clear checked, Put all back) pass a longer [duration] so
/// the Undo stays reachable while the person looks up from the phone
/// (persona finding F4).
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
  Duration duration = const Duration(seconds: 4),
}) {
  // Style (spec docs/specs/theme-v2.md §4.5): a leading check_circle glyph
  // in `inversePrimary` ahead of the message. Ground color, radius, and
  // floating-above-the-tab-bar placement all come from the app-wide
  // `SnackBarThemeData` (`lib/app/theme.dart`) plus the behavior/margin
  // below -- never hardcoded here beyond this icon.
  final inversePrimary = Theme.of(context).colorScheme.inversePrimary;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: inversePrimary, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: action,
        // See the doc comment above: without this, an action snackbar
        // never auto-dismisses.
        persist: false,
      ),
    );
}

/// Shows an ERROR snackbar (persona review B7): the same latest-wins,
/// floating, auto-dismissing presentation as [showAppSnackbar], but with an
/// `error_outline` glyph in `colorScheme.error` instead of the success
/// check, a longer 8 s duration (an error has to be read, not just
/// noticed), and -- when the caller can offer one -- a localised "Retry"
/// action that runs [onRetry].
///
/// `persist: false` for the same reason as in [showAppSnackbar]: the Retry
/// action would otherwise make the bar sticky.
void showAppErrorSnackbar(
  BuildContext context, {
  required String message,
  VoidCallback? onRetry,
}) {
  final scheme = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: onRetry == null
            ? null
            : SnackBarAction(label: l10n.commonRetry, onPressed: onRetry),
        persist: false,
      ),
    );
}
