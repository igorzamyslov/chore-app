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
    required this.id,
    required this.choreId,
    required this.choreTitle,
    required this.dueDate,
    required this.startDate,
    required this.recurrence,
    required this.assignedMemberId,
    this.reminderMinutes,
  });

  /// The occurrence row's id.
  ///
  /// Carried so [projectDigestCounts] can report [DigestCounts
  /// .soleOccurrenceId] — the notification-action payload's `occ` (spec
  /// `docs/specs/notifications.md` N2). **Required, not optional:** an
  /// optional id would let a future caller silently produce a
  /// never-actionable digest by forgetting it, and there are only three
  /// construction sites in the tree.
  final String id;

  /// The owning chore's id.
  ///
  /// **Required, not optional**, for the reason [id]'s own doc comment
  /// gives: D4's ceiling tiebreak in `lib/domain/reminder_planner.dart` is
  /// "lowest CHORE id", and an optional field would let a future
  /// construction site silently fall back to a different, unstable
  /// ordering. Distinct from [id], which is the OCCURRENCE's -- an
  /// occurrence id changes every time the chore regenerates, so it is the
  /// wrong thing to break a tie with.
  final String choreId;

  /// The owning chore's title, carried verbatim.
  ///
  /// A per-chore reminder's TITLE is the chore title, unlocalized user data
  /// -- that is what makes it actionable and it is the whole of AC1 (spec
  /// `docs/specs/notifications-n2.md` §11). Carried here rather than joined
  /// on later so the pure planner produces a complete `ReminderPlan` and no
  /// application-layer step can attach the wrong title to a
  /// position-relative id.
  final String choreTitle;

  /// The owning chore's `reminder_minutes`, or `null` for "no individual
  /// reminder" (spec `docs/specs/notifications-n2.md` D1).
  ///
  /// Optional (defaulting to `null`) unlike [choreId]/[choreTitle], because
  /// `null` is a meaningful, common and safe value here -- it is what every
  /// chore has until someone turns the switch on -- whereas a defaulted
  /// chore id would be a silently wrong ordering key.
  final int? reminderMinutes;

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
  const DigestCounts({
    required this.dueCount,
    required this.overdueCount,
    this.soleOccurrenceId,
  });

  /// Occurrences whose projected due date is exactly the queried date.
  final int dueCount;

  /// Occurrences whose projected due date is strictly before the queried
  /// date.
  final int overdueCount;

  /// The [ProjectedOccurrence.id] of the single occurrence this slot counted,
  /// or `null` when it counted anything other than exactly one.
  ///
  /// Non-null exactly when `dueCount + overdueCount == 1`, which is the only
  /// case where a notification ACTION can name an unambiguous chore (spec
  /// `docs/specs/notifications.md` N2). Deciding it HERE, rather than in the
  /// planner or the plan builder, is what guarantees it obeys precisely the
  /// same recipient scoping and the same projected-due-date comparison as
  /// the counts beside it: any other home would be a second copy of both
  /// rules, and a scoping copy that drifted would make the "Done" button
  /// vanish in every two-person household.
  final String? soleOccurrenceId;

  /// Whether there is nothing at all to say — the spec's "silence is a
  /// feature" condition, evaluated per day.
  bool get isSilent => dueCount == 0 && overdueCount == 0;

  @override
  bool operator ==(Object other) =>
      other is DigestCounts &&
      other.dueCount == dueCount &&
      other.overdueCount == overdueCount &&
      other.soleOccurrenceId == soleOccurrenceId;

  @override
  int get hashCode => Object.hash(dueCount, overdueCount, soleOccurrenceId);

  @override
  String toString() =>
      'DigestCounts(dueCount: $dueCount, overdueCount: $overdueCount, '
      'soleOccurrenceId: $soleOccurrenceId)';
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
///
/// Also reports [DigestCounts.soleOccurrenceId] when exactly one occurrence
/// was counted — see that field for why this is its only correct home.
///
/// [armedReminderDates] is `occurrence id -> the calendar date an
/// individual reminder is armed to fire on`, as produced by `planReminders`
/// (`lib/domain/reminder_planner.dart`). Rule D (spec
/// `docs/specs/notifications-n2.md` §2.4, D2) omits an occurrence from this
/// slot entirely when its entry equals [date]: being told twice on one day
/// is precisely the annoyance a per-chore reminder exists to cure. An empty
/// map — the default — means "no reminders", which is what every pre-N2
/// caller means and why they all keep compiling unchanged.
///
/// The caller must pass the map produced by the SAME planning pass whose
/// reminders it will arm. §0.1's partition is a property of one pass's
/// answers, not of two: a map from an earlier pass can omit an occurrence
/// no reminder will actually announce.
DigestCounts projectDigestCounts({
  required Iterable<ProjectedOccurrence> occurrences,
  required PlainDate date,
  required String? recipientMemberId,
  Map<String, PlainDate> armedReminderDates = const {},
}) {
  var dueCount = 0;
  var overdueCount = 0;
  String? lastCountedId;
  for (final occurrence in occurrences) {
    final assignee = occurrence.assignedMemberId;
    if (recipientMemberId != null &&
        assignee != null &&
        assignee != recipientMemberId) {
      continue;
    }
    // Rule D (spec `docs/specs/notifications-n2.md` §2.4, D2): this slot
    // omits an occurrence iff an individual reminder for it is armed to
    // fire on THIS slot's own calendar date.
    //
    // Keyed on the ARMED date, not the due date, so a quiet-hours deferral
    // cannot desynchronise the two channels -- and applied BEFORE the
    // bucketing below for the same reason: a deferral can move the reminder
    // onto a date the occurrence is already OVERDUE on, and the rule must
    // follow the reminder rather than the due date. That is why §2.4 states
    // the general form rather than only the due-bucket case.
    // INVERSION (Task 7 step 4 inversion 2): the skip moved AFTER the
    // projection and applied only in the due branch, i.e. keyed on the due
    // date rather than the armed date. To be reverted.
    final projected = projectedDueDateOn(occurrence, date);
    if (projected == date) {
      if (armedReminderDates[occurrence.id] == date) {
        continue;
      }
      dueCount++;
      lastCountedId = occurrence.id;
    } else if (projected.isBefore(date)) {
      overdueCount++;
      lastCountedId = occurrence.id;
    }
  }
  // Remembering the last counted id and discarding it unless the total is
  // exactly 1 needs no separate match counter: the total IS the counter, and
  // checking it after the loop makes the invariant hold regardless of
  // iteration order. An occurrence due strictly after [date] is counted by
  // neither branch, so it can never become the sole id either.
  return DigestCounts(
    dueCount: dueCount,
    overdueCount: overdueCount,
    soleOccurrenceId: dueCount + overdueCount == 1 ? lastCountedId : null,
  );
}
