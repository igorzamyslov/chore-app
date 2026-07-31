/// Tests for `ChoreService.updateChore`'s occurrence-regeneration rule
/// (spec `docs/specs/polish-round-1.md` C2, folded into
/// `docs/specs/occurrence-lifecycle.md` §2): editing a chore's recurrence
/// and/or start date regenerates its pending occurrence using THE SAME
/// two-floors due-date rule as `unpauseChore`.
///
/// Same conventions as `test/application/chore_service_test.dart`: a real
/// in-memory [AppDatabase] (no mocks), a fixed injected [Clock] per
/// scenario via the `serviceOn` helper, counter ids.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

Future<String> _insertHousehold(AppDatabase db, String id) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  return id;
}

Future<String> _insertMember(
  AppDatabase db,
  String id,
  String householdId,
) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          householdId: householdId,
          name: 'Member $id',
          color: 0xFF000000,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  return id;
}

void main() {
  late AppDatabase db;
  late ChoreRepository repo;
  late String householdId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChoreRepository(
      db,
      newId: _IdGen().call,
      nowUtc: () => DateTime.utc(2026),
    );
    householdId = await _insertHousehold(db, 'h1');
  });

  tearDown(() => db.close());

  ChoreService serviceOn(PlainDate today) {
    return ChoreService(
      database: db,
      chores: repo,
      clock: Clock.fixed(DateTime.utc(today.year, today.month, today.day)),
    );
  }

  group('changed recurrence', () {
    test(
      "regenerates the pending occurrence at the new rule's due date, "
      'deleting (not closing) the old one',
      () async {
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Weekly-ish',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(7),
        );
        final before = await repo.pendingOccurrenceOf(chore.id);
        expect(before!.dueDate, PlainDate(2026, 1, 1));

        await serviceOn(PlainDate(2026, 1, 3)).updateChore(
          chore.id,
          recurrence: Value(Recurrence.everyNDays(3)),
        );

        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.id, isNot(before.id));
        // Every-3-days series from 2026-01-01: 01-01, 01-04, 01-07... The
        // first slot >= today (01-03, since nothing was ever closed) is
        // 01-04.
        expect(pending.dueDate, PlainDate(2026, 1, 4));
        // Deleted, not closed: no missed/done/skipped history was created.
        expect(await repo.latestClosedOccurrence(chore.id), isNull);
      },
    );

    test(
      'converting a one-off into a recurring chore inserts a fresh '
      'occurrence per the new rule',
      () async {
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'One-off turned weekly',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );

        await serviceOn(PlainDate(2026, 1, 2)).updateChore(
          chore.id,
          recurrence: Value(Recurrence.everyNDays(5)),
        );

        final pending = await repo.pendingOccurrenceOf(chore.id);
        // Every-5-days series from 2026-01-01: 01-01, 01-06, 01-11... The
        // first slot >= today (01-02) is 01-06.
        expect(pending!.dueDate, PlainDate(2026, 1, 6));
      },
    );
  });

  group('changed start date', () {
    test(
      "regenerates a one-off's pending occurrence at the new date",
      () async {
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Future one-off',
          startDate: PlainDate(2026, 1, 10),
          assignmentMode: AssignmentMode.anyone,
        );
        final before = await repo.pendingOccurrenceOf(chore.id);
        expect(before!.dueDate, PlainDate(2026, 1, 10));

        await serviceOn(
          PlainDate(2026, 1, 3),
        ).updateChore(chore.id, startDate: PlainDate(2026, 1, 20));

        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.id, isNot(before.id));
        expect(pending.dueDate, PlainDate(2026, 1, 20));
      },
    );

    test(
      'a new start date already in the past regenerates due today, not '
      'the past date',
      () async {
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Future one-off',
          startDate: PlainDate(2026, 1, 10),
          assignmentMode: AssignmentMode.anyone,
        );

        await serviceOn(
          PlainDate(2026, 1, 15),
        ).updateChore(chore.id, startDate: PlainDate(2026, 1, 5));

        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 15));
      },
    );
  });

  group('unchanged edit', () {
    test(
      'an edit touching neither recurrence nor startDate leaves the '
      'pending occurrence and its assignee untouched',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final m2 = await _insertMember(db, 'm2', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Rotation',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [m1, m2],
        );
        final before = await repo.pendingOccurrenceOf(chore.id);

        await serviceOn(
          PlainDate(2026, 1, 5),
        ).updateChore(chore.id, title: 'Rotation (renamed)');

        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.id, before!.id);
        expect(pending.dueDate, before.dueDate);
        expect(pending.assignedMemberId, before.assignedMemberId);
        final details = await repo.getChore(chore.id);
        expect(details!.chore.title, 'Rotation (renamed)');
      },
    );

    test(
      'changing assignmentMode/assignees alone (no recurrence/startDate '
      'change) still leaves the pending occurrence untouched',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final m2 = await _insertMember(db, 'm2', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Fixed',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [m1],
        );
        final before = await repo.pendingOccurrenceOf(chore.id);
        expect(before!.assignedMemberId, m1);

        await serviceOn(PlainDate(2026, 1, 5)).updateChore(
          chore.id,
          assignmentMode: AssignmentMode.fixed,
          assigneeMemberIds: [m2],
        );

        final pending = await repo.pendingOccurrenceOf(chore.id);
        expect(pending!.id, before.id);
        // The occurrence itself is untouched even though the chore's
        // assignee list changed underneath it.
        expect(pending.assignedMemberId, m1);
        final details = await repo.getChore(chore.id);
        expect(details!.assigneeMemberIds, [m2]);
      },
    );
  });

  group('closed one-off', () {
    test(
      "editing a completed one-off's start date updates the row but "
      'inserts no occurrence',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'One-off',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        final pending = await repo.pendingOccurrenceOf(chore.id);
        await serviceOn(
          PlainDate(2026, 1, 1),
        ).completeOccurrence(pending!.id, completedBy: m1);

        await serviceOn(
          PlainDate(2026, 1, 10),
        ).updateChore(chore.id, startDate: PlainDate(2026, 1, 15));

        expect(await repo.pendingOccurrenceOf(chore.id), isNull);
        final details = await repo.getChore(chore.id);
        expect(details!.chore.startDate, PlainDate(2026, 1, 15));
        final closed = await repo.latestClosedOccurrence(chore.id);
        expect(closed!.id, pending.id);
        expect(closed.status, OccurrenceStatus.done);
      },
    );
  });

  group('completion anchor', () {
    test(
      'a completion-anchored edit recomputes from latestClosedOccurrence',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Water plants',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(
            4,
            anchor: RecurrenceAnchor.completion,
          ),
        );
        final first = await repo.pendingOccurrenceOf(chore.id);
        // Completing on time auto-advances to 2026-01-05 (interval 4).
        await serviceOn(
          PlainDate(2026, 1, 1),
        ).completeOccurrence(first!.id, completedBy: m1);
        expect(
          (await repo.pendingOccurrenceOf(chore.id))!.dueDate,
          PlainDate(2026, 1, 5),
        );

        // Widen the interval to 10 days the next day.
        await serviceOn(PlainDate(2026, 1, 2)).updateChore(
          chore.id,
          recurrence: Value(
            Recurrence.everyNDays(10, anchor: RecurrenceAnchor.completion),
          ),
        );

        final pending = await repo.pendingOccurrenceOf(chore.id);
        // nextAfterCompletion(everyNDays(10), closedOn: 2026-01-01) =
        // 2026-01-11, which is after today (2026-01-02).
        expect(pending!.dueDate, PlainDate(2026, 1, 11));
      },
    );
  });

  group('weekday-pinned', () {
    test(
      'changing the pinned weekday recalculates the due date against the '
      'new pin',
      () async {
        // 2026-01-01 is a Thursday.
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Weekly, pinned Monday',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.weekly(weekdays: {DateTime.monday}),
        );
        final before = await repo.pendingOccurrenceOf(chore.id);
        expect(before!.dueDate, PlainDate(2026, 1, 5)); // first Monday.

        await serviceOn(PlainDate(2026, 1, 2)).updateChore(
          chore.id,
          recurrence: Value(
            Recurrence.weekly(weekdays: {DateTime.wednesday}),
          ),
        );

        final pending = await repo.pendingOccurrenceOf(chore.id);
        // First Wednesday on/after 2026-01-02 is 2026-01-07.
        expect(pending!.dueDate, PlainDate(2026, 1, 7));
      },
    );
  });

  group('assignee re-resolution mirrors unpause', () {
    test(
      "rotation continues from the latest closed occurrence's assignee, "
      'even against a freshly-changed assignee list',
      () async {
        final memberA = await _insertMember(db, 'a', householdId);
        final memberB = await _insertMember(db, 'b', householdId);
        final memberC = await _insertMember(db, 'c', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Rotation',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [memberA, memberB],
        );
        final first = await repo.pendingOccurrenceOf(chore.id);
        expect(first!.assignedMemberId, memberA);
        // A completes -> pending advances to B.
        await serviceOn(
          PlainDate(2026, 1, 1),
        ).completeOccurrence(first.id, completedBy: memberA);

        // Edit the recurrence and the assignee list (adding C) in the same
        // call.
        await serviceOn(PlainDate(2026, 1, 2)).updateChore(
          chore.id,
          recurrence: Value(Recurrence.everyNDays(2)),
          assigneeMemberIds: [memberA, memberB, memberC],
        );

        final pending = await repo.pendingOccurrenceOf(chore.id);
        // Continues from history (A was last done) against the new order
        // -> B.
        expect(pending!.assignedMemberId, memberB);
      },
    );
  });

  group('paused chore', () {
    test(
      "editing a paused chore's recurrence updates the row but inserts no "
      'occurrence; unpausing afterward uses the updated rule',
      () async {
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Weekly-ish',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(7),
        );
        await serviceOn(PlainDate(2026, 1, 2)).pauseChore(chore.id);
        expect(await repo.pendingOccurrenceOf(chore.id), isNull);

        await serviceOn(PlainDate(2026, 1, 3)).updateChore(
          chore.id,
          recurrence: Value(Recurrence.everyNDays(3)),
        );

        expect(await repo.pendingOccurrenceOf(chore.id), isNull);
        final details = await repo.getChore(chore.id);
        expect(details!.chore.pausedAt, isNotNull);

        await serviceOn(PlainDate(2026, 1, 10)).unpauseChore(chore.id);
        final pending = await repo.pendingOccurrenceOf(chore.id);
        // every-3-days series from 2026-01-01: ...01-01, 01-04, 01-07,
        // 01-10... first slot >= today (01-10) is 01-10.
        expect(pending!.dueDate, PlainDate(2026, 1, 10));
      },
    );
  });

  group('errors', () {
    test(
      'updateChore throws for a nonexistent or soft-deleted chore',
      () async {
        await expectLater(
          serviceOn(PlainDate(2026, 1, 1)).updateChore('missing', title: 'x'),
          throwsStateError,
        );

        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Deleted',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        await repo.softDeleteChore(chore.id);

        await expectLater(
          serviceOn(PlainDate(2026, 1, 1)).updateChore(chore.id, title: 'x'),
          throwsStateError,
        );
      },
    );
  });
}
