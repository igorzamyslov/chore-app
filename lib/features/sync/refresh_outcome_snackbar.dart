/// The one place a USER-INITIATED sync's result becomes a snackbar (spec
/// `docs/specs/sync-freshness.md` §2.3, amended 2026-10-06): shared by the
/// chores and shopping pull-to-refresh indicators and by the Settings ->
/// Account sync tile (§2.4 amendment), so the three surfaces can never
/// disagree about what a given [RefreshOutcome] means.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs `SyncEngine.refreshNow()` and reports a failure as a snackbar.
/// Success stays silent -- the list (or the "Last synced" line) simply
/// updates, which is the platform convention.
///
/// Uses `refreshNow()`, not `pushDirty()`: the latter swallows every error
/// by contract (spec `sync-backend.md` §8.3), so the indicator used to spin
/// and stop identically whether the sync worked or the phone was offline --
/// found by the 2026-08-07 persona walkthrough.
///
/// WHEN THE FAILURE BRANCH IS ACTUALLY REACHED is narrower than it looks:
/// `syncEngineProvider` is gated on `settings.syncHouseholdId`, and the
/// engine's own startup pull and 60s poll run the same revocation probe. So
/// in the common case the ENGINE notices a revocation first, calls
/// `clearSyncLink()`, and `syncEngineProvider` becomes a `NoopSyncEngine`
/// whose `refreshNow()` returns [RefreshOutcome.ok] -- meaning a later
/// gesture reports success and says nothing. That is not a gap: a device
/// that has been revoked is told so by the revocation notice (spec
/// `docs/specs/household-lifecycle.md` §3.5), which is the primary surface.
/// `syncRefreshErrorRevoked` covers the narrower race where the user's own
/// gesture is the first probe after the server-side removal, and it exists
/// because in exactly that case `syncRefreshError`'s "will sync later" is a
/// promise the app has already made false. [RefreshOutcome.offline] stands
/// for two different situations, and only one of them is a delay: if the
/// failure was a revocation, `_pullSinceInner` has ALREADY called
/// `setMembershipRevoked()` and `clearSyncLink()` before returning, so the
/// just-written row is read with a one-shot query rather than
/// `settingsProvider`'s stream, which may not have re-emitted the write yet.
///
/// [RefreshOutcome.rejected] (technical review 2026-10-06 #5) is the third
/// case: the server REFUSED a row, no retry will fix it, and "will sync
/// later" would again be false -- `syncRefreshErrorRejected` says so.
Future<void> refreshAndReport(BuildContext context, WidgetRef ref) async {
  final outcome = await ref.read(syncEngineProvider).refreshNow();
  if (outcome == RefreshOutcome.ok || !context.mounted) {
    return;
  }
  final revoked = (await ref.read(settingsRepositoryProvider).ensureSettings())
      .membershipRevoked;
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  showAppSnackbar(
    context,
    message: switch (outcome) {
      RefreshOutcome.rejected => l10n.syncRefreshErrorRejected,
      RefreshOutcome.offline when revoked => l10n.syncRefreshErrorRevoked,
      RefreshOutcome.offline || RefreshOutcome.ok => l10n.syncRefreshError,
    },
  );
}
