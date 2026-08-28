/// Service-level tests for the two account-scoped exits (spec
/// `docs/specs/household-lifecycle.md` §2.2, §3.3, D-L3): the server call
/// happens first, the device unlinks, and this phone's data survives unless
/// the caller explicitly asked for it to go.
library;

import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/household_exit_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_auth_gateway.dart';
import '../features/settings/fake_household_gateway.dart';

void main() {
  late AppDatabase db;
  late FakeHouseholdGateway gateway;
  late FakeAuthGateway auth;
  late SettingsRepository settings;
  late HouseholdExitService service;
  late Household household;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeHouseholdGateway();
    auth = FakeAuthGateway();
    settings = SettingsRepository(db);
    service = HouseholdExitService(
      gateway: gateway,
      auth: auth,
      settings: settings,
      database: db,
    );
    household = await HouseholdRepository(db).createLocalHousehold('Me');
    await settings.setSyncLinked(
      householdId: household.id,
      linkedAt: DateTime.utc(2026),
    );
  });

  tearDown(() => db.close());

  test(
    'leave, keeping this phone: calls the RPC, unlinks, and leaves every '
    'local row in place (D-L3 -- keeping is the default)',
    () async {
      await service.leaveHousehold(
        householdId: household.id,
        alsoDeleteLocalData: false,
      );

      expect(gateway.leaveHouseholdCalls, [household.id]);
      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, isNull);
      expect(await db.select(db.households).get(), hasLength(1));
      expect(await db.select(db.members).get(), hasLength(1));
    },
  );

  test('leave with the opt-in checked: this phone is wiped as well', () async {
    await service.leaveHousehold(
      householdId: household.id,
      alsoDeleteLocalData: true,
    );

    expect(gateway.leaveHouseholdCalls, [household.id]);
    expect(await db.select(db.households).get(), isEmpty);
    expect(await db.select(db.members).get(), isEmpty);
  });

  test(
    'a failed leave changes nothing locally -- the device stays linked, so '
    'a retry is a plain retry',
    () async {
      gateway.leaveHouseholdError = Exception('offline');

      await expectLater(
        service.leaveHousehold(
          householdId: household.id,
          alsoDeleteLocalData: false,
        ),
        throwsA(isA<Exception>()),
      );

      final row = await settings.ensureSettings();
      expect(row.syncHouseholdId, household.id);
      expect(await db.select(db.households).get(), hasLength(1));
    },
  );

  test(
    'leaving clears a revocation flag a racing pull may have set, so the '
    'user who chose to leave is never told they were removed (§3.5)',
    () async {
      await settings.setMembershipRevoked();

      await service.leaveHousehold(
        householdId: household.id,
        alsoDeleteLocalData: false,
      );

      final row = await settings.ensureSettings();
      expect(row.membershipRevoked, isFalse);
    },
  );

  test('leaving does NOT sign the account out (D-L8)', () async {
    auth.signIn(const AuthUser(id: 'me', email: 'me@x.y'));

    await service.leaveHousehold(
      householdId: household.id,
      alsoDeleteLocalData: false,
    );

    expect(auth.currentUser, isNotNull);
  });
}
