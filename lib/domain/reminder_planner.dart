/// Pure scheduling logic for per-chore reminders, the evening re-reminder
/// and quiet hours (spec `docs/specs/notifications-n2.md` §2, §5, §6).
///
/// Same purity standard as `digest_planner.dart` and `digest_projection.dart`
/// -- no clock, no I/O, no Flutter, no drift. It imports those two rather
/// than `dart:core` alone, deliberately: §2.3 step 1 requires the reminder's
/// roll-forward to be **the same** `latestScheduledOnOrBefore` path the
/// digest projection already uses, and §5's horizon is the same "today if
/// still ahead of now, else tomorrow" rule `nextDigestSlot` implements. A
/// second copy of either would be exactly the drift §0.1's partition exists
/// to prevent.
library;

import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';

/// The number of iOS pending-notification ids `docs/specs/notifications.md`
/// reserves for N2 (spec `docs/specs/notifications-n2.md` §3).
///
/// iOS caps an app at 64 pending notifications; the digest owns 24 of them
/// and this is the rest. **The total is now exactly 64 and there is no
/// slack left** -- anything new must take ids from one of the three ranges
/// by amending §3.1's table.
const int n2NotificationIdBudget = 40;

/// How many consecutive daily evening re-reminder slots are armed at once
/// (spec `docs/specs/notifications-n2.md` §3.1).
///
/// Seven, not fourteen: the evening re-reminder is the "you are around
/// today and busy" instrument, and someone who has not opened the app in a
/// week is not busy-today, they are away -- which is what the digest's own
/// 83-day horizon is for.
const int eveningHorizonSlots = 7;

/// The most individual reminders that can be armed at once (spec
/// `docs/specs/notifications-n2.md` §3.1).
///
/// **Derived, never written as `33`**, for the same reason
/// `digestNotificationIds` is derived from `digestHorizonSlots`: the split
/// between reminders and the evening horizon must move as one number when
/// it moves at all.
const int reminderCeiling = n2NotificationIdBudget - eveningHorizonSlots;

/// The lowest notification id per-chore reminders own; reminder `i` in the
/// sorted armed list uses `reminderNotificationIdBase + i` (spec
/// `docs/specs/notifications-n2.md` §2.3).
///
/// **Ids are position-relative, exactly like the digest's**, so an id names
/// neither a chore nor a date and the payload is the only channel that can
/// address anything.
///
/// Deliberately far from [eveningNotificationIdBase] and from
/// `digestNotificationIdBase` (1001 / 2001 / 3001 rather than adjacent), so
/// an off-by-one inside one range cannot silently land in another's.
const int reminderNotificationIdBase = 2001;

/// The lowest notification id the evening re-reminder horizon owns; slot
/// `k` uses `eveningNotificationIdBase + k` (spec
/// `docs/specs/notifications-n2.md` §3.1). See [reminderNotificationIdBase]
/// for why the bases are spaced out.
const int eveningNotificationIdBase = 3001;

/// How far ahead an individual reminder may be armed, in days (spec
/// `docs/specs/notifications-n2.md` D3).
///
/// The digest is the long-range instrument (83 days); individual reminders
/// are the same-fortnight instrument. Arming several occurrences per chore
/// would multiply the id cost for coverage the digest already provides.
const int reminderArmWindowDays = 14;

/// The time a freshly-enabled chore reminder is pre-filled with, as minutes
/// since local midnight (18:00) -- spec `docs/specs/notifications-n2.md`
/// §2.1.
///
/// A **constant, not a settings column**: a default is not state, and a
/// stored one would have to pick a device scope for a value that is only
/// ever a starting point in a picker. 18:00 is the hour "bins out on
/// Tuesday evening" names, and far enough from the 08:00 digest default
/// that the two never read as one event.
const int defaultReminderMinutes = 1080;

