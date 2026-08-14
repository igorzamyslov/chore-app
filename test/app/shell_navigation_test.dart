import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/settings/settings_screen.dart';
import 'package:chore_app/features/shopping/shopping_list_screen.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

/// Shell navigation conventions (backlog D-1 / D-4 / D-6, conventions audit
/// C6, field feedback 2026-08-07 B3).
///
/// Kept in its own file rather than appended to `app_shell_test.dart` so
/// that file stays a stable target for the other planned edits to
/// `lib/app/app_shell.dart` (see
/// `docs/plans/2026-08-08-shell-navigation.md`, "Coordination with in-flight
/// plans").
void main() {
  final today = DateTime(2026, 7, 22, 9);

  /// Drags the shell's [PageView] by [dx] logical pixels and settles.
  ///
  /// The test surface is 800 logical pixels wide (`pump_app.dart`), and
  /// `WidgetTester.drag` imparts no fling velocity -- so `PageScrollPhysics`
  /// settles purely on the fractional page offset. 500 px is 0.625 of a
  /// page, comfortably clear of the 0.5 rounding knife-edge in both
  /// directions.
  Future<void> dragPage(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(PageView), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  /// Delivers the platform's `popRoute` message — what the Android system
  /// back gesture/button actually sends the engine.
  Future<void> pressSystemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'swiping right-to-left walks forward through the tabs, and left-to-right '
    'walks back (backlog D-1)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      await dragPage(tester, -500);
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.add'), findsNothing);

      await dragPage(tester, -500);
      expect(find.bySemanticsIdentifier('settings.categories'), findsOneWidget);

      await dragPage(tester, 500);
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsOneWidget);

      await dragPage(tester, 500);
      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping past the first tab does nothing (no wrap-around)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await dragPage(tester, 500);

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a visited tab keeps its in-flight state after leaving and coming back, '
    'and contributes nothing to the semantics tree while off screen',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      // `enterText` resolves the EditableText inside the identified
      // Semantics wrapper (WidgetTester.showKeyboard uses a matchRoot
      // descendant finder), so the semantic id is a valid target here.
      await tester.enterText(
        find.bySemanticsIdentifier('shopping.add.input'),
        'Milk',
      );
      await tester.pumpAndSettle();

      // CRITICAL: drop focus before leaving. `EditableText` mixes in
      // `AutomaticKeepAliveClientMixin` with `wantKeepAlive => hasFocus`, so
      // a focused text field keeps its own page alive all by itself. Leaving
      // the field focused made every assertion below pass even with
      // `_KeepAlivePage.wantKeepAlive` hard-coded to `false` -- verified on
      // CI, not assumed. Unfocusing removes that confound so what follows
      // tests the shell's keep-alive and nothing else.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // The State object itself, so "kept alive" means "the same State",
      // not merely "a widget of this type is findable".
      final stateBefore = tester
          .element<StatefulElement>(
            find.byType(ShoppingListScreen, skipOffstage: false),
          )
          .state;

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();

      // Kept alive: still in the element tree, but off stage...
      expect(
        find.byType(ShoppingListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(ShoppingListScreen), findsNothing);
      // ...and, critically, invisible to semantics. This is the regression
      // guard for `allowImplicitScrolling`: setting it true would lay the
      // neighbouring page out inside the viewport's semantics clip and leak
      // these ids into every `find.bySemanticsIdentifier` and every Maestro
      // `assertVisible`.
      expect(find.bySemanticsIdentifier('shopping.add.input'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      // The half-typed item survived the round trip -- the exact property
      // the old IndexedStack provided (spec docs/specs/ui-shopping.md) --
      // and it survived because the very same State was kept, not because
      // an identical-looking screen was rebuilt from the database.
      expect(find.text('Milk'), findsOneWidget);
      expect(
        tester
            .element<StatefulElement>(
              find.byType(ShoppingListScreen, skipOffstage: false),
            )
            .state,
        same(stateBefore),
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'swiping to another tab clears the snackbar shown on the tab being left, '
    'but re-tapping the CURRENT tab does not',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Re-tapping the tab you're already on isn't "leaving" it, so the
      // UNDO the user may still want stays put (field feedback B1 is about
      // a toast following you to ANOTHER tab).
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Swiping away is leaving, and clears it exactly like a tab tap does
      // (test/app/snackbar_tab_switch_test.dart covers the tap path).
      await dragPage(tester, -500);
      expect(find.byType(SnackBar), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    're-tapping the tab you are already on scrolls its list back to the top '
    '(conventions audit C6 / backlog D-4)',
    today: today,
    (tester, database) async {
      // The shared surface is 2400 px tall so forms lay out without
      // scrolling; shrink it here so the Settings list actually overflows
      // and has somewhere to scroll to. `pump_app.dart` already registered
      // the tear-down that restores it.
      tester.view.physicalSize = const Size(400, 700);
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      // `.first` guards against a future nested scrollable inside the
      // Settings subtree turning this into an ambiguous finder.
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(0));

      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      expect(position.pixels, 0);

      handle.dispose();
    },
  );

  testChoreApp(
    'each tab gets its own scroll controller: scrolling one tab and '
    "re-tapping another leaves the first tab's position alone",
    today: today,
    (tester, database) async {
      tester.view.physicalSize = const Size(400, 700);
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final scrolled = position.pixels;
      expect(scrolled, greaterThan(0));

      // Leave, re-tap the OTHER tab twice (a switch, then a scroll-to-top
      // on that tab), then come back.
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      expect(position.pixels, scrolled);

      handle.dispose();
    },
  );

  testChoreApp(
    'system back on a non-first tab returns to Chores instead of leaving the '
    'app (backlog D-6)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('settings.categories'), findsOneWidget);

      await pressSystemBack(tester);

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);
      expect(find.bySemanticsIdentifier('settings.categories'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'system back on the first tab is not intercepted — it leaves the app '
    '(Material: back exits from the start destination)',
    today: today,
    (tester, database) async {
      final platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final handle = tester.ensureSemantics();

      // Go away and come back, so the tab really is "first" rather than
      // merely "never left".
      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();

      await pressSystemBack(tester);

      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);
      expect(
        platformCalls.map((call) => call.method),
        contains('SystemNavigator.pop'),
      );

      handle.dispose();
    },
  );
}
