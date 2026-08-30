/// Application-layer orchestration between the recurrence engine
/// (`lib/domain/recurrence/`) and the data layer (`lib/data/`).
///
/// Owns every rule about when occurrences are created, closed, missed, and
/// who they're assigned to. See `docs/specs/occurrence-lifecycle.md` for the
/// authoritative semantics.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/sync_dirty.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/recurrence/recurrence_engine.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/domain/rotation.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

/// Orchestrates chore/occurrence lifecycle rules on top of [ChoreRepository]
/// primitives.
///
/// "Today" is always `PlainDate.fromDateTime(clock.now())` — the device's
/// local calendar day, computed exactly once per public method call. Every
/// public method that performs more than one write runs inside
/// `database.transaction(...)`.
class ChoreService {
  /// Creates a service backed by [database] (used to open transactions) and
  /// [chores] (the storage primitives it orchestrates). [clock] defaults to
  /// the real system clock; tests should inject `Clock.fixed(...)`.
  ChoreService({
    required this.database,
    required this.chores,
    this.clock = const Clock(),
  });

  /// The database this service opens transactions on.
  final AppDatabase database;

  /// The repository primitives this service orchestrates.
  final ChoreRepository chores;

  /// The clock used to determine "today". Injectable for deterministic
  /// tests.
  final Clock clock;

  /// The current local calendar day, per [clock].
  PlainDate get _today => PlainDate.fromDateTime(clock.now());

