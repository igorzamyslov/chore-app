/// The relative "Last synced <time>" line under Settings -> Account's
/// linked-household subtitle (spec `docs/specs/sync-freshness.md` §2.4),
/// together with the ticker that keeps it true while the screen stays open
/// (backlog A-2b).
library;

import 'dart:async';

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
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
/// **Why this owns a [Timer] (backlog A-2b).** The text is derived from
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
/// [_nextChange]): whole minutes under an hour, whole hours under a day, and
/// beyond that a fixed calendar date that will never change again -- so past
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

class _LastSyncedLineState extends ConsumerState<LastSyncedLine> {
  /// Re-arming one-shot rather than a [Timer.periodic]: the gap to the next
  /// visible change is not constant.
  Timer? _timer;

  /// The moment [_timer] is currently scheduled for, i.e. the moment the
  /// rendered string next becomes wrong.
  ///
  /// Kept so an unrelated rebuild (a theme or locale change, a settings
  /// write) re-derives the same deadline and leaves the running timer
  /// alone. Cancelling and rescheduling on every build would let a subtree
  /// that rebuilds every 59 seconds postpone the tick indefinitely.
  DateTime? _deadline;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastPulledAtRaw = ref
        .watch(settingsProvider)
        .valueOrNull
        ?.syncLastPulledAt;
    if (lastPulledAtRaw == null) {
      _stopTicking();
      // Deliberately semantics-free: while there is no cursor there must be
      // no `settings.account.lastSynced` node for E2E or widget tests to
      // find, exactly as the omitted widget it replaced had none.
      return const SizedBox.shrink();
    }
    final lastPulledAt = DateTime.parse(lastPulledAtRaw);
    final now = ref.watch(clockProvider).now();
    _tickAt(
      _nextChange(now: now, lastPulledAt: lastPulledAt),
      now: now,
    );
    return semantic(
      'settings.account.lastSynced',
      child: Text(
        _lastSyncedText(
          AppLocalizations.of(context),
          Localizations.localeOf(context).toString(),
          now: now,
          lastPulledAt: lastPulledAt,
        ),
      ),
    );
  }

  /// Schedules the next tick for [deadline], or stops ticking when the text
  /// has reached its final form ([deadline] `null`).
  ///
  /// A deadline already in the past is reachable without any bug: clock skew
  /// between devices can hand us a `lastPulledAt` in the future. Falling back
  /// to [_skewRecheck] rather than scheduling a non-positive delay matters --
  /// a `Timer` with a zero or negative duration fires in the same frame,
  /// which with the `setState` below would spin.
  void _tickAt(DateTime? deadline, {required DateTime now}) {
    if (deadline == null) {
      _stopTicking();
      return;
    }
    if (deadline == _deadline && (_timer?.isActive ?? false)) {
      return;
    }
    _timer?.cancel();
    _deadline = deadline;
    final delay = deadline.difference(now);
    _timer = Timer(
      delay > Duration.zero ? delay : _skewRecheck,
      // Nothing to assign: the text is derived from the clock, and the
      // point of the tick is that the clock has moved.
      () => setState(() {}),
    );
  }

  void _stopTicking() {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
  }
}

/// How long to wait before re-checking when the next change is apparently
/// already behind us (see [_LastSyncedLineState._tickAt]).
const _skewRecheck = Duration(minutes: 1);

/// The moment [_lastSyncedText] starts returning something different, or
/// `null` once it never will.
///
/// Mirrors that function's bands exactly, and must be kept in step with
/// them: whole minutes while under an hour (so the next change is at the
/// next whole minute since [lastPulledAt] -- which also covers the 'just
/// now' band, whose end is the first whole minute), whole hours while under
/// a day, and beyond a day a fixed date formatted from [lastPulledAt] alone,
/// which no passage of time can alter.
DateTime? _nextChange({
  required DateTime now,
  required DateTime lastPulledAt,
}) {
  final elapsed = now.difference(lastPulledAt);
  if (elapsed.inHours < 1) {
    return lastPulledAt.add(Duration(minutes: elapsed.inMinutes + 1));
  }
  if (elapsed.inHours < 24) {
    return lastPulledAt.add(Duration(hours: elapsed.inHours + 1));
  }
  return null;
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
  final elapsed = now.difference(lastPulledAt);
  if (elapsed.inMinutes < 1) {
    return l10n.settingsAccountLastSyncedJustNow;
  }
  if (elapsed.inHours < 1) {
    return l10n.settingsAccountLastSyncedMinutes(elapsed.inMinutes);
  }
  if (elapsed.inHours < 24) {
    return l10n.settingsAccountLastSyncedHours(elapsed.inHours);
  }
  return l10n.settingsAccountLastSyncedOn(
    DateFormat.MMMEd(localeName).format(lastPulledAt.toLocal()),
  );
}
