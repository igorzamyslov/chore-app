import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'quiet hours ships OFF: the switch is off and no window rows are shown',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isFalse);

      final row = await database.select(database.settings).getSingle();
      expect(row.quietHoursEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'turning quiet hours on persists it, and turning it off persists that too',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.quietHours.toggle'),
      );
      await tester.pumpAndSettle();
      var row = await database.select(database.settings).getSingle();
      expect(row.quietHoursEnabled, isTrue);
      // The shipped window is what goes live the moment the switch does
      // (spec notifications-n2.md §8.1: 22:00-07:00).
      expect(row.quietStartMinutes, 1320);
      expect(row.quietEndMinutes, 420);

      await tester.tap(
        find.bySemanticsIdentifier('settings.quietHours.toggle'),
      );
      await tester.pumpAndSettle();
      row = await database.select(database.settings).getSingle();
      expect(row.quietHoursEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'the quiet-hours switch reflects a value written outside the widget',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isTrue);

      handle.dispose();
    },
  );
}
