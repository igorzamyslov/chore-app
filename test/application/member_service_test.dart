/// Service-level tests for `MemberService.deleteMember` (spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1): the full referential
/// matrix -- rotation-of-3 drops to 2, rotation-of-2 converts to fixed,
/// fixed converts to anyone with its pending occurrence unassigned -- plus
/// both guards, the claim-state routing (spec
/// `docs/specs/household-lifecycle.md` §3.2, F10) and the "history is
/// untouched" invariant.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/member_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_household_gateway.dart';

void main() {
  late AppDatabase db;
  late HouseholdRepository households;
  late ChoreRepository chores;
  late ChoreService choreService;
  late MemberService memberService;
  late FakeHouseholdGateway gateway;
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
    gateway = FakeHouseholdGateway();
    memberService = MemberService(
      database: db,
      chores: chores,
      gateway: gateway,
      clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
    );
    household = await households.createLocalHousehold('Me');
  });

  tearDown(() => db.close());

  test('rotation-of-3: deleting one assignee drops the chore to a 2-person '
      'rotation, order preserved', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);
    final b = await households.addMember(household.id, name: 'B', color: 2);
    final c = await households.addMember(household.id, name: 'C', color: 3);
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Dishes',
      startDate: today,
      assignmentMode: AssignmentMode.rotation,
      assigneeMemberIds: [a.id, b.id, c.id],
    );

    await memberService.deleteMember(b.id);

    final details = await chores.getChore(chore.id);
    expect(details!.chore.assignmentMode, AssignmentMode.rotation);
    expect(details.assigneeMemberIds, [a.id, c.id]);
  });

  test('rotation-of-2: deleting one assignee converts the chore to fixed, '
      'assigned to the one remaining', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);
    final b = await households.addMember(household.id, name: 'B', color: 2);
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Dishes',
      startDate: today,
      assignmentMode: AssignmentMode.rotation,
      assigneeMemberIds: [a.id, b.id],
    );

    await memberService.deleteMember(b.id);

    final details = await chores.getChore(chore.id);
    expect(details!.chore.assignmentMode, AssignmentMode.fixed);
    expect(details.assigneeMemberIds, [a.id]);
  });

  test(
    'fixed: deleting the sole assignee converts the chore to anyone, '
    'assignees cleared, and its pending occurrence becomes unassigned',
    () async {
      final a = await households.addMember(household.id, name: 'A', color: 1);
      final chore = await choreService.createChore(
        householdId: household.id,
        title: 'Trash',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [a.id],
      );
      final pendingBefore = await chores.pendingOccurrenceOf(chore.id);
      expect(pendingBefore!.assignedMemberId, a.id);

      await memberService.deleteMember(a.id);

      final details = await chores.getChore(chore.id);
      expect(details!.chore.assignmentMode, AssignmentMode.anyone);
      expect(details.assigneeMemberIds, isEmpty);
      final pendingAfter = await chores.pendingOccurrenceOf(chore.id);
      expect(pendingAfter!.assignedMemberId, isNull);
    },
  );

  test('a pending occurrence assigned to the deleted member becomes '
      'unassigned even when the chore itself keeps its OTHER assignees '
      '(rotation-of-3, the currently-due slot happens to be theirs)', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);
    final b = await households.addMember(household.id, name: 'B', color: 2);
    final c = await households.addMember(household.id, name: 'C', color: 3);
    final chore = await choreService.createChore(
      householdId: household.id,
      title: 'Dishes',
      startDate: today,
      assignmentMode: AssignmentMode.rotation,
      // Position 0 (a) is the first due occurrence's assignee; delete b
      // (position 1) instead, which does NOT touch the current pending
      // occurrence's assignedMemberId via the chore-level cleanup alone.
      assigneeMemberIds: [a.id, b.id, c.id],
    );
    final pendingBefore = await chores.pendingOccurrenceOf(chore.id);
    expect(pendingBefore!.assignedMemberId, a.id);

    await memberService.deleteMember(a.id);

    // The chore rotation drops to [b, c]; the CURRENT pending occurrence
    // (previously assigned to a) is unassigned rather than silently
    // reassigned.
    final details = await chores.getChore(chore.id);
    expect(details!.assigneeMemberIds, [b.id, c.id]);
    final pendingAfter = await chores.pendingOccurrenceOf(chore.id);
    expect(pendingAfter!.assignedMemberId, isNull);
  });

  test(
    'claimed target: calls remove_member FIRST, then runs the same local '
    'referential cleanup (spec docs/specs/household-lifecycle.md §3.2)',
    () async {
      final a = await households.addMember(household.id, name: 'A', color: 1);
      await (db.update(db.members)..where((tbl) => tbl.id.equals(a.id))).write(
        const MembersCompanion(userId: Value('server-user-1')),
      );

      await memberService.deleteMember(a.id);

      expect(gateway.removeMemberCalls, [a.id]);
      final row = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(a.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(
        row.syncDirty,
        isTrue,
        reason:
            'the local soft-delete still pushes deleted_at -- a harmless '
            'no-op convergence on a row the server already soft-deleted '
            '(§3.2), so the engine needs no special case',
      );
    },
  );

  test('claimed target whose RPC fails: throws ClaimedMemberRemovalFailure and '
      'changes NOTHING locally -- the member stays active', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);
    await (db.update(db.members)..where((tbl) => tbl.id.equals(a.id))).write(
      const MembersCompanion(userId: Value('server-user-1')),
    );
    gateway.removeMemberError = Exception('offline');

    await expectLater(
      memberService.deleteMember(a.id),
      throwsA(isA<ClaimedMemberRemovalFailure>()),
    );

    final row = await (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(a.id))).getSingle();
    expect(row.deletedAt, isNull);
  });

  test('unclaimed target: purely local, the RPC is never called', () async {
    final a = await households.addMember(household.id, name: 'A', color: 1);

    await memberService.deleteMember(a.id);

    expect(gateway.removeMemberCalls, isEmpty);
    final row = await (db.select(
      db.members,
    )..where((tbl) => tbl.id.equals(a.id))).getSingle();
    expect(row.deletedAt, isNotNull);
  });

  test(
    'the last-member guard is checked BEFORE the RPC, so a removal the local '
    'rules refuse never reaches the server',
    () async {
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();
      await (db.update(db.members)..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('server-user-1')),
      );

      await expectLater(
        memberService.deleteMember(me.id),
        throwsA(isA<StateError>()),
      );
      expect(gateway.removeMemberCalls, isEmpty);
    },
  );

  test(
    'guard: throws for the last remaining active member, changing nothing',
    () async {
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();

      await expectLater(
        memberService.deleteMember(me.id),
        throwsA(isA<StateError>()),
      );

      final row = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(row.deletedAt, isNull);
    },
  );

  test(
    'history untouched: a closed occurrence keeps completedBy/assignedMemberId '
    'pointing at the soft-deleted member',
    () async {
      final a = await households.addMember(household.id, name: 'A', color: 1);
      final chore = await choreService.createChore(
        householdId: household.id,
        title: 'One-off',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [a.id],
      );
      final pending = await chores.pendingOccurrenceOf(chore.id);
      await choreService.completeOccurrence(pending!.id, completedBy: a.id);

      await memberService.deleteMember(a.id);

      final closed = await (db.select(
        db.choreOccurrences,
      )..where((tbl) => tbl.id.equals(pending.id))).getSingle();
      expect(closed.status, OccurrenceStatus.done);
      expect(closed.completedBy, a.id);
      expect(closed.assignedMemberId, a.id);

      final deletedMember = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(a.id))).getSingle();
      expect(deletedMember.deletedAt, isNotNull);
      expect(deletedMember.syncDirty, isTrue);
    },
  );
}