/// [candidate] itself when quiet hours are off or [candidate] falls outside
/// the window; otherwise the first instant at or after [candidate] whose
/// minute-of-day equals [endMinutes] (spec `docs/specs/notifications-n2.md`
/// §6).
///
/// **Deferred, never dropped**, for the digest and for individual reminders
/// (D7): dropping discards something the user asked for, while deferring
/// converts a 23:30 ping nobody can act on into an 07:00 one they can. The
/// evening re-reminder is the one exception and it is handled by its own
/// caller ([planEveningSlots]), which drops a slot this function would have
/// moved -- an "evening" re-reminder delivered at 07:00 has a false premise
/// and would collide with the 08:00 digest.
///
/// The window WRAPS midnight in the normal case and is evaluated as a
/// wrapping interval, never as a numeric range. `startMinutes ==
/// endMinutes` is treated as OFF, not as a 24-hour window: the latter would
/// mean "never notify", which is what [enabled] is for. A candidate exactly
/// at [startMinutes] is INSIDE; one exactly at [endMinutes] is OUTSIDE.
///
/// The result is built from calendar components rather than
/// `add(Duration(hours:))` for the DST reason `nextDigestSlot` documents:
/// the deferral target is a WALL-CLOCK time, and adding a fixed duration
/// across a daylight-saving transition would land an hour out. It is
/// therefore always at or after [candidate] -- a property §2.3 step 5
/// relies on, since a shift that went backwards would silently delete
/// reminders by making them look past.
///
/// [startMinutes] and [endMinutes] must be in `0..1439`; throws
/// [ArgumentError] otherwise.
DateTime applyQuietHours({
  required DateTime candidate,
  required bool enabled,
  required int startMinutes,
  required int endMinutes,
}) {
  _validateMinuteOfDay(startMinutes, 'startMinutes');
  _validateMinuteOfDay(endMinutes, 'endMinutes');
  if (!enabled || startMinutes == endMinutes) {
    return candidate;
  }
  final minuteOfDay = candidate.hour * 60 + candidate.minute;
  final inside = startMinutes < endMinutes
      // A non-wrapping window: [start, end).
      // INVERSION (Task 5 step 4 inversions 1 and 2): both boundaries
      // flipped -- `> start` excludes a candidate exactly at the start,
      // `<= end` includes one exactly at the end. To be reverted.
      ? minuteOfDay > startMinutes && minuteOfDay <= endMinutes
      // A wrapping window: [start, midnight) union [midnight, end).
      : minuteOfDay > startMinutes || minuteOfDay <= endMinutes;
  if (!inside) {
    return candidate;
  }
  final hour = endMinutes ~/ 60;
  final minute = endMinutes % 60;
  // Same day when the end is still ahead of us in the day (the early side
  // of a wrapping window, or any non-wrapping window); tomorrow when it is
  // not (the late side of a wrapping window). `DateTime`'s constructor
  // normalizes an out-of-range day into the next month/year for us.
  final sameDay = minuteOfDay < endMinutes;
  return DateTime(
    candidate.year,
    candidate.month,
    candidate.day + (sameDay ? 0 : 1),
    hour,
    minute,
  );
}

void _validateMinuteOfDay(int value, String name) {
  if (value < 0 || value > 1439) {
    throw ArgumentError.value(
      value,
      name,
      'Must be in 0..1439 (minutes since local midnight)',
    );
  }
}

/// One armed individual reminder (spec `docs/specs/notifications-n2.md`
/// §2.3).
///
/// Carries no notification id: **ids are position-relative** -- reminder `i`
/// in [ReminderPlanResult.armed] uses `reminderNotificationIdBase + i` -- so
/// an id names neither a chore nor a date, and the payload is the only
/// channel that can address anything.
class ReminderPlan {
  /// Creates a plan.
  const ReminderPlan({
    required this.fireAt,
    required this.occurrenceId,
    required this.choreId,
    required this.choreTitle,
    required this.dueDate,
  });

  /// The device-local moment this reminder should fire, after the snooze
  /// override and the quiet-hours shift.
  final DateTime fireAt;

  /// The occurrence this reminder is about -- the action payload's `occ`.
  final String occurrenceId;

  /// The owning chore's id; the D4 ceiling tiebreak.
  final String choreId;

  /// The owning chore's title, which is the notification's TITLE verbatim.
  final String choreTitle;

  /// The occurrence's projected due date.
  ///
  /// Carried so the scheduler can pick between "Due today" and "Still open"
  /// (spec `docs/specs/notifications-n2.md` §11) by comparing it with
  /// [fireAt]'s calendar date, rather than doing date arithmetic inside a
  /// localized string. A snooze or a quiet-hours deferral is exactly the
  /// case where the two differ -- and the due date is unchanged by either
  /// (D5).
  final PlainDate dueDate;
}

/// What one planning pass decided about individual reminders.
class ReminderPlanResult {
  /// Creates a result.
  ///
  /// Built at exactly one place -- see [planReminders] -- so [armed] and
  /// [overflowCount] cannot disagree.
  const ReminderPlanResult({required this.armed, required this.overflowCount});

  /// The reminders to arm, in fire-moment order, at most [reminderCeiling]
  /// of them.
  final List<ReminderPlan> armed;

