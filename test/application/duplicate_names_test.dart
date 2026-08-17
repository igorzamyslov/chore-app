import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Service-level verification suite for `docs/next-session-plan.md` #4:
/// duplicate chore names are allowed by design (user decision 2026-07-24,
/// no prohibition/warning) -- every operation must target the row by id,
/// never by title, so two identically-titled chores never cross-affect
/// each other.
///
/// Kept in its own file (separate from `chore_service_test.dart`) so the two
/// suites don't collide while both are being worked on.
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

Future<String> _insertCategory(
  AppDatabase db,
  String id,
  String householdId, {
  required String name,
}) async {
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          householdId: householdId,
          kind: CategoryKind.chore,
          name: name,
          icon: 'label',
          color: 0xFF000000,
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

  const duplicateTitle = 'Water plants';

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

  group('two chores sharing a title', () {
    test('completing one closes only that occurrence; the sibling stays '
        'pending, and the closed-today view has exactly one entry with the '
        'right completer', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final bedroom = await _insertCategory(
        db,
        'bedroom',
        householdId,
        name: 'Bedroom',
      );
      final balcony = await _insertCategory(
        db,
        'balcony',
        householdId,
        name: 'Balcony',
      );

      final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
        categoryId: bedroom,
      );
      final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m2],
        categoryId: balcony,
      );
      expect(choreA.title, choreB.title);
      expect(choreA.id, isNot(choreB.id));

      final pendingA = await repo.pendingOccurrenceOf(choreA.id);
      final pendingB = await repo.pendingOccurrenceOf(choreB.id);

      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(pendingA!.id, completedBy: m1);

      // The sibling is completely untouched: same occurrence id, still
      // pending.
      final stillPendingB = await repo.pendingOccurrenceOf(choreB.id);
      expect(stillPendingB!.id, pendingB!.id);
      expect(stillPendingB.status, OccurrenceStatus.pending);

      // Only A closed.
      expect(await repo.pendingOccurrenceOf(choreA.id), isNull);
      final closedA = await repo.latestClosedOccurrence(choreA.id);
      expect(closedA!.status, OccurrenceStatus.done);
      expect(closedA.completedBy, m1);
      expect(await repo.latestClosedOccurrence(choreB.id), isNull);

      // The Done-today view (`watchClosedOnDate`) has exactly one entry,
      // attributed to the right chore/completer -- not the sibling's.
      final closedToday = await repo
          .watchClosedOnDate(householdId, PlainDate(2026, 1, 1))
          .first;
      expect(closedToday, hasLength(1));
      expect(closedToday.single.chore.id, choreA.id);
      expect(closedToday.single.category?.id, bedroom);
      expect(closedToday.single.completedByMember?.id, m1);
    });

    test('skipping one advances/closes only that occurrence; the sibling '
        'stays pending and untouched', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m2],
      );
      final pendingA = await repo.pendingOccurrenceOf(choreA.id);
      final pendingB = await repo.pendingOccurrenceOf(choreB.id);

      await serviceOn(PlainDate(2026, 1, 1)).skipOccurrence(pendingA!.id);

      // One-off + skipped: A has no pending occurrence and is marked
      // skipped; B is completely unaffected.
      expect(await repo.pendingOccurrenceOf(choreA.id), isNull);
      final closedA = await repo.latestClosedOccurrence(choreA.id);
      expect(closedA!.status, OccurrenceStatus.skipped);

      final stillPendingB = await repo.pendingOccurrenceOf(choreB.id);
      expect(stillPendingB!.id, pendingB!.id);
      expect(stillPendingB.status, OccurrenceStatus.pending);
      expect(await repo.latestClosedOccurrence(choreB.id), isNull);
    });

    test("pausing one removes only that chore's pending occurrence; the "
        'sibling stays pending and unpaused', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m2],
      );
      final pendingB = await repo.pendingOccurrenceOf(choreB.id);

      await serviceOn(PlainDate(2026, 1, 2)).pauseChore(choreA.id);

      final detailsA = await repo.getChore(choreA.id);
      expect(detailsA!.chore.pausedAt, isNotNull);
      expect(await repo.pendingOccurrenceOf(choreA.id), isNull);

      final detailsB = await repo.getChore(choreB.id);
      expect(detailsB!.chore.pausedAt, isNull);
      final stillPendingB = await repo.pendingOccurrenceOf(choreB.id);
      expect(stillPendingB!.id, pendingB!.id);
    });

    test("soft-deleting one removes only that chore's pending occurrence; "
        'the sibling stays active and untouched', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m2],
      );
      final pendingB = await repo.pendingOccurrenceOf(choreB.id);

      await repo.softDeleteChore(choreA.id);

      final detailsA = await repo.getChore(choreA.id);
      expect(detailsA!.chore.deletedAt, isNotNull);
      expect(await repo.pendingOccurrenceOf(choreA.id), isNull);

      final detailsB = await repo.getChore(choreB.id);
      expect(detailsB!.chore.deletedAt, isNull);
      final stillPendingB = await repo.pendingOccurrenceOf(choreB.id);
      expect(stillPendingB!.id, pendingB!.id);
      expect(stillPendingB.status, OccurrenceStatus.pending);
    });

    test('reopening a closed occurrence restores the correct one; the '
        'sibling (closed the same day) stays closed', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
        householdId: householdId,
        title: duplicateTitle,
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m2],
      );
      final pendingA = await repo.pendingOccurrenceOf(choreA.id);
      final pendingB = await repo.pendingOccurrenceOf(choreB.id);

      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(pendingA!.id, completedBy: m1);
      await serviceOn(
        PlainDate(2026, 1, 1),
      ).completeOccurrence(pendingB!.id, completedBy: m2);

      await serviceOn(PlainDate(2026, 1, 1)).reopenOccurrence(pendingA.id);

      // A is back to pending, for its own original assignee.
      final restoredA = await repo.pendingOccurrenceOf(choreA.id);
      expect(restoredA!.id, pendingA.id);
      expect(restoredA.status, OccurrenceStatus.pending);
      expect(restoredA.assignedMemberId, m1);

      // B is still closed, with its own completer -- reopening A never
      // touched it.
      expect(await repo.pendingOccurrenceOf(choreB.id), isNull);
      final closedB = await repo.latestClosedOccurrence(choreB.id);
      expect(closedB!.id, pendingB.id);
      expect(closedB.status, OccurrenceStatus.done);
      expect(closedB.completedBy, m2);
    });

    test(
      "editing one chore's title leaves the sibling's title unchanged",
      () async {
        final m1 = await _insertMember(db, 'm1', householdId);
        final m2 = await _insertMember(db, 'm2', householdId);
        final choreA = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: duplicateTitle,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          assigneeMemberIds: [m1],
        );
        final choreB = await serviceOn(PlainDate(2026, 1, 1)).createChore(
          householdId: householdId,
          title: duplicateTitle,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          assigneeMemberIds: [m2],
        );

        await repo.updateChore(choreA.id, title: 'Water plants (bedroom)');

        final detailsA = await repo.getChore(choreA.id);
        expect(detailsA!.chore.title, 'Water plants (bedroom)');

        final detailsB = await repo.getChore(choreB.id);
        expect(detailsB!.chore.title, duplicateTitle);
      },
    );
  });
}
