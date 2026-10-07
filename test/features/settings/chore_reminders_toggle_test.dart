import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Persona review 2026-10-06 E3 (Leon A6): a device-level "Chore reminders"
/// master switch in the notifications group, bound to
/// `Settings.choreRemindersEnabled`.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  // Matched by literal English on purpose, as in `evening_section_test.dart`.
  const toggleLabel = 'Chore reminders';

  Switch switchOf(WidgetTester tester) => tester.widget<Switch>(
    find
        .descendant(
          of: find.bySemanticsIdentifier('settings.choreReminders.toggle'),
          matching: find.byType(Switch),
        )
        .first,
  );

  testChoreApp(
    'the row ships ON and is labelled "Chore reminders"',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final row = find.bySemanticsIdentifier('settings.choreReminders.toggle');
      expect(
        find.descendant(of: row, matching: find.text(toggleLabel)),
        findsOneWidget,
      );
      expect(switchOf(tester).value, isTrue);
      final stored = await database.select(database.settings).getSingle();
      expect(stored.choreRemindersEnabled, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'flipping the switch persists it both ways',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('settings.choreReminders.toggle'),
      );
      await tester.pumpAndSettle();
      var stored = await database.select(database.settings).getSingle();
      expect(stored.choreRemindersEnabled, isFalse);
      expect(switchOf(tester).value, isFalse);

      await tester.tap(
        find.bySemanticsIdentifier('settings.choreReminders.toggle'),
      );
      await tester.pumpAndSettle();
      stored = await database.select(database.settings).getSingle();
      expect(stored.choreRemindersEnabled, isTrue);

      handle.dispose();
    },
  );
}
