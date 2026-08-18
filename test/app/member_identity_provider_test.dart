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

/// `memberIdentityModeProvider` / `claimedMemberProvider` tests (A-5, spec
/// `docs/feedback/2026-08-07-field-feedback.md` B1): this device is
/// "pinned" to a claimed member only while it is LINKED and SIGNED IN, and
/// the claim is resolved from the local `members.userId` mirror.
///
/// Bare-`ProviderContainer` pattern with the polling helper, exactly as in
/// `test/app/acting_member_provider_test.dart`: a bare
/// `await container.read(x.future)` deadlocks under `flutter test`'s fake
/// clock, so progress is nudged with repeated nonzero-duration pumps.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
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
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  /// Seeds a household + 'Me' member, builds a container whose auth gateway
  /// reports [user], and waits for bootstrap/members/settings to resolve.
  Future<({ProviderContainer container, String householdId, Member me})>
  setUpContainer(
    WidgetTester tester,
    AppDatabase database, {
    AuthUser? user,
  }) async {
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
        authGatewayProvider.overrideWithValue(
          FakeAuthGateway(currentUser: user),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    final householdId = container.read(bootstrapProvider).requireValue;
    await _pumpUntil(
      tester,
      () =>
          container.read(membersProvider).hasValue &&
          container.read(settingsProvider).hasValue &&
          container.read(currentAuthUserProvider).hasValue,
    );
    final me = container.read(membersProvider).requireValue.single;
    return (container: container, householdId: householdId, me: me);
  }

  testWidgets('a local-only household is in switching mode with no claim', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(tester, database);
    final container = setUpResult.container;

    expect(
      container.read(memberIdentityModeProvider),
      MemberIdentityMode.switching,
    );
    expect(container.read(claimedMemberProvider), isNull);

    await database.close();
  });

  testWidgets('linked but signed out stays in switching mode', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(tester, database);
    final container = setUpResult.container;

    await SettingsRepository(database).setSyncLinked(
      householdId: setUpResult.householdId,
      linkedAt: DateTime.utc(2026, 7, 24),
    );
    await _pumpUntil(
      tester,
      () =>
          container.read(settingsProvider).value?.syncHouseholdId ==
          setUpResult.householdId,
    );

    expect(
      container.read(memberIdentityModeProvider),
      MemberIdentityMode.switching,
    );
    expect(container.read(claimedMemberProvider), isNull);

    await database.close();
  });

  testWidgets('linked AND signed in pins to the member holding the claim', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(
      tester,
      database,
      user: const AuthUser(id: 'u-1', email: 'me@example.com'),
    );
    final container = setUpResult.container;

    await SettingsRepository(database).setSyncLinked(
      householdId: setUpResult.householdId,
      linkedAt: DateTime.utc(2026, 7, 24),
    );
    await _pumpUntil(
      tester,
      () =>
          container.read(memberIdentityModeProvider) ==
          MemberIdentityMode.pinned,
    );

    // Linked + signed in, but the claim hasn't been pulled down yet.
    expect(container.read(claimedMemberProvider), isNull);

    // The claim arrives (pull, join snapshot, or adopt's G-B mirror).
    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(setUpResult.me.id))).write(
      const MembersCompanion(userId: Value('u-1')),
    );
    await _pumpUntil(
      tester,
      () => container.read(claimedMemberProvider)?.id == setUpResult.me.id,
    );

    expect(
      container.read(memberIdentityModeProvider),
      MemberIdentityMode.pinned,
    );
    expect(container.read(claimedMemberProvider)!.name, 'Me');

    await database.close();
  });

  testWidgets("another account's claim is not this device's claim", (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final setUpResult = await setUpContainer(
      tester,
      database,
      user: const AuthUser(id: 'u-1', email: 'me@example.com'),
    );
    final container = setUpResult.container;

    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(setUpResult.me.id))).write(
      const MembersCompanion(userId: Value('someone-else')),
    );
    await SettingsRepository(database).setSyncLinked(
      householdId: setUpResult.householdId,
      linkedAt: DateTime.utc(2026, 7, 24),
    );
    await _pumpUntil(
      tester,
      () =>
          container.read(memberIdentityModeProvider) ==
          MemberIdentityMode.pinned,
    );

    expect(container.read(claimedMemberProvider), isNull);

    await database.close();
  });
}
