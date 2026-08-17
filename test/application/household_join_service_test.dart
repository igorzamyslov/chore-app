import 'dart:io';

import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../features/settings/fake_household_gateway.dart';
import '../features/settings/fake_path_provider_platform.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('famdo-join-service-');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            id: 'old-hh',
            name: 'Old household',
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('join via claim: archive written, old household replaced', () async {
    final gateway = FakeHouseholdGateway()
      ..claimResultHouseholdId = 'joined-hh'
      ..downloadSnapshotOverride = const HouseholdSnapshot(
        household: Household(
          id: 'joined-hh',
          name: 'Joined household',
          createdAt: 't0',
          updatedAt: 't0',
          syncDirty: false,
        ),
      );
    final service = HouseholdJoinService(
      gateway: gateway,
      database: db,
      settings: SettingsRepository(db),
      clock: Clock.fixed(DateTime.utc(2026, 7, 24)),
    );

    final result = await service.join(
      oldHouseholdId: 'old-hh',
      code: 'ABC12345',
      choice: const ClaimMemberChoice('m-anna'),
      importAccepted: false,
    );

    expect(result.householdId, 'joined-hh');
    expect(result.archiveFileName, 'famdo-archive-2026-07-24.json');

    final households = await db.select(db.households).get();
    expect(households.map((h) => h.id), ['joined-hh']);
  });

  test(
    'reconnect (spec §7.6): no code, no claim/join RPC -- downloads and '
    'replaces straight from the ReconnectChoice ids',
    () async {
      final gateway = FakeHouseholdGateway()
        ..downloadSnapshotOverride = const HouseholdSnapshot(
          household: Household(
            id: 'joined-hh',
            name: 'Joined household',
            createdAt: 't0',
            updatedAt: 't0',
            syncDirty: false,
          ),
          // Fixture correction, not a regression: reconnect now requires the
          // reconnecting member to be present and active in the downloaded
          // snapshot (spec §7.6 -- it is the only JoinChoice with no
          // server-side authorization step). The two reconnect WIDGET tests
          // (account_section_test.dart, welcome_join_test.dart) already seed
          // exactly this member and needed no change.
          members: [
            Member(
              id: 'm-anna',
              householdId: 'joined-hh',
              name: 'Anna',
              color: 0xFF6D9F71,
              role: MemberRole.member,
              createdAt: 't0',
              updatedAt: 't0',
              syncDirty: false,
            ),
          ],
        );
      final service = HouseholdJoinService(
        gateway: gateway,
        database: db,
        settings: SettingsRepository(db),
        clock: Clock.fixed(DateTime.utc(2026, 7, 24)),
      );

      final result = await service.join(
        oldHouseholdId: 'old-hh',
        choice: const ReconnectChoice(
          householdId: 'joined-hh',
          memberId: 'm-anna',
        ),
        importAccepted: false,
      );

      expect(result.householdId, 'joined-hh');
      expect(gateway.claimMemberCalls, isEmpty);
      expect(gateway.joinAsNewMemberCalls, isEmpty);
      expect(gateway.downloadHouseholdCalls, ['joined-hh']);

      final households = await db.select(db.households).get();
      expect(households.map((h) => h.id), ['joined-hh']);

      final settings = await db.select(db.settings).getSingle();
      expect(settings.actingMemberId, 'm-anna');
      expect(settings.syncHouseholdId, 'joined-hh');
    },
  );

  test(
    'joinFresh (the welcome path, spec docs/specs/onboarding-v2.md §1): no '
    'archive, no old household deleted, and the pendingJoinCode left over '
    'from the code-entry step is cleared',
    () async {
      final settings = SettingsRepository(db);
      await settings.setPendingJoinCode('ABC12345');

      final gateway = FakeHouseholdGateway()
        ..claimResultHouseholdId = 'joined-hh'
        ..downloadSnapshotOverride = const HouseholdSnapshot(
          household: Household(
            id: 'joined-hh',
            name: 'Joined household',
            createdAt: 't0',
            updatedAt: 't0',
            syncDirty: false,
          ),
        );
      final service = HouseholdJoinService(
        gateway: gateway,
        database: db,
        settings: settings,
        clock: Clock.fixed(DateTime.utc(2026, 7, 24)),
      );

      final joinedHouseholdId = await service.joinFresh(
        choice: const ClaimMemberChoice('m-anna'),
        code: 'ABC12345',
      );

      expect(joinedHouseholdId, 'joined-hh');
      // The 'old-hh' this file's `setUp` seeds is deliberately left alone:
      // unlike `join`, `joinFresh` has nothing local to archive or replace,
      // so assert only on what `joinFresh` itself is responsible for.
      final households = await db.select(db.households).get();
      expect(households.map((h) => h.id), containsAll(['joined-hh']));

      final row = await db.select(db.settings).getSingle();
      expect(row.syncHouseholdId, 'joined-hh');
      expect(row.actingMemberId, 'm-anna');
      expect(
        row.pendingJoinCode,
        isNull,
        reason: 'the code this join was for has done its job',
      );
    },
  );

  // The Finding 1 guard (plan
  // `docs/plans/2026-08-14-reconnect-adopt-hardening.md` Task 1). RLS filters
  // rows rather than erroring, so "the server refused you" arrives as a
  // SUCCESSFUL download of an EMPTY snapshot. Before the guard, `join` then
  // deleted the local household and inserted nothing.
  group('unconfirmed snapshots never replace local data (spec §7.6)', () {
    late HouseholdJoinService service;

    /// Fills `old-hh` with one row in every table `_deleteHousehold` wipes,
    /// so the survival assertions below cover the ACTUAL blast radius of the
    /// bug rather than just the households row. Without this, a guard that
    /// deleted the chores/occurrences/categories/members/shopping items and
    /// merely left the household row standing would still pass.
    Future<void> seedOldHouseholdContents() async {
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: 'old-m1',
              householdId: 'old-hh',
              name: 'Me',
              color: 0xFF6D9F71,
              role: MemberRole.admin,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'old-c1',
              householdId: 'old-hh',
              kind: CategoryKind.chore,
              name: 'Kitchen',
              icon: 'cleaning_services',
              color: 0xFF8C7BC9,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await db
          .into(db.chores)
          .insert(
            ChoresCompanion.insert(
              id: 'old-ch1',
              householdId: 'old-hh',
              title: 'Dishes',
              startDate: PlainDate(2026, 7, 20),
              assignmentMode: AssignmentMode.anyone,
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await db
          .into(db.choreAssignees)
          .insert(
            ChoreAssigneesCompanion.insert(
              choreId: 'old-ch1',
              memberId: 'old-m1',
              position: 0,
            ),
          );
      await db
          .into(db.choreOccurrences)
          .insert(
            ChoreOccurrencesCompanion.insert(
              id: 'old-o1',
              choreId: 'old-ch1',
              dueDate: PlainDate(2026, 7, 24),
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
      await db
          .into(db.shoppingItems)
          .insert(
            ShoppingItemsCompanion.insert(
              id: 'old-s1',
              householdId: 'old-hh',
              name: 'Milk',
              createdAt: 't0',
              updatedAt: 't0',
            ),
          );
    }

    setUp(seedOldHouseholdContents);

    void buildService(HouseholdSnapshot snapshot) {
      service = HouseholdJoinService(
        gateway: FakeHouseholdGateway()
          ..claimResultHouseholdId = 'joined-hh'
          ..downloadSnapshotOverride = snapshot,
        database: db,
        settings: SettingsRepository(db),
        clock: Clock.fixed(DateTime.utc(2026, 7, 24)),
      );
    }

    /// EVERY local row must be intact -- not just the household -- and the
    /// device must NOT be linked. This is the assertion the whole task
    /// exists for: before the guard, `_deleteHousehold` emptied all six of
    /// these tables and `_insertSnapshot` put nothing back.
    Future<void> expectNothingDestroyed() async {
      expect(
        (await db.select(db.households).get()).map((row) => row.id),
        ['old-hh'],
      );
      expect(
        (await db.select(db.members).get()).map((row) => row.id),
        ['old-m1'],
      );
      expect(
        (await db.select(db.categories).get()).map((row) => row.id),
        ['old-c1'],
      );
      expect(
        (await db.select(db.chores).get()).map((row) => row.id),
        ['old-ch1'],
      );
      expect(
        (await db.select(db.choreAssignees).get()).map((row) => row.choreId),
        ['old-ch1'],
      );
      expect(
        (await db.select(db.choreOccurrences).get()).map((row) => row.id),
        ['old-o1'],
      );
      expect(
        (await db.select(db.shoppingItems).get()).map((row) => row.id),
        ['old-s1'],
      );
      final settingsRows = await db.select(db.settings).get();
      expect(
        settingsRows.map((row) => row.syncHouseholdId),
        everyElement(isNull),
      );
    }

    test(
      'reconnect against a household the caller can no longer read aborts '
      'and destroys nothing',
      () async {
        buildService(const HouseholdSnapshot());

        await expectLater(
          service.join(
            oldHouseholdId: 'old-hh',
            choice: const ReconnectChoice(
              householdId: 'joined-hh',
              memberId: 'm-anna',
            ),
            importAccepted: false,
          ),
          throwsA(isA<HouseholdSnapshotUnavailable>()),
        );

        await expectNothingDestroyed();
      },
    );

    test('reconnect whose own member row is missing from the snapshot '
        'aborts', () async {
      buildService(
        const HouseholdSnapshot(
          household: Household(
            id: 'joined-hh',
            name: 'Joined household',
            createdAt: 't0',
            updatedAt: 't0',
            syncDirty: false,
          ),
        ),
      );

      await expectLater(
        service.join(
          oldHouseholdId: 'old-hh',
          choice: const ReconnectChoice(
            householdId: 'joined-hh',
            memberId: 'm-anna',
          ),
          importAccepted: false,
        ),
        throwsA(isA<HouseholdSnapshotUnavailable>()),
      );

      await expectNothingDestroyed();
    });

    test('reconnect whose member row is present but soft-deleted '
        'aborts', () async {
      buildService(
        const HouseholdSnapshot(
          household: Household(
            id: 'joined-hh',
            name: 'Joined household',
            createdAt: 't0',
            updatedAt: 't0',
            syncDirty: false,
          ),
          members: [
            Member(
              id: 'm-anna',
              householdId: 'joined-hh',
              name: 'Anna',
              color: 0xFF6D9F71,
              role: MemberRole.member,
              createdAt: 't0',
              updatedAt: 't0',
              deletedAt: 't1',
              syncDirty: false,
            ),
          ],
        ),
      );

      await expectLater(
        service.join(
          oldHouseholdId: 'old-hh',
          choice: const ReconnectChoice(
            householdId: 'joined-hh',
            memberId: 'm-anna',
          ),
          importAccepted: false,
        ),
        throwsA(isA<HouseholdSnapshotUnavailable>()),
      );

      await expectNothingDestroyed();
    });

    test('claim against an empty snapshot aborts', () async {
      buildService(const HouseholdSnapshot());

      await expectLater(
        service.join(
          oldHouseholdId: 'old-hh',
          code: 'ABC12345',
          choice: const ClaimMemberChoice('m-anna'),
          importAccepted: false,
        ),
        throwsA(isA<HouseholdSnapshotUnavailable>()),
      );

      await expectNothingDestroyed();
    });

    test(
      'joinFresh against an empty snapshot aborts without linking',
      () async {
        buildService(const HouseholdSnapshot());

        await expectLater(
          service.joinFresh(
            code: 'ABC12345',
            choice: const ClaimMemberChoice('m-anna'),
          ),
          throwsA(isA<HouseholdSnapshotUnavailable>()),
        );

        await expectNothingDestroyed();
      },
    );
  });
}