  /// Creates a chore, then inserts its first pending occurrence.
  ///
  /// Due date: `recurrence == null` (one-off) -> [startDate]; otherwise ->
  /// `firstDueDate(recurrence, startDate)`. Assigned member: `fixed` -> the
  /// single assignee; `rotation` -> [assigneeMemberIds] position 0; `anyone`
  /// -> `null`.
  ///
  /// [reminderMinutes] is the chore's individual reminder time as minutes
  /// since local midnight, or `null` (the default) for no individual
  /// reminder — spec `docs/specs/notifications-n2.md` §2.1, decision D1.
  /// The opt-in and the time are one nullable fact, so `null` here is not
  /// "unset, use a default": it IS the off state.
  Future<Chore> createChore({
    required String householdId,
    required String title,
    required PlainDate startDate,
    required AssignmentMode assignmentMode,
    String? notes,
    String? categoryId,
    Recurrence? recurrence,
    int? reminderMinutes,
    List<String> assigneeMemberIds = const [],
    String? createdBy,
  }) {
    return database.transaction(() async {
      final chore = await chores.createChore(
        householdId: householdId,
        title: title,
        startDate: startDate,
        assignmentMode: assignmentMode,
        notes: notes,
        categoryId: categoryId,
        recurrence: recurrence,
        reminderMinutes: reminderMinutes ?? defaultReminderMinutes,
        assigneeMemberIds: assigneeMemberIds,
        createdBy: createdBy,
      );
      final dueDate = recurrence == null
          ? startDate
          : firstDueDate(recurrence, startDate);
      final assignedMemberId = _initialAssignee(
        mode: assignmentMode,
        orderedMemberIds: assigneeMemberIds,
      );
      await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: dueDate,
        assignedMemberId: assignedMemberId,
      );
      return chore;
    });
  }

  /// Marks [occurrenceId] as done, recording [completedBy], then (for a
  /// recurring chore) inserts the next pending occurrence with the rotation
  /// advanced.
  ///
  /// [completedBy] is nullable — an UNATTRIBUTED completion — and stays
  /// `required` so no caller can omit it by accident. Two callers, two
  /// different right answers, and the asymmetry is deliberate:
  ///
  /// - **In-app** (`chores_list_screen.dart`) a null identity is REFUSED: the
  ///   tap is abandoned and a snackbar asks the user who they are (T1.3). That
  ///   is right there, because there is a user looking at a screen who can
  ///   answer.
  /// - **From a digest notification action** (spec
  ///   `docs/specs/notifications.md` N2) a null identity is ACCEPTED and
  ///   recorded as null. There is no UI to ask in, and the alternatives are
  ///   both worse: dropping the tap silently discards the user's explicit "I
  ///   did this", and guessing at a member is the misattribution backlog A-5
  ///   closed.
  ///
  /// Nothing else changes: the `completed_by` column has always been nullable
  /// ([skipOccurrence] already writes null through the same
  /// `_closeAndAdvance`), and rotation advances on `assigned_member_id`, never
  /// on `completed_by`.
  ///
  /// Throws [StateError] if the occurrence is not currently pending.
  Future<void> completeOccurrence(
    String occurrenceId, {
    required String? completedBy,
  }) {
    return _closeAndAdvance(
      occurrenceId,
      status: OccurrenceStatus.done,
      completedBy: completedBy,
    );
  }

  /// Marks [occurrenceId] as skipped, then (for a recurring chore) inserts
  /// the next pending occurrence, keeping the same assignee (falling back to
  /// the next rotation member if it's no longer valid).
  ///
  /// Throws [StateError] if the occurrence is not currently pending.
  Future<void> skipOccurrence(String occurrenceId) {
    return _closeAndAdvance(occurrenceId, status: OccurrenceStatus.skipped);
  }

  /// Runs on app start, on app resume, and on local day change (spec
  /// `docs/specs/polish-round-1.md` C1: see `CatchUpController` in
  /// `lib/app/providers.dart`). For every active, unpaused,
  /// schedule-anchored recurring chore in [householdId] with a pending
  /// occurrence where at least one later series slot is <= today: closes the
  /// pending occurrence as `missed` and inserts a new pending occurrence at
  /// the latest series slot <= today, keeping the same assigned member.
  ///
  /// Completion-anchored and one-off chores are never touched; they simply
  /// stay overdue. Idempotent: calling this again the same day changes
  /// nothing.
  ///
  /// Returns the number of chores it changed — i.e. how many had their
  /// pending occurrence closed as `missed` and a fresh one reinserted (0 if
  /// none, which is the common case).
  ///
  /// Nothing in the lifecycle branches on that number: the digest recompute
  /// `CatchUpController` runs after each catch-up is deliberately
  /// UNCONDITIONAL (see `_runCatchUp` in `lib/app/providers.dart` for why —
  /// a day passing is itself a reason to re-arm the horizon). The UI is what
  /// needs the count: a nonzero result is what lets `CatchUpBanner`
  /// (`lib/features/chores/catch_up_banner.dart`) tell a returning user that
  /// this happened, and to how many chores, instead of leaving freshly
  /// overdue tiles to appear out of nowhere and read as an accusation
  /// (backlog B-1 / triage T2.1).
  Future<int> catchUpOverdue(String householdId) async {
    final today = _today;
    var changedCount = 0;
    await database.transaction(() async {
      final activeChores = await chores.getActiveChores(householdId);
      for (final details in activeChores) {
        final chore = details.chore;
        final recurrence = chore.recurrence;
        if (chore.pausedAt != null ||
            recurrence == null ||
            recurrence.anchor != RecurrenceAnchor.schedule) {
          continue;
        }
        final pending = await chores.pendingOccurrenceOf(chore.id);
        if (pending == null) {
          continue;
        }
        final latestSlot = latestScheduledOnOrBefore(
          rule: recurrence,
          startDate: chore.startDate,
          afterDueDate: pending.dueDate,
          notAfter: today,
        );
        if (latestSlot == null) {
          continue;
        }
        await chores.closeOccurrence(
          pending.id,
          status: OccurrenceStatus.missed,
          closedOn: today,
        );
        await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: latestSlot,
          assignedMemberId: pending.assignedMemberId,
        );
        changedCount++;
      }
    });
    return changedCount;
  }

  /// Pauses [choreId] and deletes its pending occurrence. History is
  /// untouched. A no-op if the chore is already paused.
  ///
  /// Throws [StateError] if the chore doesn't exist or is soft-deleted.
  Future<void> pauseChore(String choreId) async {
    await database.transaction(() async {
      final details = await _requireActiveChore(choreId);
      if (details.chore.pausedAt != null) {
        return;
      }
      await chores.setPaused(choreId, paused: true);
      await chores.deletePendingOccurrences(choreId);
    });
  }

  /// Unpauses [choreId] and inserts a fresh pending occurrence — unless the
  /// chore is a one-off whose only occurrence is already closed, in which
  /// case no occurrence is inserted at all (see below). A no-op if the
  /// chore is already unpaused.
  ///
  /// Fetches `latestClosedOccurrence` (the most recent occurrence that is
  /// done, skipped, or missed — deliberately including skipped: a skipped
  /// slot must not resurrect either, "skip sticks") exactly once, and uses
  /// it to pick the due date:
  ///
  /// - one-off: if a closed occurrence exists, unpause the chore but insert
  ///   NO occurrence — a completed/skipped one-off must never come back.
  ///   Otherwise unchanged: [Chore.startDate] if it's on or after today,
  ///   else today.
  /// - schedule anchor: `nextScheduledOnOrAfter(rule, startDate, fromDate)`,
  ///   where `fromDate` is today if there's no closed occurrence or its due
  ///   date is before today, else the day after its due date. See
  ///   `docs/specs/occurrence-lifecycle.md` §2 for the two-floors
  ///   rationale (this is what fixes the done/skip -> pause -> unpause
  ///   "resurrected today's occurrence" bug).
  /// - completion anchor: unchanged (today) if there's no closed
  ///   occurrence; otherwise `nextAfterCompletion(rule, closed.closedOn)` if
  ///   that's after today, else today.
  ///
  /// Assignee: `fixed` -> the assignee; `anyone` -> `null`; `rotation` ->
  /// continues from history via [nextRotationAssignee].
  ///
  /// Throws [StateError] if the chore doesn't exist or is soft-deleted.
  Future<void> unpauseChore(String choreId) async {
    final today = _today;
    await database.transaction(() async {
      final details = await _requireActiveChore(choreId);
      final chore = details.chore;
      if (chore.pausedAt == null) {
        return;
      }
      await chores.setPaused(choreId, paused: false);

      final latestClosed = await chores.latestClosedOccurrence(choreId);
      final dueDate = _regeneratedDueDate(
        chore: chore,
        today: today,
        latestClosed: latestClosed,
      );
      if (dueDate == null) {
        return;
      }
      final assignedMemberId = _regeneratedAssignee(
        mode: chore.assignmentMode,
        orderedMemberIds: details.assigneeMemberIds,
        latestClosed: latestClosed,
      );
      await chores.insertOccurrence(
        choreId: choreId,
        dueDate: dueDate,
        assignedMemberId: assignedMemberId,
      );
    });
  }

  /// Updates [choreId] via [ChoreRepository.updateChore] (same parameters,
  /// same "omit to leave unchanged" convention), then, if the edit changed
  /// `recurrence` and/or `startDate` — compared by VALUE, via
  /// [Recurrence]'s own `==` (backlog E-4); a bare `null` only ever equals
  /// `null` — in the same transaction:
  ///
  /// - deletes the chore's current pending occurrence (if any);
  /// - if the chore is paused, stops there: a paused chore has no pending
  ///   occurrence by design (see [pauseChore]), and [unpauseChore] will
  ///   compute the right one later, reading this now-updated row;
  /// - otherwise inserts a fresh one using THE SAME two-floors due-date
  ///   rule as [unpauseChore] (see [_regeneratedDueDate]: never before
  ///   today; never at or before the latest closed slot; closed one-off ->
  ///   nothing; completion anchor -> `max(today, nextAfterCompletion)`),
  ///   with the assignee re-resolved the same way (see
  ///   [_regeneratedAssignee]).
  ///
  /// An edit that changes NEITHER `recurrence` nor `startDate` leaves the
  /// pending occurrence — and its assignee — completely untouched, no
  /// matter what else changed (title, notes, category, assignment
  /// mode/assignees, [reminderMinutes]).
  ///
  /// [reminderMinutes] follows the same "omit to leave unchanged"
  /// convention as [notes] and [categoryId]: `Value.absent()` leaves the
  /// stored value alone, `Value(null)` clears the chore's individual
  /// reminder, `Value(m)` sets it (spec
  /// `docs/specs/notifications-n2.md` §2.1, decision D1).
  ///
  /// It is deliberately NOT part of the `recurrenceChanged` /
  /// `startDateChanged` comparison below, which decides whether to
  /// regenerate the pending occurrence
  /// (`docs/specs/occurrence-lifecycle.md` §2). A reminder time is a
  /// notification fact, not a schedule fact: changing it must not move,
  /// recreate or reassign an occurrence. That is the same distinction
  /// decision D5 draws for snooze.
  ///
  /// Throws [StateError] if the chore doesn't exist or is soft-deleted.
  Future<void> updateChore(
    String choreId, {
    String? title,
    Value<String?> notes = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<Recurrence?> recurrence = const Value.absent(),
    Value<int?> reminderMinutes = const Value.absent(),
    PlainDate? startDate,
    AssignmentMode? assignmentMode,
    List<String>? assigneeMemberIds,
  }) async {
    final today = _today;
    await database.transaction(() async {
      final before = await _requireActiveChore(choreId);
      // Value equality, straight from `Recurrence.==` (backlog E-4).
      // This used to compare `jsonEncode(a.toJson())` strings because
      // `Recurrence` had only identity equality -- equivalent in result
      // (`toJson` sorts `weekdays`, so order-independence held), but it
      // allocated two JSON strings on every chore edit and would have
      // silently stopped noticing a field added to `Recurrence` but not to
      // `toJson`.
      final recurrenceChanged =
          recurrence.present && recurrence.value != before.chore.recurrence;
      final startDateChanged =
          startDate != null && startDate != before.chore.startDate;

      await chores.updateChore(
        choreId,
        title: title,
        notes: notes,
        categoryId: categoryId,
        recurrence: recurrence,
        reminderMinutes: reminderMinutes,
        startDate: startDate,
        assignmentMode: assignmentMode,
        assigneeMemberIds: assigneeMemberIds,
      );

      if (!recurrenceChanged && !startDateChanged) {
        return;
      }

      await chores.deletePendingOccurrences(choreId);
      final after = await _requireChore(choreId);
      if (after.chore.pausedAt != null) {
        return;
      }

      final latestClosed = await chores.latestClosedOccurrence(choreId);
      final dueDate = _regeneratedDueDate(
        chore: after.chore,
        today: today,
        latestClosed: latestClosed,
      );
      if (dueDate == null) {
        return;
      }
      final assignedMemberId = _regeneratedAssignee(
        mode: after.chore.assignmentMode,
        orderedMemberIds: after.assigneeMemberIds,
        latestClosed: latestClosed,
      );
      await chores.insertOccurrence(
        choreId: choreId,
        dueDate: dueDate,
        assignedMemberId: assignedMemberId,
      );
    });
  }

  /// Reopens a closed-today occurrence: in one transaction, deletes the
  /// chore's current pending occurrence (if any) and resets [occurrenceId]
  /// back to pending, clearing `closedOn`/`completedBy` while keeping its
  /// assignee.
  ///
  /// This is the undo path for [completeOccurrence]/[skipOccurrence] (see
  /// `docs/specs/ux-round-2.md` A3/A4 and `docs/specs/occurrence-lifecycle.md`
  /// §2). The "closed today" restriction is enforced here, at the service
  /// level — [ChoreRepository] has no notion of "today".
  ///
  /// **LIFO restriction (amended 2026-08-01, field feedback B2 —
  /// `docs/feedback/2026-08-01-field-feedback.md`):** a chore can have
  /// SEVERAL closed-today occurrences (the successor of a closed occurrence
  /// can itself be closed immediately), and the blanket
  /// "delete the pending occurrence" step above would destroy a sibling an
  /// earlier reopen just restored — the original data-loss bug. So only the
  /// LATEST closed-today occurrence of [occurrenceId]'s chore — ordered by
  /// due date, then `updatedAt` as tiebreak — may be reopened; reopening any
  /// other one throws [StateError] and changes nothing. Unwinding a
  /// multi-close chain therefore takes several reopens, newest-first.
  ///
  /// Throws [StateError] if the chore has been deleted, if [occurrenceId]
  /// isn't currently closed with `closedOn == today`, or if it isn't the
  /// latest closed-today occurrence of its chore.
  Future<void> reopenOccurrence(String occurrenceId) async {
    final today = _today;
    await database.transaction(() async {
      final occurrence = await _findOccurrence(occurrenceId);
      if (occurrence == null ||
          occurrence.status == OccurrenceStatus.pending ||
          occurrence.closedOn != today) {
        throw StateError(
          'Occurrence $occurrenceId is not a closed-today occurrence',
        );
      }
      final choreDetails = await chores.getChore(occurrence.choreId);
      if (choreDetails == null || choreDetails.chore.deletedAt != null) {
        throw StateError('Chore ${occurrence.choreId} has been deleted');
      }

      final closedToday = await _closedTodayOccurrencesOf(
        occurrence.choreId,
        today,
      );
      // `occurrence` itself is always in this list (it just passed the
      // closed-today check above), so `closedToday` is never empty here.
      if (closedToday.first.id != occurrenceId) {
        throw StateError(
          'Occurrence $occurrenceId is not the latest closed-today '
          'occurrence of chore ${occurrence.choreId}; reopen '
          '${closedToday.first.id} first',
        );
      }

      await chores.deletePendingOccurrences(occurrence.choreId);

      await (database.update(
        database.choreOccurrences,
      )..where((tbl) => tbl.id.equals(occurrenceId))).write(
        ChoreOccurrencesCompanion(
          status: const Value(OccurrenceStatus.pending),
          closedOn: const Value(null),
          completedBy: const Value(null),
          updatedAt: Value(clock.now().toUtc().toIso8601String()),
          syncDirty: syncDirtyOnWrite,
        ),
      );
    });
  }

  /// Shared implementation of [completeOccurrence] and [skipOccurrence]:
  /// validates pending-ness, closes with [status], and (for a recurring
  /// chore) inserts the next occurrence with the appropriate assignee.
  Future<void> _closeAndAdvance(
    String occurrenceId, {
    required OccurrenceStatus status,
    String? completedBy,
  }) async {
    final today = _today;
    await database.transaction(() async {
      final occurrence = await _findOccurrence(occurrenceId);
      if (occurrence == null || occurrence.status != OccurrenceStatus.pending) {
        throw StateError('Occurrence $occurrenceId is not pending');
      }
      await chores.closeOccurrence(
        occurrenceId,
        status: status,
        closedOn: today,
        completedBy: completedBy,
      );

      final choreDetails = await _requireChore(occurrence.choreId);
      final chore = choreDetails.chore;
      final recurrence = chore.recurrence;
      if (recurrence == null) {
        return;
      }

      final nextDueDate = nextDueDateAfterClosing(
        rule: recurrence,
        startDate: chore.startDate,
        closedDueDate: occurrence.dueDate,
        closedOn: today,
        skipped: status == OccurrenceStatus.skipped,
      );
      final nextAssignee = _nextAssignee(
        mode: chore.assignmentMode,
        orderedMemberIds: choreDetails.assigneeMemberIds,
        previousAssignee: occurrence.assignedMemberId,
        done: status == OccurrenceStatus.done,
      );
      await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: nextDueDate,
        assignedMemberId: nextAssignee,
      );
    });
  }

  /// The assignee of a newly-created chore's first occurrence.
  String? _initialAssignee({
    required AssignmentMode mode,
    required List<String> orderedMemberIds,
  }) {
    switch (mode) {
      case AssignmentMode.fixed:
        return orderedMemberIds.single;
      case AssignmentMode.rotation:
        return orderedMemberIds[0];
      case AssignmentMode.anyone:
        return null;
    }
  }

  /// The assignee of the occurrence that follows a closed one: `fixed` is
  /// always the single assignee; `anyone` is always unassigned; `rotation`
  /// advances on [done] and otherwise sticks to [previousAssignee] (falling
  /// back to the next rotation member if it's `null` or no longer an
  /// assignee).
  String? _nextAssignee({
    required AssignmentMode mode,
    required List<String> orderedMemberIds,
    required String? previousAssignee,
    required bool done,
  }) {
    switch (mode) {
      case AssignmentMode.fixed:
        return orderedMemberIds.single;
      case AssignmentMode.anyone:
        return null;
      case AssignmentMode.rotation:
        if (done) {
          return nextRotationAssignee(
            orderedMemberIds: orderedMemberIds,
            lastAssignedMemberId: previousAssignee,
          );
        }
        if (previousAssignee != null &&
            orderedMemberIds.contains(previousAssignee)) {
          return previousAssignee;
        }
        return nextRotationAssignee(
          orderedMemberIds: orderedMemberIds,
          lastAssignedMemberId: previousAssignee,
        );
    }
  }

  /// The due date of a freshly (re)generated pending occurrence, or `null`
  /// if none should be inserted at all (a closed one-off must never
  /// resurrect). Shared by [unpauseChore] and [updateChore] — both need
  /// "the next due date, given the most recently closed occurrence" under
  /// the exact same two-floors rule (see `docs/specs/occurrence-lifecycle.md`
  /// §2): never before [today], never at or before [latestClosed]'s slot.
  PlainDate? _regeneratedDueDate({
    required Chore chore,
    required PlainDate today,
    required ChoreOccurrence? latestClosed,
  }) {
    final recurrence = chore.recurrence;
    if (recurrence == null) {
      if (latestClosed != null) {
        return null;
      }
      return chore.startDate.isOnOrAfter(today) ? chore.startDate : today;
    }
    if (recurrence.anchor == RecurrenceAnchor.completion) {
      if (latestClosed == null) {
        return today;
      }
      // `closedOn` is always set once an occurrence is non-pending (see
      // `ChoreRepository.closeOccurrence`), so a `latestClosedOccurrence`
      // result never has a null one.
      final candidate = nextAfterCompletion(recurrence, latestClosed.closedOn!);
      return candidate.isAfter(today) ? candidate : today;
    }
    // Schedule anchor. Pause is a vacation: unpause floors at two points —
    // never before today (so it never creates an instantly-overdue
    // occurrence) and never at or before the latest closed slot (so it never
    // resurrects a slot that's already done/skipped — the fix for the
    // done -> pause -> unpause bug this method used to have).
    final fromDate =
        (latestClosed == null || latestClosed.dueDate.isBefore(today))
        ? today
        : latestClosed.dueDate.addDays(1);
    return nextScheduledOnOrAfter(recurrence, chore.startDate, fromDate);
  }

  /// The assignee of a freshly (re)generated pending occurrence. Shared by
  /// [unpauseChore] and [updateChore]; see [_regeneratedDueDate].
  String? _regeneratedAssignee({
    required AssignmentMode mode,
    required List<String> orderedMemberIds,
    required ChoreOccurrence? latestClosed,
  }) {
    switch (mode) {
      case AssignmentMode.fixed:
        return orderedMemberIds.single;
      case AssignmentMode.anyone:
        return null;
      case AssignmentMode.rotation:
        return nextRotationAssignee(
          orderedMemberIds: orderedMemberIds,
          lastAssignedMemberId: latestClosed?.assignedMemberId,
        );
    }
  }

  /// Fetches [choreId]'s details, throwing [StateError] if it doesn't exist.
  Future<ChoreWithDetails> _requireChore(String choreId) async {
    final details = await chores.getChore(choreId);
    if (details == null) {
      throw StateError('No chore with id $choreId');
    }
    return details;
  }

  /// Fetches [choreId]'s details, throwing [StateError] if it doesn't exist
  /// or has been soft-deleted.
  Future<ChoreWithDetails> _requireActiveChore(String choreId) async {
    final details = await _requireChore(choreId);
    if (details.chore.deletedAt != null) {
      throw StateError('Chore $choreId has been deleted');
    }
    return details;
  }

  /// Looks up an occurrence by id, whichever chore owns it.
  ///
  /// Delegates to [ChoreRepository.getOccurrence] rather than re-issuing the
  /// query. This was a private copy of that query only because the repository
  /// exposed nothing but chore-scoped occurrence lookups; the digest
  /// notification action (spec `docs/specs/notifications.md` N2) needed a
  /// public one, and two copies of a query is how a third appears.
  Future<ChoreOccurrence?> _findOccurrence(String occurrenceId) =>
      chores.getOccurrence(occurrenceId);

  /// [choreId]'s occurrences closed (done/skipped/missed) with
  /// `closedOn == today`, ordered newest-first by due date then
  /// `updatedAt` — the LIFO order [reopenOccurrence] enforces (see its doc
  /// comment). Direct query rather than a [ChoreRepository] method since,
  /// like [_findOccurrence], this is a service-only, "today"-aware shape.
  Future<List<ChoreOccurrence>> _closedTodayOccurrencesOf(
    String choreId,
    PlainDate today,
  ) {
    return (database.select(database.choreOccurrences)
          ..where(
            (tbl) =>
                tbl.choreId.equals(choreId) &
                tbl.status.equalsValue(OccurrenceStatus.pending).not() &
                tbl.closedOn.equalsValue(today),
          )
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.dueDate, mode: OrderingMode.desc),
            (tbl) => OrderingTerm(
              expression: tbl.updatedAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }
}
