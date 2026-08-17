/// The single place that turns the app's current state into the digest's
/// whole scheduling horizon (spec `docs/specs/notifications.md`
/// architecture #2).
///
/// Deliberately a free function with no Riverpod dependency, because it has
/// two callers that cannot share a controller: `DigestRescheduleController`
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
List<DigestPlan?> buildDigestPlans({
  required DateTime now,
  required DeviceSettings settings,
  required List<OccurrenceWithChore> pending,
  required String? recipientMemberId,
}) {
  final occurrences = [
    for (final row in pending)
      ProjectedOccurrence(
        id: row.occurrence.id,
        dueDate: row.occurrence.dueDate,
        startDate: row.chore.startDate,
        recurrence: row.chore.recurrence,
        assignedMemberId: row.occurrence.assignedMemberId,
      ),
  ];
  final slots = digestSlots(now: now, digestMinutes: settings.digestMinutes);
  final plans = <DigestPlan?>[];
  for (final fireAt in slots) {
    final counts = projectDigestCounts(
      occurrences: occurrences,
      date: PlainDate.fromDateTime(fireAt),
      recipientMemberId: recipientMemberId,
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
