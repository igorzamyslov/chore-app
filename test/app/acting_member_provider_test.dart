import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_auth_gateway.dart';

/// `actingMemberProvider` fallback-resolution tests (spec
/// `docs/specs/members-management.md` §2): a valid stored id wins; a NULL
/// or dangling stored id falls back to first-admin-else-first-member.
///
/// Mirrors `test/app/digest_reschedule_test.dart`'s bare-`ProviderContainer`
/// pattern (no widget tree needed, since this only exercises a plain
/// `Provider` built on top of two `StreamProvider`s) and its polling
/// helper, for the same reason documented there: a bare `await
/// container.read(x.future)` deadlocks under `flutter test`'s fake clock,
/// so progress is nudged forward with repeated nonzero-duration
/// `tester.pump()` calls instead.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('condition never became true');
}

void main() {
  setUpAll(() {
    // Every test below opens its own fresh in-memory AppDatabase, so
    // drift's "multiple database instances" warning (aimed at accidental
    // duplicate app databases sharing one executor) doesn't apply here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets('honors a valid stored actingMemberId', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly on the database
    // BEFORE the container exists (FutureProviders only ever compute
    // once, so this must happen before the first read below).
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
      ],
    );
    addTearDown(container.dispose);

    // Read as AsyncValue and poll — bootstrap internally awaits a drift
    // watch stream (catchUpOverdue), so a bare `await ...future` here is
    // exactly the deadlock the doc comment above warns about.
    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    final householdId = container.read(bootstrapProvider).requireValue;
    await _pumpUntil(
      tester,
      () =>
          container.read(membersProvider).hasValue &&
          container.read(settingsProvider).hasValue,
    );

    final anna = await container
        .read(householdRepositoryProvider)
        .addMember(householdId, name: 'Anna', color: 0xFF112233);
    await _pumpUntil(
      tester,
      () => (container.read(membersProvider).value?.length ?? 0) == 2,
    );

    await container.read(settingsRepositoryProvider).setActingMember(anna.id);
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.actingMemberId == anna.id,
    );

    expect(container.read(actingMemberProvider)?.id, anna.id);

    await database.close();
  });

  testWidgets('falls back to the first admin when actingMemberId is NULL', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly on the database
    // BEFORE the container exists (FutureProviders only ever compute
    // once, so this must happen before the first read below).
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
      ],
    );
    addTearDown(container.dispose);

    // Poll instead of bare-awaiting bootstrap — see the first test.
    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    final householdId = container.read(bootstrapProvider).requireValue;
    await _pumpUntil(
      tester,
      () =>
          container.read(membersProvider).hasValue &&
          container.read(settingsProvider).hasValue,
    );
    // Confirms the NULL branch specifically, not just "not loaded yet".
    expect(container.read(settingsProvider).value?.actingMemberId, isNull);

    // A second, non-admin member exists, but is never made the acting
    // member — the fallback must still land on the bootstrap admin ('Me'),
    // not merely "some member".
    await container
        .read(householdRepositoryProvider)
        .addMember(householdId, name: 'Anna', color: 0xFF112233);
    await _pumpUntil(
      tester,
      () => (container.read(membersProvider).value?.length ?? 0) == 2,
    );

    expect(container.read(actingMemberProvider)?.name, 'Me');

    await database.close();
  });

  testWidgets(
    'falls back to the first admin when actingMemberId is dangling',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      // bootstrapProvider no longer creates a household (spec
      // docs/specs/onboarding-v2.md §2) -- seed one directly on the
      // database BEFORE the container exists.
      await HouseholdRepository(database).createLocalHousehold('Me');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Poll instead of bare-awaiting bootstrap — see the first test.
      await _pumpUntil(
        tester,
        () => container.read(bootstrapProvider).hasValue,
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(membersProvider).hasValue &&
            container.read(settingsProvider).hasValue,
      );

      // No member with this id exists in the household at all.
      await container
          .read(settingsRepositoryProvider)
          .setActingMember('does-not-exist');
      await _pumpUntil(
        tester,
        () =>
            container.read(settingsProvider).value?.actingMemberId ==
            'does-not-exist',
      );

      expect(container.read(actingMemberProvider)?.name, 'Me');

      await database.close();
    },
  );

  testWidgets(
    'a linked, signed-in device pins to the CLAIMED member, ignoring a '
    'stored actingMemberId that points at someone else',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _pumpUntil(
        tester,
        () => container.read(bootstrapProvider).hasValue,
      );
      final householdId = container.read(bootstrapProvider).requireValue;
      await _pumpUntil(
        tester,
        () =>
            container.read(membersProvider).hasValue &&
            container.read(settingsProvider).hasValue,
      );
      final me = container.read(membersProvider).requireValue.single;

      final anna = await container
          .read(householdRepositoryProvider)
          .addMember(householdId, name: 'Anna', color: 0xFF112233);
      // The device-scoped leftover this ticket exists to defeat: this phone
      // still thinks it is Anna.
      await container.read(settingsRepositoryProvider).setActingMember(anna.id);
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u-1')),
      );
      await SettingsRepository(database).setSyncLinked(
        householdId: householdId,
        linkedAt: DateTime.utc(2026, 7, 24),
      );

      await _pumpUntil(
        tester,
        () => container.read(actingMemberProvider)?.id == me.id,
      );
      expect(container.read(actingMemberProvider)?.name, 'Me');

      await database.close();
    },
  );

  testWidgets(
    'while pinned with no claim yet, falls back to the stored member and '
    'NEVER to the first-admin guess',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await HouseholdRepository(database).createLocalHousehold('Me');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
          authGatewayProvider.overrideWithValue(
            FakeAuthGateway(
              currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _pumpUntil(
        tester,
        () => container.read(bootstrapProvider).hasValue,
      );
      final householdId = container.read(bootstrapProvider).requireValue;
      await _pumpUntil(
        tester,
        () =>
            container.read(membersProvider).hasValue &&
            container.read(settingsProvider).hasValue,
      );

      final anna = await container
          .read(householdRepositoryProvider)
          .addMember(householdId, name: 'Anna', color: 0xFF112233);
      await container.read(settingsRepositoryProvider).setActingMember(anna.id);
      await SettingsRepository(database).setSyncLinked(
        householdId: householdId,
        linkedAt: DateTime.utc(2026, 7, 24),
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(memberIdentityModeProvider) ==
            MemberIdentityMode.pinned,
      );

      // Stored id still resolves: use it (both link paths set it to this
      // device's own member).
      expect(container.read(actingMemberProvider)?.id, anna.id);

      // Stored id dangles: return null rather than crediting 'Me' (the
      // first admin) — that guess is exactly the A-5 misattribution.
      await container
          .read(settingsRepositoryProvider)
          .setActingMember('does-not-exist');
      await _pumpUntil(
        tester,
        () => container.read(actingMemberProvider) == null,
      );
      expect(container.read(actingMemberProvider), isNull);

      await database.close();
    },
  );
}
