import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `themeModeProvider` mapping tests (spec
/// `docs/feedback/2026-08-01-field-feedback.md` G2): `settings.themeMode`
/// of `'light'`/`'dark'` maps to the matching [ThemeMode]; `NULL` (never
/// set) and an unknown stored value both map to [ThemeMode.system] (follow
/// the OS theme).
///
/// Mirrors `test/app/locale_override_provider_test.dart`'s bare-
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

  testWidgets("maps a stored 'light' to ThemeMode.light", (tester) async {
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
    await container.read(settingsRepositoryProvider).setThemeMode('light');
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.themeMode == 'light',
    );

    expect(container.read(themeModeProvider), ThemeMode.light);

    await database.close();
  });

  testWidgets("maps a stored 'dark' to ThemeMode.dark", (tester) async {
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
    await container.read(settingsRepositoryProvider).setThemeMode('dark');
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.themeMode == 'dark',
    );

    expect(container.read(themeModeProvider), ThemeMode.dark);

    await database.close();
  });

  testWidgets(
    'a NULL stored value maps to ThemeMode.system (follow the OS theme)',
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

      await _pumpUntil(
        tester,
        () => container.read(bootstrapProvider).hasValue,
      );
      await _pumpUntil(tester, () => container.read(settingsProvider).hasValue);
      // Confirms the NULL branch specifically, not just "not loaded yet".
      expect(container.read(settingsProvider).value?.themeMode, isNull);

      expect(container.read(themeModeProvider), ThemeMode.system);

      await database.close();
    },
  );

  testWidgets("an unknown stored value ('sepia') maps to ThemeMode.system "
      '(future-proofing)', (tester) async {
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
    await container.read(settingsRepositoryProvider).setThemeMode('sepia');
    await _pumpUntil(
      tester,
      () => container.read(settingsProvider).value?.themeMode == 'sepia',
    );

    expect(container.read(themeModeProvider), ThemeMode.system);

    await database.close();
  });
}
