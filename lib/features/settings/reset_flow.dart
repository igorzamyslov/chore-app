/// The Settings tab's destructive 'Reset app data' row and its
/// double-confirm flow (spec `docs/specs/polish-round-1.md` B2), the last
/// row in the Data group, immediately under the export row (spec
/// `docs/specs/theme-v2.md` §4.2; spec
/// `docs/feedback/2026-08-01-field-feedback.md` B4/F7).
///
/// The first dialog's body is state-aware (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A6): a linked device's "there is
/// no cloud backup" claim was FALSE (the household lives on the server;
/// signing in again reconnects it) -- [ResetDataTile] reads
/// [settingsProvider]'s `syncHouseholdId` to pick the right copy.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The destructive 'Reset app data' row at the very bottom of Settings,
/// immediately under the export row in the Data section -- the only row in
/// the whole screen drawn in `error`.
///
/// Tapping it runs the spec's double-confirm (two chained dialogs; a
/// cancel anywhere is a no-op and leaves the database untouched).
/// Only after both confirms does it cancel the scheduled digest
/// notification, sign out of the current Supabase session (spec
/// `docs/feedback/2026-08-08-prerelease-audit.md` P3 -- unlike the A1.2
/// Disconnect action in `account_section.dart`, which deliberately keeps
/// the session and only unlinks the device, Reset is the clean-slate
/// operation and ends it), call [resetAppData], and invalidate
/// [settingsProvider] (whose device-settings row the reset just deleted out
/// from under its already-running watch stream, needed regardless of
/// household state since `ChoreApp` watches it unconditionally for
/// locale/theme). [bootstrapProvider] itself needs no explicit invalidation
/// (spec `docs/specs/onboarding-v2.md` §2): wiping the `households` table
/// flips [householdGateProvider]'s stream to `null` on its own, and
/// `ChoreApp` reacts by swapping straight back to `WelcomeScreen` -- the
/// TRUE fresh-install state post-onboarding-v2, not a silently
/// re-bootstrapped household.
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
        onTap: () => _confirmAndReset(context, ref, linked: linked),
      ),
    );
  }

  Future<void> _confirmAndReset(
    BuildContext context,
    WidgetRef ref, {
    required bool linked,
  }) async {
    final firstConfirmed = await _showFirstDialog(context, linked: linked);
    if (!firstConfirmed || !context.mounted) {
      return;
    }
    final secondConfirmed = await _showSecondDialog(context);
    if (!secondConfirmed || !context.mounted) {
      return;
    }

    // Two side effects that live OUTSIDE the database transaction
    // resetAppData wipes (spec docs/feedback/2026-08-08-prerelease-audit.md
    // P3): the scheduled digest notification, and -- unlike Disconnect
    // (household_link_service.dart's deliberate keep-the-session inverse
    // of this action) -- the Supabase session itself. Reset is the "clean
    // slate" operation: double-confirmed, and the one most likely to be
    // used right before handing a phone to someone else, so a surviving
    // session for the previous account is the wrong default here, unlike
    // for Disconnect. Both run BEFORE the wipe and are individually
    // best-effort (wrapped below): a network hiccup signing out, or an OS
    // plugin hiccup cancelling a notification, must never block the wipe
    // itself -- the double-confirmed delete is the one promise in this
    // flow that must always be kept.
    await _cancelDigest(ref);
    await _signOut(ref);

    final database = ref.read(appDatabaseProvider);
    await resetAppData(database);
    ref.invalidate(settingsProvider);
  }

  /// Cancels the scheduled digest notification, if any. Best-effort: see
  /// the doc comment in [_confirmAndReset] on why a failure here must
  /// never block the wipe that follows.
  ///
  /// Catches [Object], not just [Exception], and this breadth is
  /// load-bearing rather than lazy: the failure mode actually observed
  /// here is `FlutterLocalNotificationsPlugin.initialize()` throwing a
  /// `LateInitializationError` -- an [Error], not an [Exception] -- when
  /// no platform implementation is registered. An `on Exception` clause
  /// lets exactly that escape and takes the wipe down with it, which is
  /// the one outcome this flow may never produce.
  Future<void> _cancelDigest(WidgetRef ref) async {
    try {
      await ref.read(notificationSchedulerProvider).cancelDigest();
    } on Object {
      // Best-effort -- see doc comment above.
    }
  }

  /// Signs out of the current Supabase session, if any. Safe to call
  /// unconditionally even when already signed out (spec's analysis:
  /// `NoopAuthGateway.signOut()` is a no-op; `SupabaseAuthGateway.
  /// signOut()` is wrapped the same way regardless). Best-effort: see the
  /// doc comment in [_confirmAndReset] on why a failure here must never
  /// block the wipe that follows. Catches [Object] for the same reason
  /// [_cancelDigest] does: the guarantee is about the wipe surviving, and
  /// an [Error] thrown out of a plugin or transport blocks it just as
  /// effectively as an [Exception] would.
  Future<void> _signOut(WidgetRef ref) async {
    try {
      await ref.read(authGatewayProvider).signOut();
    } on Object {
      // Best-effort -- see doc comment above.
    }
  }

  Future<bool> _showFirstDialog(
    BuildContext context, {
    required bool linked,
  }) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsResetConfirm1Title),
          content: Text(
            linked
                ? l10n.settingsResetConfirm1BodyLinked
                : l10n.settingsResetConfirm1Body,
          ),
          actions: [
            semantic(
              'settings.reset.cancel1',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.reset.confirm1',
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: errorColor),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.settingsResetConfirm1Action),
              ),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<bool> _showSecondDialog(BuildContext context) async {
    final errorColor = Theme.of(context).colorScheme.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsResetConfirm2Title),
          content: Text(l10n.settingsResetConfirm2Body),
          actions: [
            semantic(
              'settings.reset.cancel',
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
            ),
            semantic(
              'settings.reset.confirm2',
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: errorColor),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.settingsResetConfirm2Action),
              ),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}