  /// How many reminder-eligible occurrences the CEILING turned away (spec
  /// `docs/specs/notifications-n2.md` §3.2).
  ///
  /// **Not derivable from [armed]**: at the ceiling [armed] has exactly
  /// [reminderCeiling] entries whether one chore overflowed or ninety did,
  /// so the number has to be carried. It is produced at the same truncation
  /// site that produces [armed], which is what makes
  /// `armed.length + overflowCount` the eligible count by construction.
  ///
  /// **Counts only ceiling losses.** An occurrence excluded by the 14-day
  /// window (D3), by the already-overdue rule (D8), by recipient scoping
  /// (§2.2), or by having no `reminder_minutes` at all never competed for a
  /// slot and is NOT counted here. Slice 4's Settings sub-line says "N
  /// chores stayed in the daily summary because this device can hold
  /// [reminderCeiling] reminders at once", and that sentence is only true
  /// of ceiling losses.
  ///
  /// The losers are **not silent**: Rule D omits only ARMED occurrences, so
  /// an occurrence that lost the ordering is counted by its date's digest
  /// slot exactly as it is today. The ceiling degrades one chore from
  /// "individually reminded" to "in the daily summary" -- never into
  /// silence.
  final int overflowCount;
}

/// Plans every individual reminder for [now], over [occurrences], as seen by
/// [recipientMemberId] (spec `docs/specs/notifications-n2.md` §2.3).
///
/// Applies, in order: eligibility ([ProjectedOccurrence.reminderMinutes] is
/// non-null), the same recipient scoping [projectDigestCounts] uses (§2.2),
/// the roll-forward via [projectedDueDateOn] (§2.3 step 1 -- deliberately
/// the same function, not a copy), the arm moment built from calendar
/// components (step 2), the snooze override for a moment still in the
/// future (step 3), the quiet-hours shift (step 4 -- **the only place** it
/// is applied to a reminder, snoozed or not), and the two drops of step 5.
/// Survivors are sorted by [ReminderPlan.fireAt] ascending, tie-broken by
/// [ReminderPlan.choreId] ascending, and the first [reminderCeiling] are
/// armed.
///
/// [snoozedUntilByOccurrenceId] holds UTC instants (as stored by
/// `ReminderSnoozeRepository`); they are converted to local before any
/// comparison, because every other moment here is device-local.
ReminderPlanResult planReminders({
  required DateTime now,
  required Iterable<ProjectedOccurrence> occurrences,
  required String? recipientMemberId,
  required Map<String, DateTime> snoozedUntilByOccurrenceId,
  required bool quietHoursEnabled,
  required int quietStartMinutes,
  required int quietEndMinutes,
}) {
  final today = PlainDate.fromDateTime(now);
  final windowEnd = today.addDays(reminderArmWindowDays);
  final eligible = <ReminderPlan>[];
  for (final occurrence in occurrences) {
    final reminderMinutes = occurrence.reminderMinutes;
    if (reminderMinutes == null) {
      continue;
    }
    final assignee = occurrence.assignedMemberId;
    if (recipientMemberId != null &&
        assignee != null &&
        assignee != recipientMemberId) {
      continue;
    }
    // INVERSION (Task 6 step 5 inversion 1): the occurrence's own due date
    // instead of the projected roll-forward. To be reverted.
    final armDate = occurrence.dueDate;
    // Calendar components, never `add(Duration(days:))` -- the same DST
    // reason `nextDigestSlot` documents.
    var armAt = DateTime(
      armDate.year,
      armDate.month,
      armDate.day,
      reminderMinutes ~/ 60,
      reminderMinutes % 60,
    );
    // INVERSION (Task 6 step 5 inversion 4): the shift applied BEFORE the
    // snooze override, so a snoozed moment never goes through it. To be
    // reverted.
    armAt = applyQuietHours(
      candidate: armAt,
      enabled: quietHoursEnabled,
      startMinutes: quietStartMinutes,
      endMinutes: quietEndMinutes,
    );
    final snoozedUntil = snoozedUntilByOccurrenceId[occurrence.id]?.toLocal();
    if (snoozedUntil != null && snoozedUntil.isAfter(now)) {
      armAt = snoozedUntil;
    }
    if (!armAt.isAfter(now)) {
      continue; // Already past: overdue is the digest's job (D8).
    }
    if (PlainDate.fromDateTime(armAt).isAfter(windowEnd)) {
      continue; // Beyond the fortnight the digest already covers (D3).
    }
    eligible.add(
      ReminderPlan(
        fireAt: armAt,
        occurrenceId: occurrence.id,
        choreId: occurrence.choreId,
        choreTitle: occurrence.choreTitle,
        dueDate: armDate,
      ),
    );
  }
  eligible.sort((a, b) {
    final byMoment = a.fireAt.compareTo(b.fireAt);
    // INVERSION (Task 6 step 5 inversion 2): tie-broken by OCCURRENCE id.
    // To be reverted.
    return byMoment != 0 ? byMoment : a.occurrenceId.compareTo(b.occurrenceId);
  });
  // The ONE truncation site: `armed` and `overflowCount` are produced from
  // the same list in the same expression, so they cannot disagree.
  final armed = eligible.length <= reminderCeiling
      ? eligible
      : eligible.sublist(0, reminderCeiling);
  return ReminderPlanResult(
    armed: List<ReminderPlan>.unmodifiable(armed),
    overflowCount: eligible.length - armed.length,
  );
}

