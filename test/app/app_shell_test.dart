import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

void main() {
  testChoreApp(
    'three tabs render; switching swaps content and IndexedStack '
    "preserves each tab's state",
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.shopping'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.settings'), findsOneWidget);

      // Chores is the default tab; the other two aren't shown yet.
      expect(find.text('Shopping — coming soon'), findsNothing);
      expect(find.text('Settings — coming soon'), findsNothing);

      // IndexedStack keeps every tab's widget subtree alive at all times
      // (rather than rebuilding it on selection), so it should already be
      // present offstage.
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.children, hasLength(3));

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      expect(find.text('Shopping — coming soon'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings — coming soon'), findsOneWidget);
      expect(find.text('Shopping — coming soon'), findsNothing);

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
}
