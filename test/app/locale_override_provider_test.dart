import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `localeOverrideProvider` mapping tests (spec `docs/next-session-plan.md`
/// #5): `settings.locale` of `'de'`/`'en'` maps to the matching [Locale];
/// `NULL` (never set) and an unknown stored value both map to `null`
/// (follow the OS locale).
///
/// Mirrors `test/app/acting_member_provider_test.dart`'s bare-
/// `ProviderContainer` pattern and its polling helper: `bootstrapProvider`
/// internally awaits a drift watch stream, so a bare `await
/// container.read(x.future)` deadlocks under `flutter test`'s fake clock.
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
    // Every test below opens its own fresh in-memory AppDatabase, so
    // drift's "multiple database instances" warning (aimed at accidental
    // duplicate app databases sharing one executor) doesn't apply here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets("maps a stored 'de' to Locale('de')", (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly on the database
    // BEFORE the container exists.
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
      ],
    );
    addTearDown(container.dispose);

    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    await container.read(settingsRepositoryProvider).setLocale('de');
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.locale == 'de',
    );

    expect(container.read(localeOverrideProvider), const Locale('de'));

    await database.close();
  });

  testWidgets("maps a stored 'en' to Locale('en')", (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly on the database
    // BEFORE the container exists.
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
      ],
    );
    addTearDown(container.dispose);

    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    await container.read(settingsRepositoryProvider).setLocale('en');
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.locale == 'en',
    );

    expect(container.read(localeOverrideProvider), const Locale('en'));

    await database.close();
  });

  testWidgets('a NULL stored value maps to null (follow the OS locale)', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly on the database
    // BEFORE the container exists.
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
      ],
    );
    addTearDown(container.dispose);

    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    await _pumpUntil(tester, () => container.read(settingsProvider).hasValue);
    // Confirms the NULL branch specifically, not just "not loaded yet".
    expect(container.read(settingsProvider).value?.locale, isNull);

    expect(container.read(localeOverrideProvider), isNull);

    await database.close();
  });

  testWidgets("an unknown stored value ('fr') maps to null (future-proofing)", (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    // bootstrapProvider no longer creates a household (spec
    // docs/specs/onboarding-v2.md §2) -- seed one directly on the
    // database BEFORE the container exists.
    await HouseholdRepository(database).createLocalHousehold('Me');
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(Clock.fixed(DateTime(2026, 7, 24, 9))),
      ],
    );
    addTearDown(container.dispose);

    await _pumpUntil(tester, () => container.read(bootstrapProvider).hasValue);
    await container.read(settingsRepositoryProvider).setLocale('fr');
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.locale == 'fr',
    );

    expect(container.read(localeOverrideProvider), isNull);

    await database.close();
  });
}
