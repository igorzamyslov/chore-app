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

      final handle = tester.ensureSemantics();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Backlog A-6: the loading state must be IDENTIFIABLE from outside the
      // process, not merely visible. Both of the app's white startup screens
      // -- iOS's LaunchScreen.storyboard and this scaffold -- photograph
      // identically, so a screenshot cannot tell whether Dart ever reached
      // `runApp`. And without an id this scaffold contributes ZERO
      // accessibility nodes (`Scaffold` makes none, and
      // `CircularProgressIndicator` wraps itself in a `Semantics` whose
      // label and value are both null, which is dropped), so an E2E
      // hierarchy dump of a hung startup is empty either way. This id is the
      // discriminator between "the engine never presented" and "the engine
      // presented and the household gate never resolved".
      expect(find.bySemanticsIdentifier('app.loading'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('welcome.create'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      handle.dispose();

      await database.close();
    },
  );

  testWidgets(
    'bootstrap error renders a headline, the raw detail, and retry + reset '
    'actions (spec docs/feedback/2026-08-08-prerelease-audit.md S2: a '
    'database-open failure must not brick the app permanently)',
    (tester) async {
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

      // The raw exception stays on screen (this app ships with no crash
      // reporting, so a screenshot is the only bug report there is), but a
      // plain-language headline is now what reads first.
      expect(find.bySemanticsIdentifier('app.bootstrap_error'), findsOneWidget);
      expect(find.text("We couldn't open your data"), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('app.bootstrap_error.retry'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('app.bootstrap_error.reset'),
        findsOneWidget,
      );

      // Retry re-invalidates the gate provider: the database is still
      // closed, so the SAME error screen must reappear rather than crash
      // the test with an unhandled exception.
      await tester.tap(find.bySemanticsIdentifier('app.bootstrap_error.retry'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('app.bootstrap_error'), findsOneWidget);

      // The reset escape hatch opens the SAME double-confirm dialog
      // Settings uses (`settings.reset.*` ids); with the database closed,
      // the wipe itself fails, which must surface as an inline message
      // rather than crash the app.
      await tester.tap(find.bySemanticsIdentifier('app.bootstrap_error.reset'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.reset.confirm1'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't reset your data. Please try again."),
        findsOneWidget,
      );

      // Let the snackbar's own 4s auto-dismiss timer fire before the test
      // ends, so nothing is left pending.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      handle.dispose();
    },
  );
}
