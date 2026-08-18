import 'package:chore_app/application/household_link_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_household_gateway.dart';

/// Unit tests for `HouseholdLinkService.disconnect` (spec
/// `docs/feedback/2026-08-07-field-feedback.md` A1.2): the local exit from a
/// linked household this app never had. Exercised directly against the
/// service (no widget pump needed) since disconnect is a pure local-state
/// change with no UI dependency.
void main() {
  late AppDatabase db;
  late FakeHouseholdGateway gateway;
  late HouseholdLinkService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeHouseholdGateway();
    service = HouseholdLinkService(
      gateway: gateway,
      households: HouseholdRepository(db),
      settings: SettingsRepository(db),
      clock: Clock.fixed(DateTime.utc(2026, 7, 24)),
    );
  });

  tearDown(() => db.close());

  test(
    'disconnect clears syncHouseholdId, syncLinkedAt, and '
    'syncLastPulledAt, leaves every other local row untouched, and never '
    'calls the gateway (the server is never touched)',
    () async {
      final household = await HouseholdRepository(db).createLocalHousehold(
        'Me',
      );
      final settings = SettingsRepository(db);
      await settings.setSyncLinked(
        householdId: household.id,
        linkedAt: DateTime.utc(2026),
      );
      await settings.setSyncLastPulledAt(DateTime.utc(2026, 1, 2));

      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();
      final chore = await ChoreRepository(db).createChore(
        householdId: household.id,
        title: 'Water plants',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final item = await ShoppingRepository(
        db,
      ).addItem(household.id, name: 'Milk');

      await service.disconnect();

      final updatedSettings = await db.select(db.settings).getSingle();
      expect(updatedSettings.syncHouseholdId, isNull);
      expect(updatedSettings.syncLinkedAt, isNull);
      expect(updatedSettings.syncLastPulledAt, isNull);

      // Not a delete: the household, its member, the chore, and the
      // shopping item are all still exactly there.
      final households = await db.select(db.households).get();
      expect(households.map((h) => h.id), [household.id]);
      final members = await db.select(db.members).get();
      expect(members.map((m) => m.id), [me.id]);
      final chores = await db.select(db.chores).get();
      expect(chores.map((c) => c.id), [chore.id]);
      final items = await db.select(db.shoppingItems).get();
      expect(items.map((i) => i.id), [item.id]);

      // The server is genuinely never called -- disconnect is purely local.
      expect(gateway.createHouseholdCalls, isEmpty);
      expect(gateway.uploadHouseholdDataCalls, isEmpty);
      expect(gateway.downloadHouseholdCalls, isEmpty);
      expect(gateway.createInviteCalls, isEmpty);
      expect(gateway.revokeActiveInvitesCalls, isEmpty);
      expect(gateway.findMyMembershipCallCount, 0);
    },
  );

  test(
    'disconnect on an already-unlinked household is a harmless no-op',
    () async {
      await HouseholdRepository(db).createLocalHousehold('Me');

      await service.disconnect();

      final settings = await db.select(db.settings).getSingle();
      expect(settings.syncHouseholdId, isNull);
    },
  );

  test(
    'adopt sets the acting member userId locally, mirroring the claim the '
    'server just made (spec docs/specs/household-lifecycle.md §3.1 G-B)',
    () async {
      final households = HouseholdRepository(db);
      final household = await households.createLocalHousehold('Me');
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();

      await service.adopt(
        householdId: household.id,
        actingMemberId: me.id,
        authUserId: 'auth-user-1',
      );

      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(after.userId, 'auth-user-1');
    },
  );

  test(
    'adopt mirrors the server claim onto the local member row (G-B, spec '
    'docs/specs/household-lifecycle.md §3.1) without dirtying it',
    () async {
      final household = await HouseholdRepository(db).createLocalHousehold(
        'Me',
      );
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();
      expect(me.userId, isNull);

      await service.adopt(
        householdId: household.id,
        actingMemberId: me.id,
        authUserId: 'auth-user-1',
      );

      final claimed = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(claimed.userId, 'auth-user-1');
      // Still admin (step 3's existing role mirror) and still marked dirty
      // by that role write -- setMemberClaim itself must not bump
      // updatedAt or syncDirty, because user_id is server-owned and is not
      // even UPDATE-granted (initial schema grants).
      expect(claimed.role, MemberRole.admin);
      expect(claimed.updatedAt, isNot(equals(me.updatedAt)));
    },
  );

  test(
    "adopt sets settings.actingMemberId to the caller's own member id, "
    'matching what HouseholdJoinService.join/joinFresh already do -- '
    'without it, actingMemberProvider has no stored id to fall back on '
    'before the first claim-carrying pull, and can resolve to null (spec '
    'docs/specs/members-management.md §4.2, pre-claim window)',
    () async {
      final household = await HouseholdRepository(db).createLocalHousehold(
        'Me',
      );
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();

      await service.adopt(
        householdId: household.id,
        actingMemberId: me.id,
        authUserId: 'auth-user-1',
      );

      final settings = await db.select(db.settings).getSingle();
      expect(settings.actingMemberId, me.id);
    },
  );
}
