/// Shared "how long ago" bands and the ticker that keeps a rendered
/// relative time true while its screen stays open.
///
/// Extracted from `last_synced_line.dart` (spec
/// `docs/specs/sync-freshness.md` §2.4) when the Shopping tab's status line
/// (persona finding F1/F10) needed the same arithmetic: whole minutes under
/// an hour, whole hours under a day, a fixed calendar date beyond that.
/// Each surface keeps its own wording; only the bands and the timer are
/// shared, so the two can never disagree about when a text changes.
library;

import 'dart:async';

import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Which wording band an elapsed time falls in.
enum RelativeTimeBand {
  /// Under a minute.
  justNow,

  /// One minute up to (not including) an hour; [RelativeTime.count] is the
  /// whole minutes elapsed.
  minutes,

  /// One hour up to (not including) a day; [RelativeTime.count] is the whole
  /// hours elapsed.
  hours,

  /// A day or more: a fixed date that no passage of time can alter.
  date,
}

/// An elapsed time classified into a [RelativeTimeBand].
class RelativeTime {
  /// Creates a classified elapsed time.
  const RelativeTime(this.band, this.count);

  /// The wording band.
  final RelativeTimeBand band;

  /// Whole minutes ([RelativeTimeBand.minutes]) or hours
  /// ([RelativeTimeBand.hours]) elapsed; `0` for the other bands.
  final int count;
}

/// Classifies the time from [then] to [now].
///
/// A [then] in the future (clock skew between devices) is "just now" rather
/// than negative minutes.
RelativeTime relativeTimeSince({
  required DateTime now,
  required DateTime then,
}) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) {
    return const RelativeTime(RelativeTimeBand.justNow, 0);
  }
  if (elapsed.inHours < 1) {
    return RelativeTime(RelativeTimeBand.minutes, elapsed.inMinutes);
  }
  if (elapsed.inHours < 24) {
    return RelativeTime(RelativeTimeBand.hours, elapsed.inHours);
  }
  return const RelativeTime(RelativeTimeBand.date, 0);
}

/// The moment [relativeTimeSince] next returns something different, or
/// `null` once it never will.
///
/// Whole minutes while under an hour (so the next change is at the next
/// whole minute since [then] -- which also covers the 'just now' band,
/// whose end is the first whole minute), whole hours while under a day, and
/// beyond a day a fixed date formatted from [then] alone.
DateTime? nextRelativeTimeChange({
  required DateTime now,
  required DateTime then,
}) {
  final elapsed = now.difference(then);
  if (elapsed.inHours < 1) {
    return then.add(Duration(minutes: elapsed.inMinutes + 1));
  }
  if (elapsed.inHours < 24) {
    return then.add(Duration(hours: elapsed.inHours + 1));
  }
  return null;
}

/// A short relative phrase for [then] as seen at [now] -- "just now",
/// "5 min ago", "2 hours ago", "on Fri, Jul 31" -- to be embedded in a
/// larger sentence (the Shopping status line's "synced {relative}").
///
/// The date band uses `package:intl`'s `MMMEd` for [localeName], never a
/// hardcoded weekday or month name.
String relativeTimePhrase(
  AppLocalizations l10n,
  String localeName, {
  required DateTime now,
  required DateTime then,
}) {
  final relative = relativeTimeSince(now: now, then: then);
  return switch (relative.band) {
    RelativeTimeBand.justNow => l10n.relativeTimeJustNow,
    RelativeTimeBand.minutes => l10n.relativeTimeMinutesAgo(relative.count),
    RelativeTimeBand.hours => l10n.relativeTimeHoursAgo(relative.count),
    RelativeTimeBand.date => l10n.relativeTimeOn(
      DateFormat.MMMEd(localeName).format(then.toLocal()),
    ),
  };
}

/// How long to wait before re-checking when the next change is apparently
/// already behind us (see [RelativeTimeTicker.tickAt]).
const _skewRecheck = Duration(minutes: 1);

/// Owns the one-shot [Timer] that re-renders a relative-time text exactly
/// when [nextRelativeTimeChange] says it goes stale.
///
/// **Boundary-aligned and band-derived, never a fixed interval** (backlog
/// A-2b): in the hours band it wakes once an hour rather than 60 times, and
/// past 24 hours no timer is armed at all.
///
/// Cancelled in [dispose], which is what keeps it out of `flutter_test`'s
/// "a Timer is still pending" check: that check runs *after* the binding
/// unmounts the tree, so a timer released on disposal is not a leak.
mixin RelativeTimeTicker<T extends StatefulWidget> on State<T> {
  /// Re-arming one-shot rather than a [Timer.periodic]: the gap to the next
  /// visible change is not constant.
  Timer? _timer;

  /// The moment [_timer] is currently scheduled for.
  ///
  /// Kept so an unrelated rebuild (a theme or locale change, a settings
  /// write) re-derives the same deadline and leaves the running timer
  /// alone. Cancelling and rescheduling on every build would let a subtree
  /// that rebuilds every 59 seconds postpone the tick indefinitely.
  DateTime? _deadline;

  /// Schedules the next tick for [deadline], or stops ticking when the text
  /// has reached its final form ([deadline] `null`).
  ///
  /// A deadline already in the past is reachable without any bug: clock skew
  /// between devices can hand us a timestamp in the future. Falling back to
  /// [_skewRecheck] rather than scheduling a non-positive delay matters -- a
  /// `Timer` with a zero or negative duration fires in the same frame,
  /// which with the `setState` below would spin.
  void tickAt(DateTime? deadline, {required DateTime now}) {
    if (deadline == null) {
      stopTicking();
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

  /// Cancels any pending tick.
  void stopTicking() {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
