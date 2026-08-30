/// The single place that turns the app's current state into the app's whole
/// notification plan (spec `docs/specs/notifications.md` architecture #2 and
/// `docs/specs/notifications-n2.md` §9.1).
///
/// Deliberately free functions with no Riverpod dependency, because there
/// are callers that cannot share a controller: `DigestRescheduleController`
/// in `lib/app/providers.dart` (which owns the debounced reschedule wiring
/// and is only ever activated from `main.dart`) and
/// `DigestPrepromptBanner` in `lib/features/chores/` (a widget, which must
/// never read that controller). Before this existed, the banner carried a
/// hand-copied duplicate of the recompute logic.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/reminder_planner.dart';

/// Everything one planning pass decided: the digest's horizon, the armed
/// individual reminders and the evening re-reminder's horizon (spec
/// `docs/specs/notifications-n2.md` §9.1).
///
/// Produced by a SINGLE call to [buildNotificationPlans] and applied by a
/// SINGLE enqueued write (`NotificationScheduler.applyPlans`, D9): Rule D
/// couples the digest's counts to the reminders' arming, so two passes or
/// two writes open a window in which a chore is announced twice or not at
/// all.
class NotificationPlanSet {
  /// Creates a plan set.
  const NotificationPlanSet({
    required this.digest,
    required this.reminders,
    required this.evening,
    required this.reminderOverflowCount,
  });

  /// Exactly [digestHorizonSlots] entries; index `k` is digest slot `k`.
  final List<DigestPlan?> digest;

  /// Exactly [reminderCeiling] entries; index `i` is notification id
  /// `reminderNotificationIdBase + i`.
  ///
  /// Armed reminders are packed at the FRONT in fire-moment order and the
  /// tail is `null`, because ids are position-relative (spec
  /// `docs/specs/notifications-n2.md` §2.3) -- an id names neither a chore
  /// nor a date, so the position IS the contract.
  final List<ReminderPlan?> reminders;

  /// Exactly [eveningHorizonSlots] entries; index `k` is notification id
  /// `eveningNotificationIdBase + k`.
  final List<EveningPlan?> evening;

  /// How many reminder-eligible occurrences the ceiling turned away (spec
  /// `docs/specs/notifications-n2.md` §3.2).
  ///
  /// **Slice 4's Settings sub-line reads THIS**, and must never re-derive
  /// §2.3's arming rule at the UI layer: a second copy of that rule would
  /// drift from this one the moment either changed. Forwarded verbatim from
  /// [ReminderPlanResult.overflowCount] -- see there for why it counts only
  /// ceiling losses and why it cannot be derived from [reminders].
  final int reminderOverflowCount;
}

/// The whole notification plan for [now] (spec
/// `docs/specs/notifications-n2.md` §9.1).
///
/// Computes in the order **reminders -> evening -> digest**, and that order
/// is load-bearing: Rule D (§2.4) and §5's suppression both read the armed
/// set, so it must exist before either runs.
///
/// [snoozedUntilByOccurrenceId] is `occurrenceId -> UTC instant`, from
/// `ReminderSnoozeRepository.activeSnoozes`. It is a parameter rather than a
/// read because this function must stay free of any I/O -- the same reason
/// [pending] is passed in.
NotificationPlanSet buildNotificationPlans({
  required DateTime now,
  required DeviceSettings settings,
  required List<OccurrenceWithChore> pending,
  required String? recipientMemberId,
  Map<String, DateTime> snoozedUntilByOccurrenceId = const {},
}) {
  final occurrences = _projected(pending);

  // INVERSION (BLOCKING, Task 9 step 4 inversion 1): the pass reordered to
  // digest -> reminders -> evening, so Rule D reads an armed set that does
  // not exist yet. To be reverted.
  final digest = _digestPlans(
    now: now,
    settings: settings,
    occurrences: occurrences,
    recipientMemberId: recipientMemberId,
    armedReminderDates: const {},
  );

  // 1. Reminders first -- everything below reads the armed set.
  final reminderResult = planReminders(
    now: now,
    occurrences: occurrences,
    recipientMemberId: recipientMemberId,
    snoozedUntilByOccurrenceId: snoozedUntilByOccurrenceId,
    quietHoursEnabled: settings.quietHoursEnabled,
    quietStartMinutes: settings.quietStartMinutes,
    quietEndMinutes: settings.quietEndMinutes,
  );

  // 2. Evening, which is suppressed by a still-to-come reminder (§5).
  final evening = planEveningSlots(
    now: now,
    enabled: settings.eveningReminderEnabled,
    eveningMinutes: settings.eveningReminderMinutes,
    occurrences: occurrences,
    recipientMemberId: recipientMemberId,
    armedReminders: reminderResult.armed,
    quietHoursEnabled: settings.quietHoursEnabled,
    quietStartMinutes: settings.quietStartMinutes,
    quietEndMinutes: settings.quietEndMinutes,
  );

  // 3. Digest, minus whatever a reminder is about to announce (Rule D).
  //
  // Keyed on the reminder's FIRE date rather than the occurrence's due
  // date: a quiet-hours deferral moves the reminder onto the following
  // calendar date, and Rule D must follow the reminder or the two channels
  // desynchronise (§2.4).
  return NotificationPlanSet(
    digest: digest,
    reminders: List<ReminderPlan?>.unmodifiable([
      ...reminderResult.armed,
      for (var i = reminderResult.armed.length; i < reminderCeiling; i++) null,
    ]),
    evening: evening,
    reminderOverflowCount: reminderResult.overflowCount,
  );
}

