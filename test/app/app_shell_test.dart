import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

void main() {
  testChoreApp(
    'three tabs render; switching swaps content and the shell keeps every '
    "visited tab's state alive",
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.shopping'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.settings'), findsOneWidget);

      // Chores is the default tab; the other two aren't shown yet.
      expect(find.bySemanticsIdentifier('settings.categories'), findsNothing);

      // The content is a PageView (backlog D-1: horizontal swipe between
      // tabs). Per-page keep-alive -- the property the old IndexedStack
      // provided -- is covered in test/app/shell_navigation_test.dart.
      expect(find.byType(PageView), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Shopping'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Settings'),
        ),
        findsOneWidget,
      );
      // The real settings screen (spec ux-round-2 B1), not a placeholder.
      expect(find.bySemanticsIdentifier('settings.categories'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Chores'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the active tab shows a primaryContainer pill behind its filled icon; '
    'inactive tabs show no pill (spec docs/specs/theme-v2.md §4.5)',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      Color? pillColorFor(String tabId) {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.bySemanticsIdentifier(tabId),
            matching: find.byType(Container),
          ),
        );
        return (container.decoration! as BoxDecoration).color;
      }

      final primaryContainer = Theme.of(
        tester.element(find.bySemanticsIdentifier('shell.tab.chores')),
      ).colorScheme.primaryContainer;

      // Chores is the default tab: it carries the pill, the others don't.
      expect(pillColorFor('shell.tab.chores'), primaryContainer);
      expect(pillColorFor('shell.tab.shopping'), Colors.transparent);
      expect(pillColorFor('shell.tab.settings'), Colors.transparent);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      // The pill moved with the selection.
      expect(pillColorFor('shell.tab.shopping'), primaryContainer);
      expect(pillColorFor('shell.tab.chores'), Colors.transparent);

      handle.dispose();
    },
  );
}
