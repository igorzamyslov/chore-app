/// Manages chores, their assignees, and their occurrences.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/sync_dirty.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A chore joined with its ordered assignee ids and resolved category.
class ChoreWithDetails {
  /// Creates a chore detail view.
  const ChoreWithDetails({
    required this.chore,
    required this.assigneeMemberIds,
    this.category,
  });

  /// The chore row itself.
  final Chore chore;

  /// Assignee member ids in rotation order (empty for the `anyone`
  /// assignment mode).
  final List<String> assigneeMemberIds;

  /// The chore's category, or `null` if uncategorized.
  final Category? category;
}

/// A pending chore occurrence joined with its chore, category, and
/// assigned member.
class OccurrenceWithChore {
  /// Creates an occurrence detail view.
  const OccurrenceWithChore({
    required this.occurrence,
    required this.chore,
    this.category,
    this.assignedMember,
  });

  /// The occurrence row itself.
  final ChoreOccurrence occurrence;

  /// The chore this occurrence belongs to.
  final Chore chore;

  /// The chore's category, or `null` if uncategorized.
  final Category? category;

  /// The member this occurrence is assigned to, or `null` if unassigned.
  final Member? assignedMember;
}

/// A closed (done/skipped/missed) occurrence joined with its chore,
/// category, assigned member, and the member who completed it (if any).
class ClosedOccurrenceWithChore {
  /// Creates a closed-occurrence detail view.
  const ClosedOccurrenceWithChore({
    required this.occurrence,
    required this.chore,
    this.category,
    this.assignedMember,
    this.completedByMember,
  });

  /// The occurrence row itself.
  final ChoreOccurrence occurrence;

  /// The chore this occurrence belongs to.
  final Chore chore;

  /// The chore's category, or `null` if uncategorized.
  final Category? category;

  /// The member this occurrence was assigned to, or `null` if unassigned.
  final Member? assignedMember;

  /// The member who completed this occurrence, or `null` if it wasn't
  /// completed (e.g. it was skipped rather than done).
  final Member? completedByMember;
}