/// The digest plan for each of the next [digestHorizonSlots] slots.
///
/// The returned list is ALWAYS exactly [digestHorizonSlots] long: index `k`
/// is slot `k` (0 = the next slot), and a `null` entry means that slot's
/// own date is silent and its notification id must be cancelled rather than
/// scheduled (see `NotificationScheduler.applyDigestPlans`). Slot `k` is
/// not necessarily `k` days out — see [digestSlots] for the segmented
/// shape.
///
/// [pending] is the household's current pending occurrences (i.e.
/// `pendingOccurrencesProvider`'s value). [recipientMemberId] is the
/// acting member's id, or `null` when it can't be resolved — see
/// [projectDigestCounts] for what each means.
///
/// **Rule D is deliberately NOT applied here** (`armedReminderDates` is
/// empty): this entry point exists for the two callers that must not
/// rewrite reminders -- `DigestPrepromptBanner._enable`, which is about to
/// trigger a full recompute anyway via its settings write, and
/// `rewriteDigestHorizon` in the background isolate, which
/// `docs/specs/notifications-n2.md` §10.1 explicitly limits to the digest.
/// Both therefore write a digest horizon that can be stale by one
/// occurrence until the next recompute, and §10.1 accepts that because the
/// staleness always errs toward REPORTING a chore, never toward hiding one.
/// New callers should use [buildNotificationPlans].
///
/// Quiet hours ARE applied here, unlike Rule D: §6 says in as many words
/// that they apply to the digest, and a horizon written by these two
/// callers at a moment the user has muted would fire at that moment.
List<DigestPlan?> buildDigestPlans({
  required DateTime now,
  required DeviceSettings settings,
  required List<OccurrenceWithChore> pending,
  required String? recipientMemberId,
}) => _digestPlans(
  now: now,
  settings: settings,
  occurrences: _projected(pending),
  recipientMemberId: recipientMemberId,
  armedReminderDates: const {},
);

/// Maps the data layer's [pending] rows onto the pure projection's input.
///
/// Extracted so [buildDigestPlans] and [buildNotificationPlans] share one
/// mapping: a second copy could attach a different chore title or drop
/// `reminderMinutes` on one path only.
List<ProjectedOccurrence> _projected(List<OccurrenceWithChore> pending) => [
  for (final row in pending)
    ProjectedOccurrence(
      id: row.occurrence.id,
      choreId: row.chore.id,
      choreTitle: row.chore.title,
      reminderMinutes: row.chore.reminderMinutes,
      dueDate: row.occurrence.dueDate,
      startDate: row.chore.startDate,
      recurrence: row.chore.recurrence,
      assignedMemberId: row.occurrence.assignedMemberId,
    ),
];

List<DigestPlan?> _digestPlans({
  required DateTime now,
  required DeviceSettings settings,
  required List<ProjectedOccurrence> occurrences,
  required String? recipientMemberId,
  required Map<String, PlainDate> armedReminderDates,
}) {
  final plans = <DigestPlan?>[];
  for (final rawFireAt in digestSlots(
    now: now,
    digestMinutes: settings.digestMinutes,
  )) {
    // Spec `docs/specs/notifications-n2.md` §6/D7: quiet hours DEFER the
    // digest, never drop it -- the evening re-reminder is the sole
    // exception and it is handled inside [planEveningSlots]. The counts are
    // then computed for the SHIFTED date, because the slot now speaks on
    // that date, and Rule D is keyed on the date each channel actually
    // fires on.
    //
    // Two slots can never collide into one date: slot k at 23:30 on day k
    // defers to 07:00 on day k+1, and slot k+1 defers to day k+2.
    //
    // Nothing ships changed by this: quiet hours default OFF, and the
    // shipped 08:00 digest sits outside the default 22:00-07:00 window
    // anyway (§6's closing paragraph).
    final fireAt = applyQuietHours(
      candidate: rawFireAt,
      enabled: settings.quietHoursEnabled,
      startMinutes: settings.quietStartMinutes,
      endMinutes: settings.quietEndMinutes,
    );
    final counts = projectDigestCounts(
      occurrences: occurrences,
      date: PlainDate.fromDateTime(fireAt),
      recipientMemberId: recipientMemberId,
      armedReminderDates: armedReminderDates,
    );
    plans.add(
      planDigestSlot(
        fireAt: fireAt,
        enabled: settings.digestEnabled,
        dueTodayCount: counts.dueCount,
        overdueCount: counts.overdueCount,
        // Per-slot, deliberately: each slot has its own counts and so its
        // own actionability (spec `docs/specs/notifications.md` N2). Slot 3
        // can carry a Done button while slot 4 does not.
        soleOccurrenceId: counts.soleOccurrenceId,
      ),
    );
  }
  return plans;
}
