/// The Settings tab's destructive 'Reset app data' row and its
/// double-confirm flow (spec `docs/specs/polish-round-1.md` B2), the last
/// row in the Data group, immediately under the export row (spec
/// `docs/specs/theme-v2.md` §4.2; spec
/// `docs/feedback/2026-08-01-field-feedback.md` B4/F7).
///
/// The first dialog's body is state-aware (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A6): a linked device's "there is
/// no cloud backup" claim was FALSE (the household lives on the server;
/// signing in again reconnects it), so the caller passes `linked` and
/// [confirmAndResetAppData] picks the right copy.
///
/// [confirmAndResetAppData] is the flow itself, pulled out of
/// [ResetDataTile] as a top-level function so the startup error screen can
/// reach it too (`lib/app/app.dart`'s `_ErrorScaffold`, spec
/// `docs/feedback/2026-08-08-prerelease-audit.md` S2): a database-open
/// failure never reaches Settings, so before this the only route to a
/// recovery wipe was uninstalling the app.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/features/settings/destructive_confirm.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs the whole reset-app-data flow: the spec's double-confirm (two
/// chained dialogs; a cancel anywhere is a no-op and leaves the database
/// untouched) and then, only after both confirms, the wipe.
///
/// [linked] picks the first dialog's body — see the library doc comment
/// above for why that distinction matters.
///
/// After both confirms, in this order:
///
/// 1. cancel the scheduled digest notification,
/// 2. sign out of the current Supabase session (spec
///    `docs/feedback/2026-08-08-prerelease-audit.md` P3 — unlike the A1.2
///    Disconnect action in `account_section.dart`, which deliberately keeps
///    the session and only unlinks the device, Reset is the clean-slate
///    operation and ends it),
/// 3. [resetAppData],
/// 4. invalidate [settingsProvider], whose device-settings row the wipe just
///    deleted out from under its already-running watch stream — needed
///    regardless of household state, since `ChoreApp` watches it
///    unconditionally for locale/theme.
///
/// [bootstrapProvider] needs no explicit invalidation (spec
/// `docs/specs/onboarding-v2.md` §2): wiping the `households` table flips
/// [householdGateProvider]'s stream to `null` on its own, and `ChoreApp`
/// reacts by swapping straight back to `WelcomeScreen` — the TRUE
/// fresh-install state post-onboarding-v2, not a silently re-bootstrapped
/// household.
///
/// Steps 1 and 2 are individually best-effort
/// ([_cancelNotifications]/[_signOut]): a network hiccup signing out, or an
/// OS plugin hiccup cancelling a notification, must never block the wipe —
/// the double-confirmed delete is the one promise in this flow that must
/// always be kept. **Do not reorder
/// them after the wipe and do not let either throw.**
///
/// If [resetAppData] itself throws, this shows
/// [AppLocalizations.settingsResetError] as a snackbar rather than letting
/// the exception propagate: the startup error screen has no error handling
/// of its own, and the broken database connection that put a user there is
/// exactly what the wipe has to write through, so this is a routine
/// outcome on that path rather than an exotic one.
Future<void> confirmAndResetAppData(
  BuildContext context,
  WidgetRef ref, {
  required bool linked,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await confirmTwoStepDestructiveAction(
    context,
    first: DestructiveConfirmStep(
      title: l10n.settingsResetConfirm1Title,
      body: linked
          ? l10n.settingsResetConfirm1BodyLinked
          : l10n.settingsResetConfirm1Body,
      confirmLabel: l10n.settingsResetConfirm1Action,
      cancelLabel: l10n.commonCancel,
      confirmSemanticId: 'settings.reset.confirm1',
      cancelSemanticId: 'settings.reset.cancel1',
    ),
    second: DestructiveConfirmStep(
      title: l10n.settingsResetConfirm2Title,
      body: l10n.settingsResetConfirm2Body,
      confirmLabel: l10n.settingsResetConfirm2Action,
      cancelLabel: l10n.commonCancel,
      // Note the irregular ids: `confirm2` but plain `cancel`. Both are
      // load-bearing for the E2E flows, which select only by id.
      confirmSemanticId: 'settings.reset.confirm2',
      cancelSemanticId: 'settings.reset.cancel',
    ),
  );
  if (!confirmed || !context.mounted) {
    return;
  }

  // Two side effects that live OUTSIDE the database transaction
  // resetAppData wipes (spec docs/feedback/2026-08-08-prerelease-audit.md
  // P3). Both run BEFORE the wipe and are individually best-effort -- see
  // this function's doc comment.
  await _cancelNotifications(ref);
  await _signOut(ref);

  final database = ref.read(appDatabaseProvider);
  try {
    await resetAppData(database);
  } on Object catch (_) {
    // `on Object`, not `on Exception`: a closed or corrupted drift/sqlite3
    // connection surfaces as a `StateError` (package:sqlite3's "This
    // database has already been closed"), which is an Error. The usual
    // reason to let an Error crash loudly -- it signals a programming bug
    // -- does not apply here: this path is reached from the app's own
    // broken-database error screen, where "the connection is bad" is the
    // expected failure, not a bug. `on Object catch` rather than a bare
    // `catch` also satisfies `avoid_catches_without_on_clauses`.
    if (context.mounted) {
      showAppSnackbar(context, message: l10n.settingsResetError);
    }
    return;
  }
  ref.invalidate(settingsProvider);
}

/// Cancels EVERY scheduled notification -- the digest horizon, every
/// per-chore reminder and every evening slot (spec
/// `docs/specs/notifications-n2.md` §9.2). Best-effort: see
/// [confirmAndResetAppData]'s doc comment on why a failure here must never
/// block the wipe that follows.
///
/// Widened from the digest alone at schema v13, and the reason is worth
/// stating: a wipe that leaves per-chore reminders armed is strictly worse
/// than the digest case G-12 fixed, because a reminder NAMES a chore that
/// no longer exists.
///
/// Catches [Object], not just [Exception], and this breadth is load-bearing
/// rather than lazy: the failure mode actually observed here is
/// `FlutterLocalNotificationsPlugin.initialize()` throwing a
/// `LateInitializationError` -- an [Error], not an [Exception] -- when no
/// platform implementation is registered. An `on Exception` clause lets
/// exactly that escape and takes the wipe down with it, which is the one
/// outcome this flow may never produce.
///
/// Since backlog G-12 this may WAIT: `cancelAll()` rides the scheduler's
/// serialized notification-write queue, so if a recompute or the notification
/// action's horizon rewrite is mid-loop, the cancel queues behind it. That
/// is the point — without it the apply could re-arm slots this cancel had
/// already cleared, leaving a wiped app still notifying. The wait does not
/// weaken the "never block the wipe" promise beyond what was already true:
/// `cancelAll()` has always awaited `ensureInitialized()`, i.e. a
/// `plugin.initialize()` platform call, so this path already depended on
/// the plugin's calls returning, and the [Object] guard below was always
/// about a throw rather than a hang.
Future<void> _cancelNotifications(WidgetRef ref) async {
  try {
    await ref.read(notificationSchedulerProvider).cancelAll();
  } on Object {
    // Best-effort -- see doc comment above.
  }
}

/// Signs out of the current Supabase session, if any. Safe to call
/// unconditionally even when already signed out (`NoopAuthGateway.signOut()`
/// is a no-op; `SupabaseAuthGateway.signOut()` is wrapped the same way
/// regardless). Best-effort: see [confirmAndResetAppData]'s doc comment on
/// why a failure here must never block the wipe that follows. Catches
/// [Object] for the same reason [_cancelNotifications] does: the guarantee is
/// about
/// the wipe surviving, and an [Error] thrown out of a plugin or transport
/// blocks it just as effectively as an [Exception] would.
Future<void> _signOut(WidgetRef ref) async {
  try {
    await ref.read(authGatewayProvider).signOut();
  } on Object {
    // Best-effort -- see doc comment above.
  }
}

/// The destructive 'Reset app data' row at the very bottom of Settings,
/// immediately under the export row in the Data section -- the only row in
/// the whole screen drawn in `error`.
///
/// Tapping it runs [confirmAndResetAppData].
class ResetDataTile extends ConsumerWidget {
  /// Creates the reset row.
  const ResetDataTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final linked =
        ref.watch(settingsProvider).valueOrNull?.syncHouseholdId != null;
    return semantic(
      'settings.reset',
      child: SettingsRow(
        icon: Icons.delete_forever_outlined,
        label: l10n.settingsResetEntry,
        destructive: true,
        onTap: () => confirmAndResetAppData(context, ref, linked: linked),
      ),
    );
  }
}