/// Repository for chores, their assignees, and their occurrences.
///
/// Occurrence creation/closing decisions (recurrence math, "what's due
/// next") belong to a service layer built on top of this repository; the
/// occurrence methods here are storage primitives only.
class ChoreRepository {
  /// Creates a repository backed by [db].
  ///
  /// [newId] and [nowUtc] are injectable so tests can supply deterministic
  /// ids and a controllable clock; they default to a random UUIDv4
  /// generator and the real UTC clock, respectively.
  ChoreRepository(
    this.db, {
    this.newId = _defaultNewId,
    this.nowUtc = _defaultNowUtc,
  });

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Generates the id for a newly inserted row.
  final String Function() newId;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Creates a chore (and its assignee rows) in a single transaction.
  ///
  /// Validates [assigneeMemberIds] against [assignmentMode]: the `fixed`
  /// mode requires exactly 1 assignee, `rotation` requires 2 or more, and
  /// `anyone` requires 0. Throws [ArgumentError] otherwise.
  ///
  /// Does NOT create occurrences; that's the service layer's job.
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
  }) async {
    _validateAssignees(assignmentMode, assigneeMemberIds);
    final now = _isoNow();
    final id = newId();
    return db.transaction(() async {
      await db
          .into(db.chores)
          .insert(
            ChoresCompanion.insert(
              id: id,
              householdId: householdId,
              title: title,
              notes: Value(notes),
              categoryId: Value(categoryId),
              recurrence: Value(recurrence),
              startDate: startDate,
              assignmentMode: assignmentMode,
              createdBy: Value(createdBy),
              createdAt: now,
              updatedAt: now,
              syncDirty: syncDirtyOnWrite,
            ),
          );
      await _insertAssignees(id, assigneeMemberIds);
      return Chore(
        id: id,
        householdId: householdId,
        title: title,
        notes: notes,
        categoryId: categoryId,
        recurrence: recurrence,
        startDate: startDate,
        assignmentMode: assignmentMode,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
        syncDirty: true,
      );
    });
  }

  /// Updates the given fields of an existing chore.
  ///
  /// [title], [startDate], and [assignmentMode] are plain "leave unchanged
  /// if omitted" parameters. [notes], [categoryId], and [recurrence] are
  /// themselves nullable in the schema, so a bare `null` would be
  /// ambiguous between "unchanged" and "clear it"; they use drift's
  /// `Value` wrapper instead — omit the parameter (default
  /// `Value.absent()`) to leave it unchanged, or pass `Value(null)` to
  /// write `NULL`.
  ///
  /// If [assigneeMemberIds] is provided, it replaces the chore's assignee
  /// list (preserving the given order as rotation position). The same
  /// fixed/rotation/anyone validation as [createChore] applies to the
  /// *effective* mode and assignee list after this update (falling back to
  /// the chore's current mode and/or current assignees for whichever of
  /// the two isn't being changed).
  Future<void> updateChore(
    String id, {
    String? title,
    Value<String?> notes = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<Recurrence?> recurrence = const Value.absent(),
    PlainDate? startDate,
    AssignmentMode? assignmentMode,
    List<String>? assigneeMemberIds,
  }) async {
    await db.transaction(() async {
      final current = await (db.select(
        db.chores,
      )..where((tbl) => tbl.id.equals(id))).getSingle();
      final effectiveMode = assignmentMode ?? current.assignmentMode;
      final effectiveAssignees =
          assigneeMemberIds ?? await _currentAssigneeIds(id);
      _validateAssignees(effectiveMode, effectiveAssignees);

      await (db.update(db.chores)..where((tbl) => tbl.id.equals(id))).write(
        ChoresCompanion(
          title: title != null ? Value(title) : const Value.absent(),
          notes: notes,
          categoryId: categoryId,
          recurrence: recurrence,
          startDate: startDate != null
              ? Value(startDate)
              : const Value.absent(),
          assignmentMode: assignmentMode != null
              ? Value(assignmentMode)
              : const Value.absent(),
          updatedAt: Value(_isoNow()),
          syncDirty: syncDirtyOnWrite,
        ),
      );

      if (assigneeMemberIds != null) {
        await (db.delete(
          db.choreAssignees,
        )..where((tbl) => tbl.choreId.equals(id))).go();
        await _insertAssignees(id, assigneeMemberIds);
      }
    });
  }

  /// Soft-deletes a chore and hard-deletes its pending occurrence, if any.
  ///
  /// History occurrences (done/skipped/missed) are kept.
  Future<void> softDeleteChore(String id) async {
    final now = _isoNow();
    await db.transaction(() async {
      await (db.update(db.chores)..where((tbl) => tbl.id.equals(id))).write(
        ChoresCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncDirty: syncDirtyOnWrite,
        ),
      );
      await (db.delete(db.choreOccurrences)..where(
            (tbl) =>
                tbl.choreId.equals(id) &
                tbl.status.equalsValue(OccurrenceStatus.pending),
          ))
          .go();
    });
  }

  /// Pauses or unpauses a chore.
  Future<void> setPaused(String id, {required bool paused}) async {
    final now = _isoNow();
    await (db.update(db.chores)..where((tbl) => tbl.id.equals(id))).write(
      ChoresCompanion(
        pausedAt: Value(paused ? now : null),
        updatedAt: Value(now),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  /// Watches every active chore in [householdId], each joined with its
  /// ordered assignee ids and category.
  Stream<List<ChoreWithDetails>> watchActiveChores(String householdId) {
    final query =
        db.select(db.chores).join([
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.chores.categoryId),
            ),
          ])
          ..where(
            db.chores.householdId.equals(householdId) &
                db.chores.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm(expression: db.chores.title)]);

    // `asyncMap` re-queries chore_assignees per emission rather than
    // joining it directly, to avoid a row explosion from the one-to-many
    // join. This only stays correct because `createChore`/`updateChore`
    // always bump the chore row's `updated_at` whenever assignees change,
    // which is what actually drives this stream's re-emission.
    return query.watch().asyncMap(_choreDetailsFromRows);
  }

  /// Fetches every active chore in [householdId], each joined with its
  /// ordered assignee ids and category — the one-shot `Future` equivalent
  /// of [watchActiveChores]'s query (same `WHERE`/`ORDER BY`), with no
  /// stream. Used by `ChoreService.catchUpOverdue`, which only ever needs a
  /// single point-in-time read inside its transaction; reading it via
  /// `watchActiveChores(...).first` there was needlessly indirect.
  Future<List<ChoreWithDetails>> getActiveChores(String householdId) async {
    final query =
        db.select(db.chores).join([
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.chores.categoryId),
            ),
          ])
          ..where(
            db.chores.householdId.equals(householdId) &
                db.chores.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm(expression: db.chores.title)]);
    return _choreDetailsFromRows(await query.get());
  }

  /// Fetches a single chore joined with its ordered assignee ids and
  /// category, or `null` if no chore with [id] exists.
  Future<ChoreWithDetails?> getChore(String id) async {
    final query = db.select(db.chores).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.chores.categoryId),
      ),
    ])..where(db.chores.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    final chore = row.readTable(db.chores);
    final category = row.readTableOrNull(db.categories);
    final assigneeIds = await _currentAssigneeIds(id);
    return ChoreWithDetails(
      chore: chore,
      assigneeMemberIds: assigneeIds,
      category: category,
    );
  }

  /// Inserts a new pending occurrence for [choreId].
  Future<ChoreOccurrence> insertOccurrence({
    required String choreId,
    required PlainDate dueDate,
    String? assignedMemberId,
  }) async {
    final now = _isoNow();
    final id = newId();
    await db
        .into(db.choreOccurrences)
        .insert(
          ChoreOccurrencesCompanion.insert(
            id: id,
            choreId: choreId,
            dueDate: dueDate,
            assignedMemberId: Value(assignedMemberId),
            createdAt: now,
            updatedAt: now,
            syncDirty: syncDirtyOnWrite,
          ),
        );
    return ChoreOccurrence(
      id: id,
      choreId: choreId,
      dueDate: dueDate,
      status: OccurrenceStatus.pending,
      assignedMemberId: assignedMemberId,
      createdAt: now,
      updatedAt: now,
      syncDirty: true,
    );
  }

  /// Closes an occurrence with a final [status].
  ///
  /// [status] must be `done`, `skipped`, or `missed`; throws
  /// [ArgumentError] if the `pending` status is passed.
  Future<void> closeOccurrence(
    String occurrenceId, {
    required OccurrenceStatus status,
    required PlainDate closedOn,
    String? completedBy,
  }) async {
    if (status == OccurrenceStatus.pending) {
      throw ArgumentError.value(
        status,
        'status',
        'Must be done, skipped, or missed',
      );
    }
    await (db.update(
      db.choreOccurrences,
    )..where((tbl) => tbl.id.equals(occurrenceId))).write(
      ChoreOccurrencesCompanion(
        status: Value(status),
        closedOn: Value(closedOn),
        completedBy: Value(completedBy),
        updatedAt: Value(_isoNow()),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  /// Returns the pending occurrence of [choreId], or `null` if none.
  Future<ChoreOccurrence?> pendingOccurrenceOf(String choreId) {
    return (db.select(db.choreOccurrences)..where(
          (tbl) =>
              tbl.choreId.equals(choreId) &
              tbl.status.equalsValue(OccurrenceStatus.pending),
        ))
        .getSingleOrNull();
  }

  /// Clears `assignedMemberId` on every PENDING occurrence currently
  /// assigned to [memberId], across every chore (member-deletion
  /// referential cleanup, spec `docs/feedback/2026-08-01-ux-audit.md` A1;
  /// see `MemberService.deleteMember`, `lib/application/member_service.dart`,
  /// which calls this alongside the chore-level assignee cleanup those
  /// methods don't retroactively apply to an already-inserted occurrence).
  ///
  /// Closed occurrences (their own `assignedMemberId`, and `completedBy`)
  /// are deliberately untouched -- history keeps pointing at the
  /// soft-deleted member row.
  Future<void> unassignPendingOccurrencesForMember(String memberId) async {
    await (db.update(db.choreOccurrences)..where(
          (tbl) =>
              tbl.assignedMemberId.equals(memberId) &
              tbl.status.equalsValue(OccurrenceStatus.pending),
        ))
        .write(
          ChoreOccurrencesCompanion(
            assignedMemberId: const Value(null),
            updatedAt: Value(_isoNow()),
            syncDirty: syncDirtyOnWrite,
          ),
        );
  }

  /// Hard-deletes every pending occurrence of [choreId].
  Future<void> deletePendingOccurrences(String choreId) async {
    await (db.delete(db.choreOccurrences)..where(
          (tbl) =>
              tbl.choreId.equals(choreId) &
              tbl.status.equalsValue(OccurrenceStatus.pending),
        ))
        .go();
  }

  /// Returns the most recently closed (done/skipped/missed) occurrence of
  /// [choreId], ordered by closed date then due date, or `null` if none.
  Future<ChoreOccurrence?> latestClosedOccurrence(String choreId) {
    return (db.select(db.choreOccurrences)
          ..where(
            (tbl) =>
                tbl.choreId.equals(choreId) &
                tbl.status.equalsValue(OccurrenceStatus.pending).not(),
          )
          ..orderBy([
            (tbl) => OrderingTerm(
              expression: tbl.closedOn,
              mode: OrderingMode.desc,
            ),
            (tbl) =>
                OrderingTerm(expression: tbl.dueDate, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Watches pending occurrences of active, unpaused chores in
  /// [householdId], joined with their chore, category, and assigned
  /// member, ordered by due date then chore title.
  ///
  /// This is a DISPLAY join (spec `docs/feedback/2026-08-01-ux-audit.md`
  /// A1's members-query classification): the `members` join deliberately
  /// does NOT filter on `deletedAt` -- an occurrence tile's assignee
  /// avatar/name should still resolve if the assigned member is ever
  /// soft-deleted (in practice `MemberService.deleteMember` already clears
  /// `assignedMemberId` on every pending occurrence of a deleted member, so
  /// this mostly matters as a defensive default, not a normally-hit path).
  Stream<List<OccurrenceWithChore>> watchPendingOccurrences(
    String householdId,
  ) {
    final query =
        db.select(db.choreOccurrences).join([
            innerJoin(
              db.chores,
              db.chores.id.equalsExp(db.choreOccurrences.choreId),
            ),
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.chores.categoryId),
            ),
            leftOuterJoin(
              db.members,
              db.members.id.equalsExp(db.choreOccurrences.assignedMemberId),
            ),
          ])
          ..where(
            db.chores.householdId.equals(householdId) &
                db.chores.deletedAt.isNull() &
                db.chores.pausedAt.isNull() &
                db.choreOccurrences.status.equalsValue(
                  OccurrenceStatus.pending,
                ),
          )
          ..orderBy([
            OrderingTerm(expression: db.choreOccurrences.dueDate),
            OrderingTerm(expression: db.chores.title),
          ]);

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          OccurrenceWithChore(
            occurrence: row.readTable(db.choreOccurrences),
            chore: row.readTable(db.chores),
            category: row.readTableOrNull(db.categories),
            assignedMember: row.readTableOrNull(db.members),
          ),
      ];
    });
  }

  /// Watches occurrences of active chores in [householdId] closed (done or
  /// skipped — never missed) with `closedOn == date`, joined with their
  /// chore, category, assigned member, and completer, ordered by chore
  /// title.
  ///
  /// Backs the chores list's collapsed 'Done today' section (see
  /// `docs/specs/ux-round-2.md` A3); the caller passes today's date. This is
  /// also a DISPLAY join (see `watchPendingOccurrences`'s doc comment): the
  /// `members`/`completedByMember` joins never filter on `deletedAt`, so
  /// "done today, by {name}" keeps naming a since-deleted member — history
  /// stays readable (spec `docs/feedback/2026-08-01-ux-audit.md` A1).
  Stream<List<ClosedOccurrenceWithChore>> watchClosedOnDate(
    String householdId,
    PlainDate date,
  ) {
    final completedByMember = db.members.createAlias('completed_by_member');
    final query =
        db.select(db.choreOccurrences).join([
            innerJoin(
              db.chores,
              db.chores.id.equalsExp(db.choreOccurrences.choreId),
            ),
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.chores.categoryId),
            ),
            leftOuterJoin(
              db.members,
              db.members.id.equalsExp(db.choreOccurrences.assignedMemberId),
            ),
            leftOuterJoin(
              completedByMember,
              completedByMember.id.equalsExp(db.choreOccurrences.completedBy),
            ),
          ])
          ..where(
            db.chores.householdId.equals(householdId) &
                db.chores.deletedAt.isNull() &
                db.choreOccurrences.closedOn.equalsValue(date) &
                (db.choreOccurrences.status.equalsValue(
                      OccurrenceStatus.done,
                    ) |
                    db.choreOccurrences.status.equalsValue(
                      OccurrenceStatus.skipped,
                    )),
          )
          ..orderBy([OrderingTerm(expression: db.chores.title)]);

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          ClosedOccurrenceWithChore(
            occurrence: row.readTable(db.choreOccurrences),
            chore: row.readTable(db.chores),
            category: row.readTableOrNull(db.categories),
            assignedMember: row.readTableOrNull(db.members),
            completedByMember: row.readTableOrNull(completedByMember),
          ),
      ];
    });
  }

  /// Maps joined chore/category rows (from [watchActiveChores] or
  /// [getActiveChores]) to [ChoreWithDetails], resolving each chore's
  /// ordered assignee ids along the way. Shared so the two query methods
  /// can't drift apart on how a row becomes a [ChoreWithDetails].
  Future<List<ChoreWithDetails>> _choreDetailsFromRows(
    List<TypedResult> rows,
  ) async {
    final result = <ChoreWithDetails>[];
    for (final row in rows) {
      final chore = row.readTable(db.chores);
      final category = row.readTableOrNull(db.categories);
      final assigneeIds = await _currentAssigneeIds(chore.id);
      result.add(
        ChoreWithDetails(
          chore: chore,
          assigneeMemberIds: assigneeIds,
          category: category,
        ),
      );
    }
    return result;
  }

  Future<void> _insertAssignees(
    String choreId,
    List<String> assigneeMemberIds,
  ) async {
    for (var i = 0; i < assigneeMemberIds.length; i++) {
      await db
          .into(db.choreAssignees)
          .insert(
            ChoreAssigneesCompanion.insert(
              choreId: choreId,
              memberId: assigneeMemberIds[i],
              position: i,
              syncDirty: syncDirtyOnWrite,
            ),
          );
    }
  }

  Future<List<String>> _currentAssigneeIds(String choreId) async {
    final rows =
        await (db.select(db.choreAssignees)
              ..where((tbl) => tbl.choreId.equals(choreId))
              ..orderBy([(tbl) => OrderingTerm(expression: tbl.position)]))
            .get();
    return [for (final row in rows) row.memberId];
  }

  String _isoNow() => nowUtc().toIso8601String();
}

void _validateAssignees(AssignmentMode mode, List<String> assigneeMemberIds) {
  switch (mode) {
    case AssignmentMode.fixed:
      if (assigneeMemberIds.length != 1) {
        throw ArgumentError.value(
          assigneeMemberIds,
          'assigneeMemberIds',
          'AssignmentMode.fixed requires exactly 1 assignee',
        );
      }
    case AssignmentMode.rotation:
      if (assigneeMemberIds.length < 2) {
        throw ArgumentError.value(
          assigneeMemberIds,
          'assigneeMemberIds',
          'AssignmentMode.rotation requires at least 2 assignees',
        );
      }
    case AssignmentMode.anyone:
      if (assigneeMemberIds.isNotEmpty) {
        throw ArgumentError.value(
          assigneeMemberIds,
          'assigneeMemberIds',
          'AssignmentMode.anyone requires 0 assignees',
        );
      }
  }
}

String _defaultNewId() => const Uuid().v4();

DateTime _defaultNowUtc() => DateTime.now().toUtc();
