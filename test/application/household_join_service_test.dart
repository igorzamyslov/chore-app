import 'dart:io';

import 'package:chore_app/application/household_join_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
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
}