/// One evening re-reminder slot (spec `docs/specs/notifications-n2.md` §5).
class EveningPlan {
  /// Creates a plan.
  const EveningPlan({
    required this.fireAt,
    required this.openCount,
    this.soleOccurrenceId,
  });

  /// The device-local moment this slot should fire.
  final DateTime fireAt;

  /// How many in-scope occurrences are still open on this slot's own date.
  ///
  /// `>= 1` by construction -- a slot counting nothing is `null`, not a
  /// plan with a zero -- which is why §11's ICU plural needs no `zero{}`
  /// branch.
  final int openCount;

  /// The single occurrence this slot is about, or `null` when it is about
  /// more than one -- the same gate the digest uses for its Done action.
  /// Computed now and unused until slice 7 (notification actions).
  final String? soleOccurrenceId;
}

/// The evening re-reminder's whole horizon: exactly [eveningHorizonSlots]
/// consecutive daily slots at [eveningMinutes], the first chosen by the same
/// "today if still ahead of now, else tomorrow" rule `nextDigestSlot` uses
/// (spec `docs/specs/notifications-n2.md` §5).
///
/// A `null` entry means that slot must be cancelled rather than scheduled.
///
/// A slot at moment `M` on date `D` fires iff at least one in-scope
/// occurrence's projected due date is `D` **and** that occurrence is not
/// about to be individually reminded -- precisely, and not "has an armed
/// reminder on `D`" alone: an occurrence is discounted iff it has an armed
/// reminder on `D` with `fireAt >= M`. A reminder that already fired earlier
/// that evening does not suppress the summary; one still to come does,
/// because it would arrive minutes later and say the same thing better.
///
/// **Overdue occurrences never count** (D6). That is the whole anti-nag
/// design, and it is a property rather than a rule: it is impossible to
/// receive this two evenings running about the same occurrence, because by
/// the second evening that occurrence is overdue, not due-today.
///
/// **Quiet hours DROP a slot rather than deferring it** (D7), which is the
/// one place this differs from every other candidate: an "evening"
/// re-reminder delivered at 07:00 has a false premise -- "there is still
/// time today" -- and would collide with the 08:00 digest.
List<EveningPlan?> planEveningSlots({
  required DateTime now,
  required bool enabled,
  required int eveningMinutes,
  required Iterable<ProjectedOccurrence> occurrences,
  required String? recipientMemberId,
  required List<ReminderPlan> armedReminders,
  required bool quietHoursEnabled,
  required int quietStartMinutes,
  required int quietEndMinutes,
}) {
  final moments = digestSlots(
    now: now,
    digestMinutes: eveningMinutes,
    dailyDays: eveningHorizonSlots,
    weeklySlots: 0,
  );
  if (!enabled) {
    return List<EveningPlan?>.unmodifiable(
      List<EveningPlan?>.filled(moments.length, null),
    );
  }
  final plans = <EveningPlan?>[];
  for (final moment in moments) {
    // Dropped, never deferred (D7): if the shift would move it, it does
    // not fire at all.
    final shifted = applyQuietHours(
      candidate: moment,
      enabled: quietHoursEnabled,
      startMinutes: quietStartMinutes,
      endMinutes: quietEndMinutes,
    );
    if (shifted != moment) {
      plans.add(null);
      continue;
    }
    final date = PlainDate.fromDateTime(moment);
    var openCount = 0;
    String? lastCountedId;
    for (final occurrence in occurrences) {
      final assignee = occurrence.assignedMemberId;
      if (recipientMemberId != null &&
          assignee != null &&
          assignee != recipientMemberId) {
        continue;
      }
      // Due on THIS date. Overdue never counts (D6).
      if (projectedDueDateOn(occurrence, date) != date) {
        continue;
      }
      final stillToCome = armedReminders.any(
        (reminder) =>
            reminder.occurrenceId == occurrence.id &&
            PlainDate.fromDateTime(reminder.fireAt) == date &&
            !reminder.fireAt.isBefore(moment),
      );
      if (stillToCome) {
        continue;
      }
      openCount++;
      lastCountedId = occurrence.id;
    }
    plans.add(
      openCount == 0
          ? null
          : EveningPlan(
              fireAt: moment,
              openCount: openCount,
              soleOccurrenceId: openCount == 1 ? lastCountedId : null,
            ),
    );
  }
  return List<EveningPlan?>.unmodifiable(plans);
}
