import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'both themes render the manage-categories screen without exceptions',
    today: today,
    (tester, database) async {
      await openManageCategories(tester);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Manage categories'),
        ),
        findsOneWidget,
      );
    },
  );

  testChoreApp(
    'text scale 2.0 renders the list and edit sheet without overflow '
    'exceptions',
    today: today,
    (tester, database) async {
      await openManageCategories(tester);

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
