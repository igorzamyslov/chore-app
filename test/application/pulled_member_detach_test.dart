/// A pull that soft-deletes a member detaches them from every assignment
/// (plan `docs/plans/2026-10-06-persona-review-fixes.md` W5.6, finding D8):
/// `SyncRepository.applyPulledMember`'s post-hook runs
/// `ChoreRepository.detachMemberFromChores`, the same rewrite a local
/// removal (`MemberService.deleteMember`) runs.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/sync_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late HouseholdRepository households;
  late ChoreRepository chores;
  late ChoreService choreService;
  late Household household;

  final today = PlainDate(2026, 7, 24);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    households = HouseholdRepository(db);
    chores = ChoreRepository(db);
    choreService = ChoreService(
      database: db,
      chores: chores,
      clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
    );
    household = await households.createLocalHousehold('Me');
  });

  tearDown(() => db.close());

  /// The member row as a pull would deliver it: soft-deleted server-side,
  /// clean locally.
  Member pulledSoftDeleted(Member member) => member.copyWith(
    deletedAt: const Value('2026-07-24T08:00:00.000Z'),
    updatedAt: '2026-07-24T08:00:00.000Z',
    syncDirty: false,
  );

  Future<void> markClean(Member member) async {
    await (db.update(db.members)..where((tbl) => tbl.id.equals(member.id)))
        .write(const MembersCompanion(syncDirty: Value(false)));
  }

  test(
    'a pulled soft-delete removes the member from every chore_assignees row '
    'and every pending occurrence',
    () async {
      final a = await households.addMember(household.id, name: 'A', color: 1);
      final b = await households.addMember(household.id, name: 'B', color: 2);
      final c = await households.addMember(household.id, name: 'C', color: 3);
      final rotation = await choreService.createChore(
        householdId: household.id,
        title: 'Dishes',
        startDate: today,
        assignmentMode: AssignmentMode.rotation,
        assigneeMemberIds: [b.id, a.id, c.id],
      );
      final fixed = await choreService.createChore(
        householdId: household.id,
        title: 'Trash',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [b.id],
      );
      expect(
        (await chores.pendingOccurrenceOf(fixed.id))!.assignedMemberId,
        b.id,
      );
      await markClean(b);

      await SyncRepository(db).applyPulledMember(pulledSoftDeleted(b));

      final assigneeRows = await (db.select(
        db.choreAssignees,
      )..where((tbl) => tbl.memberId.equals(b.id))).get();
      expect(assigneeRows, isEmpty);
      final pendingForB =
          await (db.select(db.choreOccurrences)..where(
                (tbl) =>
                    tbl.assignedMemberId.equals(b.id) &
                    tbl.status.equalsValue(OccurrenceStatus.pending),
              ))
              .get();
      expect(pendingForB, isEmpty);

      // Same rules as a local removal: the rotation shrinks, the fixed chore
      // falls back to anyone.
      final rotationAfter = (await chores.getChore(rotation.id))!;
      expect(rotationAfter.chore.assignmentMode, AssignmentMode.rotation);
      expect(rotationAfter.assigneeMemberIds, [a.id, c.id]);
      final fixedAfter = (await chores.getChore(fixed.id))!;
      expect(fixedAfter.chore.assignmentMode, AssignmentMode.anyone);
      expect(fixedAfter.assigneeMemberIds, isEmpty);

      final storedB = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(b.id))).getSingle();
      expect(storedB.deletedAt, isNotNull);
    },
  );

  test('a pulled member that was ALREADY soft-deleted locally triggers no '
      'rewrite', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Trash',
      startDate: today,
      assignmentMode: AssignmentMode.fixed,
      assigneeMemberIds: [a.id],
    );
    // A row soft-deleted locally while still assigned can only come from an
    // older client; the hook must not fire again for it (it only reacts to
    // the transition), so the assignment stays as it was.
    await (db.update(db.members)..where((tbl) => tbl.id.equals(a.id))).write(
      const MembersCompanion(
        deletedAt: Value('2026-07-23T08:00:00.000Z'),
        syncDirty: Value(false),
      ),
    );
    final stored = await (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(a.id))).getSingle();

    await SyncRepository(db).applyPulledMember(stored);

    final details = (await chores.getChore(chore.id))!;
    expect(details.chore.assignmentMode, AssignmentMode.fixed);
    expect(details.assigneeMemberIds, [a.id]);
  });

  test('a dirty local member row wins: the pulled soft-delete is skipped and '
      'nothing is detached', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Trash',
      startDate: today,
      assignmentMode: AssignmentMode.fixed,
      assigneeMemberIds: [a.id],
    );
    // addMember leaves the row dirty.

    await SyncRepository(db).applyPulledMember(pulledSoftDeleted(a));

    final details = (await chores.getChore(chore.id))!;
    expect(details.assigneeMemberIds, [a.id]);
    final storedA = await (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(a.id))).getSingle();
    expect(storedA.deletedAt, isNull);
  });
}
