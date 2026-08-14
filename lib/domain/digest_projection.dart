// `DigestCounts` has only final fields and no mutating members, so it is
// effectively immutable; we deliberately don't import `package:meta` (lib
// code is dart:core only) to add the `@immutable` annotation the lint below
// wants (same convention as `digest_planner.dart` and `plain_date.dart`).
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// Projects what the daily digest would have to say on a *future* calendar
/// date, assuming nothing happens in between (spec
/// `docs/specs/notifications.md` architecture #1).
///
/// This exists because the digest is scheduled a whole horizon ahead
/// (`digestHorizonSlots` in `lib/domain/digest_planner.dart`) and each of
/// those slots needs its own counts *and* its own silence decision — the
/// slots are not all consecutive days, so no slot's answer can be reused
/// for another's. The
/// assumption "nothing happens in between" is exactly right for the case
/// that matters: the app is not being opened, so nothing is completed,
/// skipped, or created, and `ChoreService.catchUpOverdue` never runs.
///
/// The one thing that DOES change without the app running is which slot a
/// schedule-anchored recurring chore is sitting on — because that is what
/// catch-up will do the moment the user opens the app on that day. So this
/// module mirrors catch-up's rule via
/// [latestScheduledOnOrBefore], rather than replaying the raw recurrence
/// series (which would count one chore several times over, since a chore
/// only ever has ONE pending occurrence).
///
/// Pure, same standard as `lib/domain/recurrence/`: no clock, no I/O, no
/// Flutter, no drift.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/recurrence/recurrence_engine.dart';

/// One pending occurrence, reduced to just the fields the projection needs.
///
/// The application layer maps a `OccurrenceWithChore` onto this (see
/// `lib/application/digest_plan_builder.dart`), which is what keeps this
/// module free of any data-layer import.
class ProjectedOccurrence {
  /// Creates a projection input.
  const ProjectedOccurrence({
    required this.dueDate,
    required this.startDate,
    required this.recurrence,
    required this.assignedMemberId,
  });

  /// The occurrence's current due date.
  final PlainDate dueDate;

  /// The owning chore's start date (the recurrence series' anchor).
  final PlainDate startDate;

  /// The owning chore's recurrence rule, or `null` for a one-off.
  final Recurrence? recurrence;

  /// The member this occurrence is assigned to, or `null` for "anyone".
  final String? assignedMemberId;
}

/// The due/overdue split for a single digest slot's calendar date.
class DigestCounts {
  /// Creates a counts pair.
  const DigestCounts({required this.dueCount, required this.overdueCount});

  /// Occurrences whose projected due date is exactly the queried date.
  final int dueCount;

  /// Occurrences whose projected due date is strictly before the queried
  /// date.
  final int overdueCount;

  /// Whether there is nothing at all to say — the spec's "silence is a
  /// feature" condition, evaluated per day.
  bool get isSilent => dueCount == 0 && overdueCount == 0;

  @override
  bool operator ==(Object other) =>
      other is DigestCounts &&
      other.dueCount == dueCount &&
      other.overdueCount == overdueCount;

  @override
  int get hashCode => Object.hash(dueCount, overdueCount);

  @override
  String toString() =>
      'DigestCounts(dueCount: $dueCount, overdueCount: $overdueCount)';
}

/// The due date [occurrence] would carry on [date], if the app is never
/// opened between now and then.
///
/// A one-off or completion-anchored occurrence simply stays where it is —
/// it goes further overdue, it does not move. A schedule-anchored recurring
/// occurrence rolls forward to the newest series slot on or before [date],
/// which is precisely what `ChoreService.catchUpOverdue` would do on that
/// day; if no slot has come due yet, it stays put.
PlainDate projectedDueDateOn(ProjectedOccurrence occurrence, PlainDate date) {
  final rule = occurrence.recurrence;
  if (rule == null || rule.anchor != RecurrenceAnchor.schedule) {
    return occurrence.dueDate;
  }
  return latestScheduledOnOrBefore(
        rule: rule,
        startDate: occurrence.startDate,
        afterDueDate: occurrence.dueDate,
        notAfter: date,
      ) ??
      occurrence.dueDate;
}

/// The digest counts for [date], over [occurrences], as seen by
/// [recipientMemberId].
///
/// Scoping (spec `docs/specs/notifications.md` N1, triage T2.3): an
/// occurrence counts when it is unassigned ("anyone" — genuinely everyone's
/// business) or assigned to [recipientMemberId]. A `null`
/// [recipientMemberId] means the acting member could not be resolved, in
/// which case everything counts: a digest that hides work because identity
/// is momentarily unknown would be worse than one that shows too much.
///
/// Scoping is applied BEFORE projection, so a partner's chore never
/// influences this recipient's counts no matter how it rolls forward.
DigestCounts projectDigestCounts({
  required Iterable<ProjectedOccurrence> occurrences,
  required PlainDate date,
  required String? recipientMemberId,
}) {
  var dueCount = 0;
  var overdueCount = 0;
  for (final occurrence in occurrences) {
    final assignee = occurrence.assignedMemberId;
    if (recipientMemberId != null &&
        assignee != null &&
        assignee != recipientMemberId) {
      continue;
    }
    final projected = projectedDueDateOn(occurrence, date);
    if (projected == date) {
      dueCount++;
    } else if (projected.isBefore(date)) {
      overdueCount++;
    }
  }
  return DigestCounts(dueCount: dueCount, overdueCount: overdueCount);
}
