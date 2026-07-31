import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
