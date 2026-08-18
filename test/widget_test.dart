import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Every test opens its own fresh in-memory AppDatabase, so drift's
  // "you've created this database class multiple times" warning doesn't
  // apply here; silence it to keep test output readable.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'bootstrap: loading indicator, then the welcome gate (spec '
    'docs/specs/onboarding-v2.md: a fresh install with no household shows '
    'WelcomeScreen, not the chores list)',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(
              Clock.fixed(DateTime(2026, 7, 24, 9)),
            ),
          ],
          child: const ChoreApp(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsIdentifier('welcome.create'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      handle.dispose();

      await database.close();
    },
  );

  testWidgets('bootstrap error renders the error state', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    // Establishes the connection, then severs it, so the very first
    // bootstrap query throws — simulating a startup failure without
    // mocking anything.
    await database.select(database.households).getSingleOrNull();
    await database.close();

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          clockProvider.overrideWithValue(
            Clock.fixed(DateTime(2026, 7, 24, 9)),
          ),
        ],
        child: const ChoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('app.bootstrap_error'), findsOneWidget);
    handle.dispose();
  });
}
