/// Shared widget-test bootstrap helper.
///
/// Every widget test in this suite pumps the real [ChoreApp] against a real
/// in-memory [AppDatabase] and a fixed [Clock] — the only two provider
/// overrides this app ever needs (per
/// `docs/specs/ui-foundation-chores.md`). No repository or service is ever
/// mocked.
library;

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs a [testWidgets] test that pumps [ChoreApp] against a fresh
/// in-memory database and a clock fixed at [today] (09:00 local), waits for
/// bootstrap and animations to settle, then hands the pumped
/// `WidgetTester` and the in-memory [AppDatabase] to [body] — so a test can
/// seed chores/occurrences directly through the real repositories/service
/// before asserting on the rendered UI.
///
/// [body]'s database is explicitly closed right after it returns, as the
/// last thing done *inside* the test body (rather than via `addTearDown`,
/// which runs too late: flutter_test's "a Timer is still pending" leak
/// check runs before registered tear-downs, so only closing the database
/// before the test body itself returns reliably drains drift's internal
/// stream-cleanup timer in time).
///
/// [overrides] may add further provider overrides on top of the two above.
void testChoreApp(
  String description,
  Future<void> Function(WidgetTester tester, AppDatabase database) body, {
  required DateTime today,
  List<Override> overrides = const [],
}) {
  testWidgets(description, (tester) async {
    // Every test opens its own fresh in-memory AppDatabase, so drift's
    // "you've created this database class multiple times" warning (aimed
    // at accidental duplicate app databases sharing one executor) doesn't
    // apply here; silence it to keep test output readable.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    // A tall surface so a fully-expanded chore form (or a chores list with
    // several sections) lays out without needing to scroll to reach a
    // control under test.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(Clock.fixed(today)),
          ...overrides,
        ],
        child: const ChoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    await body(tester, database);

    await database.close();
  });
}

/// The id of the single household [testChoreApp] bootstraps.
Future<String> currentHouseholdId(AppDatabase database) async {
  final household = await database.select(database.households).getSingle();
  return household.id;
}
