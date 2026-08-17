/// The testable core of the digest notification's "Done" action (spec
/// `docs/specs/notifications.md` N2, backlog F-1): everything with a decision
/// in it, kept out of the untestable isolate glue in
/// `lib/application/notification_action_handler.dart`.
///
/// Free functions rather than a class: none of this holds state, and the
/// background isolate that calls it holds nothing either.
library;

import 'dart:ui' as ui;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/application/digest_plan_builder.dart';
import 'package:clock/clock.dart';

/// Completes the occurrence named by a digest action payload, if it is still
/// pending.
///
/// **The definition, restated because it is easy to "improve" wrongly:**
/// complete the specific occurrence ROW [occurrenceId] names, if it is still
/// pending; otherwise do nothing at all. NOT "complete whatever is due on the
/// date this notification described" — that is what makes the answer
/// independent of which horizon slot fired and of how long the notification
/// sat unread in the shade, which matters because slots reach ~83 days out.
///
/// Three cases fall out of it, and all three are correct:
/// - still pending → completed and attributed;
/// - already closed (another device, the user in-app, or a duplicate tap on a
///   stale shade entry) → silent no-op. There is no UI to report to, and
///   "someone already handled it" is a success, not a failure;
/// - replaced by `catchUpOverdue` after an app open → the payload's id is
///   stale, so also a silent no-op.
///
/// [actingMemberId] is passed straight through to
/// [ChoreService.completeOccurrence], `null` included. An unattributed
/// completion is the honest answer when identity is unknown; guessing at a
/// member is the misattribution backlog A-5 closed, and the background isolate
/// could not resolve it correctly anyway without a live Supabase session it
/// must not have.
///
/// Deliberately does NOT run `catchUpOverdue` first (decision D4). For a
/// schedule-anchored overdue occurrence that means recording `done` where
/// in-app catch-up would have recorded `missed`. Accepted: the user is
/// asserting they did the chore, and `missed` is precisely what catch-up
/// infers from the ABSENCE of such an assertion. Running catch-up here would
/// also invalidate the payload's id before it could be used, turning a
/// legitimate "Done" into a no-op.
///
/// Touches no notifications; that is [rewriteDigestHorizon]'s job.
Future<void> applyDoneAction({
  required AppDatabase database,
  required String occurrenceId,
  required String? actingMemberId,
  Clock clock = const Clock(),
}) async {
  final chores = ChoreRepository(database);
  final occurrence = await chores.getOccurrence(occurrenceId);
  if (occurrence == null || occurrence.status != OccurrenceStatus.pending) {
    return;
  }
  final service = ChoreService(
    database: database,
    chores: chores,
    clock: clock,
  );
  try {
    await service.completeOccurrence(occurrenceId, completedBy: actingMemberId);
  } on StateError {
    // `ChoreService._closeAndAdvance` THROWS (it does not silently return)
    // when the occurrence is not pending, so this is the narrow race between
    // the read above and the transaction below it: something else closed the
    // row in between. Same silent no-op as finding it already closed.
    //
    // `on StateError` specifically, NOT `on Object`: this is one known race,
    // not a safety net wrapped around a user-confirmed destructive action, and
    // swallowing everything here would hide a real database failure in a
    // context that has no other way to surface one.
    return;
  }
}

/// Rewrites the digest's ENTIRE scheduling horizon from the current state of
/// [database], through the same `buildDigestPlans` the app itself uses.
///
/// Needed because the occurrence the user just completed was counted into ALL
/// the still-pending slots, so after the write their bodies are known-wrong.
/// Concretely: a one-off marked done from the notification, app never
/// re-opened — the next slot fires saying "1 overdue chore" about a chore the
/// user has just told the app they did. Rewriting costs the same
/// `digestHorizonSlots` platform calls as `cancelDigest()` would and is
/// strictly better: cancelling produces up to 83 days of silence for exactly
/// the disengaged user the horizon exists to serve.
///
/// Re-uses `buildDigestPlans` rather than re-deriving counts. That free
/// function already had two callers "that cannot share a controller"; a third,
/// in another isolate, is what it is for. Re-deriving here would be a defect.
///
/// ## Two concurrency hazards, both recorded rather than fixed
///
/// **`applyDigestPlans`' serialization does not cross isolates.** Its
/// `_applyTail` chain is per-instance, so the scheduler this function is given
/// (constructed inside the background isolate) and the main isolate's own can
/// interleave writes to the same `digestHorizonSlots` ids. It is
/// self-correcting whenever it can happen at all: interleaving requires the app
/// to be alive, and an alive app receives the handler's ping AFTER the
/// completion is written, so the main isolate's last apply always runs on
/// post-completion data (`DigestRescheduleController`'s depth-1 queue makes a
/// trigger arriving mid-apply run afterwards rather than be dropped). When the
/// app is dead there is no second writer at all. **Do not add a cross-isolate
/// lock.**
///
/// **`cancelDigest()` is unserialized against `applyDigestPlans`** (see
/// `docs/handover-2026-08-14-planning.md` §4). Previously academic; with this
/// second process-level writer it becomes reachable in principle — a wipe
/// (`reset_flow.dart`) racing a notification action. The consequence is bounded
/// (a reset that leaves one armed slot, fixed by the next recompute) and the
/// window is a user physically confirming a destructive wipe while also tapping
/// a notification. Flagged, not fixed here: fixing it means serializing
/// `cancelDigest` onto `_applyTail`, which belongs with whoever owns
/// `NotificationScheduler` next.
Future<void> rewriteDigestHorizon({
  required AppDatabase database,
  required NotificationScheduler scheduler,
  required String? actingMemberId,
  Clock clock = const Clock(),
}) async {
  final household = await HouseholdRepository(database).getHousehold();
  if (household == null) {
    // No household means nothing could have been scheduled in the first place.
    return;
  }
  // Note `ensureSettings()` WRITES a default row if none exists -- it is not a
  // pure read. Harmless and consistent with every other caller, but worth
  // knowing about in a background context.
  final settings = await SettingsRepository(database).ensureSettings();
  final pending = await ChoreRepository(
    database,
  ).getPendingOccurrences(household.id);
  await scheduler.applyDigestPlans(
    buildDigestPlans(
      now: clock.now(),
      settings: settings,
      pending: pending,
      recipientMemberId: actingMemberId,
    ),
    actingMemberId: actingMemberId,
  );
}

/// The locale the background isolate must render notification copy in.
///
/// The isolate has no Riverpod container, so it cannot read
/// `localeOverrideProvider` — but it must reach the SAME answer, because the
/// main isolate and this one write to the same notification ids and must
/// produce identical copy. So it reads the same persisted `settings.locale`
/// through the same [localeFromStoredSetting] mapping and the same
/// [resolveDigestLocale] fallback.
///
/// Using [NotificationScheduler]'s bare `PlatformDispatcher.instance.locale`
/// default instead would hand a user who chose German on an English phone an
/// English "Done" button under a German app — precisely the defect backlog E-1
/// closed for the digest's title and body, and more glaring on a button.
Future<ui.Locale> readDigestLocale(AppDatabase database) async {
  final settings = await SettingsRepository(database).ensureSettings();
  return resolveDigestLocale(localeFromStoredSetting(settings.locale));
}
