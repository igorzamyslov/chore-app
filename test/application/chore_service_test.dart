import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
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

  group('createChore', () {
    test('schedule-anchored due date is the first pinned-weekday slot on or '
        'after startDate', () async {
      final chore = await serviceOn(PlainDate(2026, 7, 22)).createChore(
        householdId: householdId,
        title: 'Take out trash',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(weekdays: {DateTime.saturday}),
      );

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 7, 25));
    });

    test('completion-anchored due date is startDate', () async {
      final chore = await serviceOn(PlainDate(2026, 1, 10)).createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: PlainDate(2026, 1, 10),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          4,
          anchor: RecurrenceAnchor.completion,
        ),
      );

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 10));
    });

    test('one-off due date is startDate', () async {
      final chore = await serviceOn(PlainDate(2026, 3, 1)).createChore(
        householdId: householdId,
        title: 'One-off task',
        startDate: PlainDate(2026, 3, 1),
        assignmentMode: AssignmentMode.anyone,
      );

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 3, 1));
    });

    test('assignee is chosen per assignment mode', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);

      final fixedChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Fixed',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final rotationChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Rotation',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.rotation,
        assigneeMemberIds: [m2, m1],
      );
      final anyoneChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Anyone',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );

      expect(
        (await repo.pendingOccurrenceOf(fixedChore.id))!.assignedMemberId,
        m1,
      );
      expect(
        (await repo.pendingOccurrenceOf(rotationChore.id))!.assignedMemberId,
        m2,
      );
      expect(
        (await repo.pendingOccurrenceOf(anyoneChore.id))!.assignedMemberId,
        isNull,
      );
    });
  });

  group('completeOccurrence / skipOccurrence', () {
    test('done advances a rotation across 4 closes, wrapping around', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final m3 = await _insertMember(db, 'm3', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Rotation',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.rotation,
        recurrence: Recurrence.everyNDays(1),
        assigneeMemberIds: [m1, m2, m3],
      );

      final expectedAssignees = [m2, m3, m1, m2];
      var day = PlainDate(2026, 1, 1);
      for (final expectedAssignee in expectedAssignees) {
        final pending = await repo.pendingOccurrenceOf(chore.id);
        await serviceOn(day).completeOccurrence(
          pending!.id,
          completedBy: pending.assignedMemberId!,
        );
        final next = await repo.pendingOccurrenceOf(chore.id);
        expect(next!.assignedMemberId, expectedAssignee);
        day = day.addDays(1);
      }
    });

    test(
      'skip sticks to the same member; a following done then advances',
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

        final first = await repo.pendingOccurrenceOf(chore.id);
        expect(first!.assignedMemberId, m1);
        await serviceOn(PlainDate(2026, 1, 1)).skipOccurrence(first.id);

        final second = await repo.pendingOccurrenceOf(chore.id);
        expect(second!.assignedMemberId, m1);
        await serviceOn(PlainDate(2026, 1, 2)).skipOccurrence(second.id);

        final third = await repo.pendingOccurrenceOf(chore.id);
        expect(third!.assignedMemberId, m1);
        await serviceOn(
          PlainDate(2026, 1, 3),
        ).completeOccurrence(third.id, completedBy: m1);

        final fourth = await repo.pendingOccurrenceOf(chore.id);
        expect(fourth!.assignedMemberId, m2);
      },
    );

    test('a fixed assignment is unaffected by done or skip', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Fixed',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        recurrence: Recurrence.everyNDays(1),
        assigneeMemberIds: [m1],
      );

      final first = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(first!.id, completedBy: m1);
      final second = await repo.pendingOccurrenceOf(chore.id);
      expect(second!.assignedMemberId, m1);
      await serviceOn(PlainDate(2026, 1, 2)).skipOccurrence(second.id);
      final third = await repo.pendingOccurrenceOf(chore.id);
      expect(third!.assignedMemberId, m1);
    });

    test('an anyone assignment stays null for the next occurrence', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Anyone',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );

      final first = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(first!.id, completedBy: m1);
      final second = await repo.pendingOccurrenceOf(chore.id);
      expect(second!.assignedMemberId, isNull);
    });

    test('completedBy is recorded only for done, not for skip', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final doneChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Done one-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final skippedChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Skipped one-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );

      final donePending = await repo.pendingOccurrenceOf(doneChore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(donePending!.id, completedBy: m1);
      final skippedPending = await repo.pendingOccurrenceOf(skippedChore.id);
      await serviceOn(PlainDate(2026, 1, 1)).skipOccurrence(skippedPending!.id);

      final doneClosed = await repo.latestClosedOccurrence(doneChore.id);
      expect(doneClosed!.status, OccurrenceStatus.done);
      expect(doneClosed.completedBy, m1);

      final skippedClosed = await repo.latestClosedOccurrence(skippedChore.id);
      expect(skippedClosed!.status, OccurrenceStatus.skipped);
      expect(skippedClosed.completedBy, isNull);
    });

    test('a one-off chore gets no next occurrence after completion', () async {
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

      expect(await repo.pendingOccurrenceOf(chore.id), isNull);
      final closed = await repo.latestClosedOccurrence(chore.id);
      expect(closed!.status, OccurrenceStatus.done);
    });

    test('closing a non-pending occurrence throws StateError', () async {
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

      await expectLater(
        serviceOn(
          PlainDate(2026, 1, 1),
        ).completeOccurrence(pending.id, completedBy: m1),
        throwsStateError,
      );
      await expectLater(
        serviceOn(PlainDate(2026, 1, 1)).skipOccurrence(pending.id),
        throwsStateError,
      );
      await expectLater(
        serviceOn(PlainDate(2026, 1, 1)).skipOccurrence('no-such-occurrence'),
        throwsStateError,
      );
    });
  });

  group('late completion', () {
    test('a schedule-anchored weekly chore completed 16 days late skips the '
        'missed slots', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Weekly',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 1));

      // 16 days after the 2026-01-01 due date: 2026-01-17. The regular
      // 01-08 and 01-15 slots were missed and are skipped entirely.
      await serviceOn(
        PlainDate(2026, 1, 17),
      ).completeOccurrence(pending.id, completedBy: m1);

      final next = await repo.pendingOccurrenceOf(chore.id);
      expect(next!.dueDate, PlainDate(2026, 1, 22));
    });
  });

  group('catchUpOverdue', () {
    test(
      '3 slots behind: closes as missed and reinserts at the latest slot '
      '<= today, preserving the assignee; a same-household future-due '
      'chore is left untouched; a second call the same day is a no-op',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final m2 = await _insertMember(db, 'm2', householdId);
        final overdueChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Daily',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [m1, m2],
        );
        final futureChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Far ahead',
          startDate: PlainDate(2026, 1, 20),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(1),
        );

        await serviceOn(PlainDate(2026, 1, 4)).catchUpOverdue(householdId);

        final pending = await repo.pendingOccurrenceOf(overdueChore.id);
        expect(pending!.dueDate, PlainDate(2026, 1, 4));
        expect(pending.assignedMemberId, m1);

        final missed = await repo.latestClosedOccurrence(overdueChore.id);
        expect(missed!.status, OccurrenceStatus.missed);
        expect(missed.dueDate, PlainDate(2026, 1, 1));
        expect(missed.closedOn, PlainDate(2026, 1, 4));

        final futurePending = await repo.pendingOccurrenceOf(futureChore.id);
        expect(futurePending!.dueDate, PlainDate(2026, 1, 20));
        expect(await repo.latestClosedOccurrence(futureChore.id), isNull);

        // Idempotent: a second call the same day changes nothing.
        await serviceOn(PlainDate(2026, 1, 4)).catchUpOverdue(householdId);

        final pendingAfter = await repo.pendingOccurrenceOf(overdueChore.id);
        expect(pendingAfter!.id, pending.id);
        expect(pendingAfter.dueDate, PlainDate(2026, 1, 4));
        expect(pendingAfter.assignedMemberId, m1);
        final missedAfter = await repo.latestClosedOccurrence(overdueChore.id);
        expect(missedAfter!.id, missed.id);
      },
    );

    test('a completion-anchored chore is never auto-missed', () async {
      final chore = await serviceOn(PlainDate(2025, 12, 25)).createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: PlainDate(2025, 12, 25),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          4,
          anchor: RecurrenceAnchor.completion,
        ),
      );

      // 10 days overdue.
      await serviceOn(PlainDate(2026, 1, 4)).catchUpOverdue(householdId);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2025, 12, 25));
      expect(pending.status, OccurrenceStatus.pending);
      expect(await repo.latestClosedOccurrence(chore.id), isNull);
    });

    test('a paused chore is left untouched even if its pending occurrence is '
        'overdue', () async {
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Paused daily',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );
      await repo.setPaused(chore.id, paused: true);

      await serviceOn(PlainDate(2026, 1, 4)).catchUpOverdue(householdId);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 1));
      expect(pending.status, OccurrenceStatus.pending);
      expect(await repo.latestClosedOccurrence(chore.id), isNull);
    });
  });

  group('pauseChore / unpauseChore', () {
    test(
      'pausing deletes the pending occurrence; pausing again is a no-op',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'Fixed daily',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          recurrence: Recurrence.everyNDays(1),
          assigneeMemberIds: [m1],
        );

        await serviceOn(PlainDate(2026, 1, 2)).pauseChore(chore.id);

        var details = await repo.getChore(chore.id);
        expect(details!.chore.pausedAt, isNotNull);
        expect(await repo.pendingOccurrenceOf(chore.id), isNull);

        await serviceOn(PlainDate(2026, 1, 3)).pauseChore(chore.id);
        details = await repo.getChore(chore.id);
        expect(details!.chore.pausedAt, isNotNull);
        expect(await repo.pendingOccurrenceOf(chore.id), isNull);
      },
    );

    test('unpausing a schedule-anchored chore resumes at the next slot >= '
        'today; unpausing again is a no-op', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Weekly-ish',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        recurrence: Recurrence.everyNDays(7),
        assigneeMemberIds: [m1],
      );
      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(chore.id);

      await serviceOn(PlainDate(2026, 1, 10)).unpauseChore(chore.id);

      final details = await repo.getChore(chore.id);
      expect(details!.chore.pausedAt, isNull);
      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 15));
      expect(pending.assignedMemberId, m1);

      await serviceOn(PlainDate(2026, 1, 11)).unpauseChore(chore.id);
      final pendingAfter = await repo.pendingOccurrenceOf(chore.id);
      expect(pendingAfter!.id, pending.id);
    });

    test('unpausing a completion-anchored chore resumes due today', () async {
      final chore = await serviceOn(PlainDate(2025, 12, 25)).createChore(
        householdId: householdId,
        title: 'Plants',
        startDate: PlainDate(2025, 12, 25),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          4,
          anchor: RecurrenceAnchor.completion,
        ),
      );
      await serviceOn(PlainDate(2025, 12, 26)).pauseChore(chore.id);

      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 5));
      expect(pending.assignedMemberId, isNull);
    });

    test('unpausing a one-off chore resumes at startDate if still ahead, '
        'else today', () async {
      final futureChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Future one-off',
        startDate: PlainDate(2026, 1, 10),
        assignmentMode: AssignmentMode.anyone,
      );
      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(futureChore.id);
      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(futureChore.id);
      final futurePending = await repo.pendingOccurrenceOf(futureChore.id);
      expect(futurePending!.dueDate, PlainDate(2026, 1, 10));

      final pastChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Past one-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(pastChore.id);
      await serviceOn(PlainDate(2026, 1, 20)).unpauseChore(pastChore.id);
      final pastPending = await repo.pendingOccurrenceOf(pastChore.id);
      expect(pastPending!.dueDate, PlainDate(2026, 1, 20));
    });

    test('rotation continuity survives a pause/unpause round trip', () async {
      final memberA = await _insertMember(db, 'a', householdId);
      final memberB = await _insertMember(db, 'b', householdId);
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

      // A completes -> rotation auto-advances to B's pending occurrence.
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(first.id, completedBy: memberA);
      expect(
        (await repo.pendingOccurrenceOf(chore.id))!.assignedMemberId,
        memberB,
      );

      // Pausing removes that pending occurrence, but not the closed history.
      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(chore.id);
      expect(await repo.pendingOccurrenceOf(chore.id), isNull);

      // Unpausing must continue the rotation from history (A), landing on B
      // again -- not restart from position 0.
      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(chore.id);
      final resumed = await repo.pendingOccurrenceOf(chore.id);
      expect(resumed!.assignedMemberId, memberB);
    });

    test(
      'pauseChore/unpauseChore throw for a nonexistent or deleted chore',
      () async {
        await expectLater(
          serviceOn(PlainDate(2026, 1, 1)).pauseChore('missing'),
          throwsStateError,
        );
        await expectLater(
          serviceOn(PlainDate(2026, 1, 1)).unpauseChore('missing'),
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
          serviceOn(PlainDate(2026, 1, 1)).pauseChore(chore.id),
          throwsStateError,
        );
        await expectLater(
          serviceOn(PlainDate(2026, 1, 1)).unpauseChore(chore.id),
          throwsStateError,
        );
      },
    );
  });

  group('unpauseChore does not resurrect an already-closed slot', () {
    test('regression: a weekly schedule-anchored chore due today, completed, '
        'paused, then unpaused the same day gets no pending occurrence due '
        'today; the pending occurrence sits at the next weekly slot, and the '
        'completed occurrence is untouched', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      // 2026-01-05 is a Monday.
      final chore = await serviceOn(PlainDate(2026, 1, 5)).createChore(
        householdId: householdId,
        title: 'Weekly',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );
      final today = await repo.pendingOccurrenceOf(chore.id);
      expect(today!.dueDate, PlainDate(2026, 1, 5));

      await serviceOn(
        PlainDate(2026, 1, 5),
      ).completeOccurrence(today.id, completedBy: m1);
      await serviceOn(PlainDate(2026, 1, 5)).pauseChore(chore.id);
      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 12));

      final closed = await repo.latestClosedOccurrence(chore.id);
      expect(closed!.id, today.id);
      expect(closed.status, OccurrenceStatus.done);
      expect(closed.dueDate, PlainDate(2026, 1, 5));
      expect(closed.closedOn, PlainDate(2026, 1, 5));
    });

    test('same as the completion regression, but with skipOccurrence: "skip '
        'sticks" applies here too', () async {
      final chore = await serviceOn(PlainDate(2026, 1, 5)).createChore(
        householdId: householdId,
        title: 'Weekly',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(),
      );
      final today = await repo.pendingOccurrenceOf(chore.id);

      await serviceOn(PlainDate(2026, 1, 5)).skipOccurrence(today!.id);
      await serviceOn(PlainDate(2026, 1, 5)).pauseChore(chore.id);
      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 12));

      final closed = await repo.latestClosedOccurrence(chore.id);
      expect(closed!.id, today.id);
      expect(closed.status, OccurrenceStatus.skipped);
    });

    test('a weekly chore pinned to Monday, completed on that Monday, paused, '
        'then unpaused the same day resumes at the next Monday', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      // 2026-01-01 is a Thursday; the first pinned Monday on/after it is
      // 2026-01-05.
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Weekly, pinned Monday',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(weekdays: {DateTime.monday}),
      );
      final firstMonday = await repo.pendingOccurrenceOf(chore.id);
      expect(firstMonday!.dueDate, PlainDate(2026, 1, 5));

      await serviceOn(
        PlainDate(2026, 1, 5),
      ).completeOccurrence(firstMonday.id, completedBy: m1);
      await serviceOn(PlainDate(2026, 1, 5)).pauseChore(chore.id);
      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 12));
    });

    test('schedule anchor whose latest closed slot is weeks in the past: '
        'unpausing today lands on the first slot >= today, never an overdue '
        'one', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Weekly-ish',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(7),
      );
      final first = await repo.pendingOccurrenceOf(chore.id);
      expect(first!.dueDate, PlainDate(2026, 1, 1));
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(first.id, completedBy: m1);

      // The chore is paused long after completion, then unpaused weeks
      // later still; the closed slot (2026-01-01) is far in the past.
      await serviceOn(PlainDate(2026, 1, 9)).pauseChore(chore.id);
      await serviceOn(PlainDate(2026, 1, 30)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      // Series from 2026-01-01 every 7 days: ...01-22, 01-29, 02-05... The
      // first slot on/after 2026-01-30 is 2026-02-05 -- not an overdue
      // slot before today.
      expect(pending!.dueDate, PlainDate(2026, 2, 5));
      expect(pending.dueDate.isOnOrAfter(PlainDate(2026, 1, 30)), isTrue);
    });

    test('completion anchor, every 3 days: completed today, paused, then '
        'unpaused the same day resumes due today + 3', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          3,
          anchor: RecurrenceAnchor.completion,
        ),
      );
      final first = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(first!.id, completedBy: m1);
      await serviceOn(PlainDate(2026, 1, 1)).pauseChore(chore.id);
      await serviceOn(PlainDate(2026, 1, 1)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 4));
    });

    test('completion anchor whose latest closedOn is 5 days ago (so the '
        'completion-based candidate, 2 days ago, is itself in the past): '
        'unpausing today resumes due today', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(
          3,
          anchor: RecurrenceAnchor.completion,
        ),
      );
      final first = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(first!.id, completedBy: m1);
      await serviceOn(PlainDate(2026, 1, 1)).pauseChore(chore.id);

      // closedOn was 2026-01-01; unpausing 5 days later on 2026-01-06
      // makes the completion candidate (2026-01-04) 2 days in the past.
      await serviceOn(PlainDate(2026, 1, 6)).unpauseChore(chore.id);

      final pending = await repo.pendingOccurrenceOf(chore.id);
      expect(pending!.dueDate, PlainDate(2026, 1, 6));
    });

    test(
      'a one-off chore, completed then paused, stays closed through an '
      'unpause: the chore itself is unpaused but no occurrence resurrects',
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
        await serviceOn(PlainDate(2026, 1, 2)).pauseChore(chore.id);

        await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(chore.id);

        final details = await repo.getChore(chore.id);
        expect(details!.chore.pausedAt, isNull);
        expect(await repo.pendingOccurrenceOf(chore.id), isNull);
        final closed = await repo.latestClosedOccurrence(chore.id);
        expect(closed!.id, pending.id);
        expect(closed.status, OccurrenceStatus.done);
      },
    );

    test('a one-off chore never closed still resumes at startDate if still '
        'ahead, else today', () async {
      final futureChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Future one-off',
        startDate: PlainDate(2026, 1, 10),
        assignmentMode: AssignmentMode.anyone,
      );
      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(futureChore.id);
      await serviceOn(PlainDate(2026, 1, 5)).unpauseChore(futureChore.id);
      final futurePending = await repo.pendingOccurrenceOf(futureChore.id);
      expect(futurePending!.dueDate, PlainDate(2026, 1, 10));

      final pastChore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'Past one-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(pastChore.id);
      await serviceOn(PlainDate(2026, 1, 20)).unpauseChore(pastChore.id);
      final pastPending = await repo.pendingOccurrenceOf(pastChore.id);
      expect(pastPending!.dueDate, PlainDate(2026, 1, 20));
    });
  });

  group('reopenOccurrence', () {
    test('reopening a completed recurring occurrence the same day restores it '
        'to pending (clearing closedOn/completedBy, keeping the assignee) and '
        'deletes the auto-created next occurrence', () async {
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
      final closed = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(closed!.id, completedBy: m1);

      // Rotation advanced to m2's fresh pending occurrence.
      final rotated = await repo.pendingOccurrenceOf(chore.id);
      expect(rotated!.assignedMemberId, m2);

      await serviceOn(PlainDate(2026, 1, 1)).reopenOccurrence(closed.id);

      // The rotated-to occurrence is gone; the original is pending again,
      // for the original (m1) assignee, with its close fields cleared.
      final restored = await repo.pendingOccurrenceOf(chore.id);
      expect(restored!.id, closed.id);
      expect(restored.assignedMemberId, m1);
      expect(restored.status, OccurrenceStatus.pending);
      expect(restored.closedOn, isNull);
      expect(restored.completedBy, isNull);

      final rotatedRow = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(rotated.id))).getSingleOrNull();
      expect(rotatedRow, isNull);
    });

    test('reopening a skipped one-off occurrence restores it, with no next '
        'occurrence to delete', () async {
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'One-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final closed = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(PlainDate(2026, 1, 1)).skipOccurrence(closed!.id);
      expect(await repo.pendingOccurrenceOf(chore.id), isNull);

      await serviceOn(PlainDate(2026, 1, 1)).reopenOccurrence(closed.id);

      final restored = await repo.pendingOccurrenceOf(chore.id);
      expect(restored!.id, closed.id);
      expect(restored.status, OccurrenceStatus.pending);
      expect(restored.closedOn, isNull);
    });

    test('throws StateError for an occurrence that is still pending', () async {
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'One-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = await repo.pendingOccurrenceOf(chore.id);

      await expectLater(
        serviceOn(PlainDate(2026, 1, 1)).reopenOccurrence(pending!.id),
        throwsStateError,
      );
    });

    test(
      'throws StateError for an occurrence closed on an earlier day (the '
      'catch-up day-boundary case): closed yesterday, reopened today',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: 'One-off',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        final closed = await repo.pendingOccurrenceOf(chore.id);
        await serviceOn(
          PlainDate(2026, 1, 1),
        ).completeOccurrence(closed!.id, completedBy: m1);

        await expectLater(
          serviceOn(PlainDate(2026, 1, 2)).reopenOccurrence(closed.id),
          throwsStateError,
        );
      },
    );

    test('throws StateError for a nonexistent occurrence', () async {
      await expectLater(
        serviceOn(PlainDate(2026, 1, 1)).reopenOccurrence('no-such-id'),
        throwsStateError,
      );
    });

    test('throws StateError when the chore has been deleted', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: 'One-off',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final closed = await repo.pendingOccurrenceOf(chore.id);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(closed!.id, completedBy: m1);
      await repo.softDeleteChore(chore.id);

      await expectLater(
        serviceOn(PlainDate(2026, 1, 1)).reopenOccurrence(closed.id),
        throwsStateError,
      );
    });
  });

  group('LIFO reopen (field feedback B2)', () {
    // A completion-anchored, rotation-assigned chore due TODAY. Completing
    // it (A) creates B due today+3 (completion anchor, done -> closedOn +
    // interval). Completing B TODAY too (early — B isn't due for 3 more
    // days) creates C, ALSO due today+3 (done always anchors at closedOn,
    // per the amended B3 contract — completing early yields the same
    // successor date). So closed-today now holds A (due today) and B (due
    // today+3): B is the latest by due date.
    Future<
      (
        Chore chore,
        String m1,
        String m2,
        ChoreOccurrence closedA,
        ChoreOccurrence closedB,
      )
    >
    setUpTwoCloses(PlainDate today) async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: today,
        assignmentMode: AssignmentMode.rotation,
        recurrence: Recurrence.everyNDays(
          3,
          anchor: RecurrenceAnchor.completion,
        ),
        assigneeMemberIds: [m1, m2],
      );
      final a = await repo.pendingOccurrenceOf(chore.id);
      expect(a!.assignedMemberId, m1);
      await serviceOn(today).completeOccurrence(a.id, completedBy: m1);

      final b = await repo.pendingOccurrenceOf(chore.id);
      expect(b!.dueDate, today.addDays(3));
      expect(b.assignedMemberId, m2);
      await serviceOn(today).completeOccurrence(b.id, completedBy: m2);

      final c = await repo.pendingOccurrenceOf(chore.id);
      expect(c!.dueDate, today.addDays(3));

      final closedA = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(a.id))).getSingle();
      final closedB = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(b.id))).getSingle();
      return (chore, m1, m2, closedA, closedB);
    }

    test('unwinding newest-first (reopen B, then reopen A) restores exactly '
        'one pending occurrence due today with the original assignee, and no '
        'occurrence is lost along the way', () async {
      final today = PlainDate(2026, 1, 1);
      final (chore, m1, m2, closedA, closedB) = await setUpTwoCloses(today);

      // Reopen the LATEST (B, due today+3): deletes pending C, restores B
      // to pending due today+3, keeping its own (m2) assignee.
      await serviceOn(today).reopenOccurrence(closedB.id);
      final afterFirstReopen = await repo.pendingOccurrenceOf(chore.id);
      expect(afterFirstReopen!.id, closedB.id);
      expect(afterFirstReopen.dueDate, today.addDays(3));
      expect(afterFirstReopen.assignedMemberId, m2);

      // A is now the latest closed-today row (the only one left).
      // Reopen it: deletes pending B, restores A to pending due today,
      // keeping its own (m1) assignee.
      await serviceOn(today).reopenOccurrence(closedA.id);
      final afterSecondReopen = await repo.pendingOccurrenceOf(chore.id);
      expect(afterSecondReopen!.id, closedA.id);
      expect(afterSecondReopen.dueDate, today);
      expect(afterSecondReopen.assignedMemberId, m1);
      expect(afterSecondReopen.status, OccurrenceStatus.pending);
      expect(afterSecondReopen.closedOn, isNull);

      // Exactly back to where it started: ONE occurrence total for this
      // chore (A, pending, due today) -- B and C both fully unwound, no
      // occurrence lost or duplicated along the way.
      final allOccurrences = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.choreId.equals(chore.id))).get();
      expect(allOccurrences, hasLength(1));
      expect(allOccurrences.single.id, closedA.id);
    });

    test('reopening the NON-latest closed-today row first throws StateError '
        'and changes nothing', () async {
      final today = PlainDate(2026, 1, 1);
      final (chore, _, _, closedA, closedB) = await setUpTwoCloses(today);

      await expectLater(
        serviceOn(today).reopenOccurrence(closedA.id),
        throwsStateError,
      );

      // Untouched: C is still the sole pending occurrence, and both A and
      // B are still closed exactly as they were.
      final stillPending = await repo.pendingOccurrenceOf(chore.id);
      expect(stillPending!.dueDate, today.addDays(3));
      expect(stillPending.id, isNot(closedB.id));

      final aRow = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(closedA.id))).getSingle();
      expect(aRow.status, OccurrenceStatus.done);
      expect(aRow.closedOn, today);

      final bRow = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(closedB.id))).getSingle();
      expect(bRow.status, OccurrenceStatus.done);
      expect(bRow.closedOn, today);

      final allOccurrences = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.choreId.equals(chore.id))).get();
      expect(allOccurrences, hasLength(3));
    });
  });

  group('read-after-write consistency', () {
    test('watchPendingOccurrences and watchActiveChores reflect state right '
        'after completeOccurrence', () async {
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
      final pending = await repo.pendingOccurrenceOf(chore.id);

      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(pending!.id, completedBy: m1);

      final rows = await repo.watchPendingOccurrences(householdId).first;
      expect(rows, hasLength(1));
      expect(rows.single.chore.id, chore.id);
      expect(rows.single.occurrence.dueDate, PlainDate(2026, 1, 2));
      expect(rows.single.assignedMember?.id, m2);

      final activeChores = await repo.watchActiveChores(householdId).first;
      final details = activeChores.singleWhere((c) => c.chore.id == chore.id);
      expect(details.assigneeMemberIds, [m1, m2]);
    });
  });
}
