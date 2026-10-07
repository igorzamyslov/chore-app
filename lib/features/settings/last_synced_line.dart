/// The relative "Last synced <time>" line under Settings -> Account's
/// linked-household subtitle (spec `docs/specs/sync-freshness.md` §2.4),
/// together with the ticker that keeps it true while the screen stays open
/// (backlog A-2b).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/settings/relative_time.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Settings -> Account's relative last-sync line: `Last synced 10 minutes
/// ago` and friends, read from the `syncLastPulledAt` cursor the engine
/// persists on every successful pull
/// (`SettingsRepository.setSyncLastPulledAt`), and **nothing at all** until
/// there is a cursor to render.
///
/// Only ever mounted from the LINKED branch of the Account section's
/// signed-in tile, which is what makes the unconditional [settingsProvider]
/// watch here equivalent to the `householdName == null`-gated read it
/// replaced: the cursor is meaningless while this device is unlinked, and
/// while it is unlinked this widget does not exist.
///
/// **Why this owns a `Timer` (backlog A-2b).** The text is derived from
/// "now", and nothing in the provider graph moves as time passes:
/// [clockProvider] is a plain [Provider] that never re-emits, and
/// [settingsProvider] only re-emits when the cursor is actually rewritten.
/// So without a trigger of its own the line was correct exactly once -- at
/// the instant the tile was built -- and a Settings screen left open for
/// twenty minutes went on claiming the sync was ten minutes old. The tick is
/// therefore a `setState` from a timer this [State] owns and cancels, not a
/// provider recomputation; an equal `AsyncData` re-emission would correctly
/// be treated as no change, so a reactive-only version could not work.
///
/// **The timer is boundary-aligned and band-derived, never a fixed
/// interval,** because [_lastSyncedText]'s own bands are (see
/// `nextRelativeTimeChange`): whole minutes under an hour, whole hours under a
/// day, and beyond that a fixed calendar date that will never change again --
/// so past
/// 24 hours no timer is armed at all, and in the hours band it wakes once an
/// hour rather than 60 times. Worst case is 60 wakes in the first hour and 23
/// more that day, each one a string format and a one-`Text` rebuild.
///
/// Cancelled in [State.dispose], which is what keeps it out of
/// `flutter_test`'s "a Timer is still pending" check: that check runs *after*
/// the binding unmounts the tree (`TestWidgetsFlutterBinding._runTest` calls
/// `runApp(Container(...))` and pumps before `_verifyInvariants()`), so a
/// timer released on disposal is not a leak. `AppShell`'s `_KeepAlivePage`
/// does keep a visited tab alive, so the ticker outlives the tab being
/// looked at and stops only when the screen leaves the tree; at one cheap
/// wake a minute, with both platforms suspending or throttling timers for a
/// backgrounded app, that is not worth a lifecycle observer.
class LastSyncedLine extends ConsumerStatefulWidget {
  /// Creates the last-synced line.
  const LastSyncedLine({super.key});

  @override
  ConsumerState<LastSyncedLine> createState() => _LastSyncedLineState();
}

class _LastSyncedLineState extends ConsumerState<LastSyncedLine>
    with RelativeTimeTicker<LastSyncedLine> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The DEVICE-clock stamp of this session's last pull when there is one
    // (spec §2.5 amendment 2026-10-06, `syncLastPullCompletedAtProvider`):
    // the persisted cursor is server time, and "10 minutes ago" computed
    // from the device clock against a server stamp was off by the clock
    // skew. The cursor remains the fallback before the first pull of the
    // session, when it is the only record there is.
    final completedAt = ref.watch(syncLastPullCompletedAtProvider);
    final lastPulledAtRaw = ref
        .watch(settingsProvider)
        .valueOrNull
        ?.syncLastPulledAt;
    final lastPulledAt =
        completedAt ??
        (lastPulledAtRaw == null ? null : DateTime.parse(lastPulledAtRaw));
    // Spec §2.4 amendment 2026-10-06: how many changes are still waiting
    // to be sent. `0` while unlinked or still loading, so the line is
    // simply absent then.
    final pending = ref.watch(syncPendingCountProvider).valueOrNull ?? 0;

    final lines = <Widget>[];
    if (lastPulledAt == null) {
      stopTicking();
      // Deliberately semantics-free: while there is no cursor there must be
      // no `settings.account.lastSynced` node for E2E or widget tests to
      // find, exactly as the omitted widget it replaced had none.
    } else {
      final now = ref.watch(clockProvider).now();
      tickAt(
        nextRelativeTimeChange(now: now, then: lastPulledAt),
        now: now,
      );
      lines.add(
        semantic(
          'settings.account.lastSynced',
          child: Text(
            _lastSyncedText(
              l10n,
              Localizations.localeOf(context).toString(),
              now: now,
              lastPulledAt: lastPulledAt,
            ),
          ),
        ),
      );
    }
    if (pending > 0) {
      lines.add(
        semantic(
          'settings.account.pendingChanges',
          child: Text(l10n.syncPendingChanges(pending)),
        ),
      );
    }
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }
}

/// The relative "Last synced" text for [LastSyncedLine] (spec
/// `docs/specs/sync-freshness.md` §2.4): 'just now' under a minute,
/// otherwise pluralized minutes/hours up to a day, else a locale-formatted
/// weekday + month + day (e.g. 'Fri, Jul 31') via `package:intl` -- never a
/// hardcoded weekday/month name, mirroring
/// `chore_occurrence_tile.dart`'s `futureDueText`.
String _lastSyncedText(
  AppLocalizations l10n,
  String localeName, {
  required DateTime now,
  required DateTime lastPulledAt,
}) {
  final relative = relativeTimeSince(now: now, then: lastPulledAt);
  return switch (relative.band) {
    RelativeTimeBand.justNow => l10n.settingsAccountLastSyncedJustNow,
    RelativeTimeBand.minutes => l10n.settingsAccountLastSyncedMinutes(
      relative.count,
    ),
    RelativeTimeBand.hours => l10n.settingsAccountLastSyncedHours(
      relative.count,
    ),
    RelativeTimeBand.date => l10n.settingsAccountLastSyncedOn(
      DateFormat.MMMEd(localeName).format(lastPulledAt.toLocal()),
    ),
  };
}
