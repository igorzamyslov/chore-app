/// The Shopping app bar's one-line status subtitle.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/features/settings/relative_time.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "7 left" -- and, while the household is linked, " · synced 2 min ago" or
/// " · 3 changes waiting to send" (persona findings F1/F10, tom-shopping
/// PP2/MF2).
///
/// Tom, at the dairy shelf, could not tell "nothing new" from "nothing
/// arrived": a healthy sync showed nothing at all, and "Last synced" lived
/// two taps away in Settings. This line is that same data (the device-clock
/// `syncLastPullCompletedAtProvider`, falling back to the persisted cursor
/// before the first pull of the session -- exactly what the Settings line
/// reads) quietly on the screen where it is needed.
///
/// **Unlinked households see only the remaining count:** there is no sync to
/// report on, so claiming "synced" would be false and "waiting to send"
/// meaningless. The linked gate is the same one the pull-to-refresh uses
/// (`syncEngineProvider` is not a [NoopSyncEngine]).
///
/// **Pending beats synced.** While anything is waiting to send, "synced 2
/// min ago" would be a half-truth about the very thing the person is
/// worried about, so the pending count replaces it.
///
/// The relative time is kept true by the shared [RelativeTimeTicker], the
/// same boundary-aligned timer the Settings line uses.
class ShoppingStatusLine extends ConsumerStatefulWidget {
  /// Creates the status line.
  const ShoppingStatusLine({super.key});

  @override
  ConsumerState<ShoppingStatusLine> createState() => _ShoppingStatusLineState();
}

class _ShoppingStatusLineState extends ConsumerState<ShoppingStatusLine>
    with RelativeTimeTicker<ShoppingStatusLine> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(shoppingItemsProvider).valueOrNull;
    if (items == null) {
      stopTicking();
      return const SizedBox.shrink();
    }
    final remaining = items.where((item) => item.item.checkedAt == null).length;
    final parts = <String>[l10n.shoppingRemainingCount(remaining)];

    final linked = ref.watch(syncEngineProvider) is! NoopSyncEngine;
    var ticking = false;
    if (linked) {
      final pending = ref.watch(syncPendingCountProvider).valueOrNull ?? 0;
      if (pending > 0) {
        parts.add(l10n.syncPendingChanges(pending));
      } else {
        final completedAt = ref.watch(syncLastPullCompletedAtProvider);
        final cursorRaw = ref
            .watch(settingsProvider)
            .valueOrNull
            ?.syncLastPulledAt;
        final lastPulledAt =
            completedAt ??
            (cursorRaw == null ? null : DateTime.tryParse(cursorRaw));
        if (lastPulledAt != null) {
          final now = ref.watch(clockProvider).now();
          ticking = true;
          tickAt(
            nextRelativeTimeChange(now: now, then: lastPulledAt),
            now: now,
          );
          parts.add(
            l10n.shoppingSyncedAgo(
              relativeTimePhrase(
                l10n,
                Localizations.localeOf(context).toString(),
                now: now,
                then: lastPulledAt,
              ),
            ),
          );
        }
      }
    }
    if (!ticking) {
      stopTicking();
    }

    final theme = Theme.of(context);
    return semantic(
      'shopping.status',
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
