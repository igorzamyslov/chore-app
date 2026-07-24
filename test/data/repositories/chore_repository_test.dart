import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

class _FixedClock {
  _FixedClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration duration) => _now = _now.add(duration);
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
  late _FixedClock clock;
  late String householdId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = _FixedClock(DateTime.utc(2026));
    repo = ChoreRepository(db, newId: _IdGen().call, nowUtc: clock.call);
    householdId = await _insertHousehold(db, 'h1');
  });

  tearDown(() => db.close());

  group('createChore validation', () {
    test('fixed requires exactly 1 assignee', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);

      await expectLater(
        repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          assigneeMemberIds: [m1, m2],
        ),
        throwsArgumentError,
      );
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      expect(chore.assignmentMode, AssignmentMode.fixed);
    });

    test('rotation requires 2 or more assignees', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);

      await expectLater(
        repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          assigneeMemberIds: [m1],
        ),
        throwsArgumentError,
      );
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.rotation,
        assigneeMemberIds: [m1, m2],
      );
      expect(chore.assignmentMode, AssignmentMode.rotation);
    });

    test('anyone requires 0 assignees', () async {
      final m1 = await _insertMember(db, 'm1', householdId);

      await expectLater(
        repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          assigneeMemberIds: [m1],
        ),
        throwsArgumentError,
      );
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      expect(chore.assignmentMode, AssignmentMode.anyone);
    });
  });

  group('updateChore', () {
    test('notes/category/recurrence are settable and nullable', () async {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'cat1',
              householdId: householdId,
              kind: CategoryKind.chore,
              name: 'Cat',
              icon: 'icon',
              color: 1,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        notes: 'initial',
        categoryId: 'cat1',
        recurrence: Recurrence.everyNDays(2),
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );

      // Omitted Value params leave fields unchanged.
      await repo.updateChore(chore.id, title: 'Renamed');
      var current = await (db.select(
        db.chores,
      )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
      expect(current.title, 'Renamed');
      expect(current.notes, 'initial');
      expect(current.categoryId, 'cat1');
      expect(current.recurrence?.toJson(), Recurrence.everyNDays(2).toJson());

      // Explicit Value(null) clears nullable fields.
      await repo.updateChore(
        chore.id,
        notes: const Value(null),
        categoryId: const Value(null),
        recurrence: const Value(null),
      );
      current = await (db.select(
        db.chores,
      )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
      expect(current.notes, isNull);
      expect(current.categoryId, isNull);
      expect(current.recurrence, isNull);

      // Value(x) sets a new non-null value.
      await repo.updateChore(chore.id, notes: const Value('updated note'));
      current = await (db.select(
        db.chores,
      )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
      expect(current.notes, 'updated note');
    });

    test('replacing assignees preserves the given order', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final m3 = await _insertMember(db, 'm3', householdId);
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.rotation,
        assigneeMemberIds: [m1, m2],
      );

      await repo.updateChore(
        chore.id,
        assigneeMemberIds: [m3, m1, m2],
      );

      final details = await repo.getChore(chore.id);
      expect(details!.assigneeMemberIds, [m3, m1, m2]);
    });

    test(
      'validates the effective mode/assignees after partial updates',
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final chore = await repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          assigneeMemberIds: [m1],
        );

        // Switching to rotation without supplying a new (2+) assignee list
        // must fail against the *current* (single) assignee list.
        await expectLater(
          repo.updateChore(chore.id, assignmentMode: AssignmentMode.rotation),
          throwsArgumentError,
        );
      },
    );
  });

  group('softDeleteChore', () {
    test(
      'disappears from watchActiveChores; pending occurrence deleted; '
      'closed occurrences retained',
      () async {
        final chore = await repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        final pending = await repo.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 5),
        );
        final closed = await repo.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2025, 12, 20),
        );
        await repo.closeOccurrence(
          closed.id,
          status: OccurrenceStatus.done,
          closedOn: PlainDate(2025, 12, 20),
        );

        final beforeDelete = await repo.watchActiveChores(householdId).first;
        expect(beforeDelete.map((c) => c.chore.id), contains(chore.id));

        await repo.softDeleteChore(chore.id);

        final afterDelete = await repo.watchActiveChores(householdId).first;
        expect(afterDelete.map((c) => c.chore.id), isNot(contains(chore.id)));

        final pendingRow = await (db.select(
          db.choreOccurrences,
        )..where((tbl) => tbl.id.equals(pending.id))).getSingleOrNull();
        expect(pendingRow, isNull);

        final closedRow = await (db.select(
          db.choreOccurrences,
        )..where((tbl) => tbl.id.equals(closed.id))).getSingleOrNull();
        expect(closedRow, isNotNull);
        expect(closedRow!.status, OccurrenceStatus.done);
      },
    );
  });

  group('occurrence primitives', () {
    test('closeOccurrence rejects the pending status', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final occurrence = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 5),
      );

      await expectLater(
        repo.closeOccurrence(
          occurrence.id,
          status: OccurrenceStatus.pending,
          closedOn: PlainDate(2026, 1, 5),
        ),
        throwsArgumentError,
      );
    });

    test(
      'latestClosedOccurrence orders by closed date then due date',
      () async {
        final chore = await repo.createChore(
          householdId: householdId,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        final older = await repo.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 1),
        );
        await repo.closeOccurrence(
          older.id,
          status: OccurrenceStatus.done,
          closedOn: PlainDate(2026, 1, 2),
        );
        final newer = await repo.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 10),
        );
        await repo.closeOccurrence(
          newer.id,
          status: OccurrenceStatus.skipped,
          closedOn: PlainDate(2026, 1, 12),
        );

        final latest = await repo.latestClosedOccurrence(chore.id);
        expect(latest!.id, newer.id);
      },
    );

    test('pendingOccurrenceOf ignores closed occurrences', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final occurrence = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 5),
      );
      await repo.closeOccurrence(
        occurrence.id,
        status: OccurrenceStatus.done,
        closedOn: PlainDate(2026, 1, 5),
      );

      expect(await repo.pendingOccurrenceOf(chore.id), isNull);

      final freshPending = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 2, 5),
      );
      final found = await repo.pendingOccurrenceOf(chore.id);
      expect(found!.id, freshPending.id);
    });

    test('deletePendingOccurrences removes only pending rows', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final closed = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 1),
      );
      await repo.closeOccurrence(
        closed.id,
        status: OccurrenceStatus.done,
        closedOn: PlainDate(2026, 1, 1),
      );
      await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 2, 1),
      );

      await repo.deletePendingOccurrences(chore.id);

      expect(await repo.pendingOccurrenceOf(chore.id), isNull);
      final closedRow = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(closed.id))).getSingleOrNull();
      expect(closedRow, isNotNull);
    });
  });

  group('watchPendingOccurrences', () {
    test(
      'excludes paused/deleted chores and non-pending occurrences; '
      'orders by due date then title; reacts to pausing',
      () async {
        final choreA = await repo.createChore(
          householdId: householdId,
          title: 'B chore',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        await repo.insertOccurrence(
          choreId: choreA.id,
          dueDate: PlainDate(2026, 1, 10),
        );

        final choreB = await repo.createChore(
          householdId: householdId,
          title: 'A chore',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        await repo.insertOccurrence(
          choreId: choreB.id,
          dueDate: PlainDate(2026, 1, 10),
        );

        final pausedChore = await repo.createChore(
          householdId: householdId,
          title: 'Paused chore',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        await repo.insertOccurrence(
          choreId: pausedChore.id,
          dueDate: PlainDate(2026, 1, 1),
        );
        await repo.setPaused(pausedChore.id, paused: true);

        final deletedChore = await repo.createChore(
          householdId: householdId,
          title: 'Deleted chore',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        await repo.insertOccurrence(
          choreId: deletedChore.id,
          dueDate: PlainDate(2026, 1, 1),
        );
        await repo.softDeleteChore(deletedChore.id);

        final closedChore = await repo.createChore(
          householdId: householdId,
          title: 'Closed occurrence chore',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
        );
        final closedOccurrence = await repo.insertOccurrence(
          choreId: closedChore.id,
          dueDate: PlainDate(2026, 1, 1),
        );
        await repo.closeOccurrence(
          closedOccurrence.id,
          status: OccurrenceStatus.done,
          closedOn: PlainDate(2026, 1, 1),
        );

        final emissions = <List<String>>[];
        final sub = repo.watchPendingOccurrences(householdId).listen((rows) {
          emissions.add([for (final r in rows) r.chore.title]);
        });
        addTearDown(sub.cancel);
        await pumpEventQueue();

        expect(emissions.last, ['A chore', 'B chore']);

        await repo.setPaused(choreA.id, paused: true);
        await pumpEventQueue();

        expect(emissions.last, ['A chore']);
      },
    );
  });
}
