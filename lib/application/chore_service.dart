/// Application-layer orchestration between the recurrence engine
/// (`lib/domain/recurrence/`) and the data layer (`lib/data/`).
///
/// Owns every rule about when occurrences are created, closed, missed, and
/// who they're assigned to. See `docs/specs/occurrence-lifecycle.md` for the
/// authoritative semantics.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/recurrence/recurrence_engine.dart';
import 'package:chore_app/domain/rotation.dart';
import 'package:clock/clock.dart';

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
  Future<Chore> createChore({
    required String householdId,
    required String title,
    required PlainDate startDate,
    required AssignmentMode assignmentMode,
    String? notes,
    String? categoryId,
    Recurrence? recurrence,
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
  /// Throws [StateError] if the occurrence is not currently pending.
  Future<void> completeOccurrence(
    String occurrenceId, {
    required String completedBy,
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

  /// Runs on app start and on day change. For every active, unpaused,
  /// schedule-anchored recurring chore in [householdId] with a pending
  /// occurrence where at least one later series slot is <= today: closes the
  /// pending occurrence as `missed` and inserts a new pending occurrence at
  /// the latest series slot <= today, keeping the same assigned member.
  ///
  /// Completion-anchored and one-off chores are never touched; they simply
  /// stay overdue. Idempotent: calling this again the same day changes
  /// nothing.
  Future<void> catchUpOverdue(String householdId) async {
    final today = _today;
    await database.transaction(() async {
      final activeChores = await chores.watchActiveChores(householdId).first;
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
        final latestSlot = _latestOverdueSlot(
          rule: recurrence,
          startDate: chore.startDate,
          afterDueDate: pending.dueDate,
          today: today,
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
      }
    });
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

  /// Unpauses [choreId] and inserts a fresh pending occurrence. A no-op if
  /// the chore is already unpaused.
  ///
  /// Due date: schedule anchor -> `nextScheduledOnOrAfter(rule, startDate,
  /// today)`; completion anchor -> today; one-off -> [Chore.startDate] if
  /// it's on or after today, else today. Assignee: `fixed` -> the assignee;
  /// `anyone` -> `null`; `rotation` -> continues from history via
  /// [nextRotationAssignee].
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

      final dueDate = _unpauseDueDate(chore: chore, today: today);
      final assignedMemberId = await _unpauseAssignee(
        choreId: choreId,
        mode: chore.assignmentMode,
        orderedMemberIds: details.assigneeMemberIds,
      );
      await chores.insertOccurrence(
        choreId: choreId,
        dueDate: dueDate,
        assignedMemberId: assignedMemberId,
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

  /// The due date of the fresh occurrence inserted by [unpauseChore].
  PlainDate _unpauseDueDate({required Chore chore, required PlainDate today}) {
    final recurrence = chore.recurrence;
    if (recurrence == null) {
      return chore.startDate.isOnOrAfter(today) ? chore.startDate : today;
    }
    if (recurrence.anchor == RecurrenceAnchor.completion) {
      return today;
    }
    return nextScheduledOnOrAfter(recurrence, chore.startDate, today);
  }

  /// The assignee of the fresh occurrence inserted by [unpauseChore].
  Future<String?> _unpauseAssignee({
    required String choreId,
    required AssignmentMode mode,
    required List<String> orderedMemberIds,
  }) async {
    switch (mode) {
      case AssignmentMode.fixed:
        return orderedMemberIds.single;
      case AssignmentMode.anyone:
        return null;
      case AssignmentMode.rotation:
        final latestClosed = await chores.latestClosedOccurrence(choreId);
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

  /// Looks up an occurrence by id directly, since [ChoreRepository] only
  /// exposes chore-scoped occurrence lookups.
  Future<ChoreOccurrence?> _findOccurrence(String occurrenceId) {
    return (database.select(
      database.choreOccurrences,
    )..where((tbl) => tbl.id.equals(occurrenceId))).getSingleOrNull();
  }
}

/// The latest schedule slot for [rule]/[startDate] that is `<= today` and
/// strictly after [afterDueDate], or `null` if there is none (i.e. the chore
/// isn't overdue past [afterDueDate]).
///
/// Walks forward one slot at a time from [afterDueDate] via
/// [nextScheduledOnOrAfter], which is efficient per that function's
/// performance contract; the number of steps is bounded by how many slots
/// have been missed, not by the distance from the chore's start date.
PlainDate? _latestOverdueSlot({
  required Recurrence rule,
  required PlainDate startDate,
  required PlainDate afterDueDate,
  required PlainDate today,
}) {
  var latest = nextScheduledOnOrAfter(rule, startDate, afterDueDate.addDays(1));
  if (latest.isAfter(today)) {
    return null;
  }
  while (true) {
    final next = nextScheduledOnOrAfter(rule, startDate, latest.addDays(1));
    if (next.isAfter(today)) {
      return latest;
    }
    latest = next;
  }
}
