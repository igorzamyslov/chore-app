import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  // Matched by literal English on purpose: `testChoreApp` pumps the app
  // with no locale override, so the template ARB's text is what renders,
  // and a test that read the same `AppLocalizations` getter the widget
  // reads would pass no matter what that getter returned. Both strings are
  // BINDING copy (spec docs/specs/notifications-n2.md §5.1 / §11) -- if
  // this test has to change, the spec has to change first.
  const toggleLabel = 'Remind me again in the evening';
  const toggleSubtitle = 'Only if something is still open today';

  testChoreApp(
    'the evening re-reminder ships OFF (decision D12)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.evening.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isFalse);

      final row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderEnabled, isFalse);
      expect(row.eveningReminderMinutes, 1200);

      handle.dispose();
    },
  );

  testChoreApp(
    'the row is labelled for the problem, not the mechanism, and carries '
    'its condition as a sub-line whether it is on or off',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final row = find.bySemanticsIdentifier('settings.evening.toggle');
      expect(
        find.descendant(of: row, matching: find.text(toggleLabel)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(toggleSubtitle)),
        findsOneWidget,
      );
      // The feature's name in the spec must not become the name of the row.
      expect(find.textContaining('re-reminder'), findsNothing);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: row, matching: find.text(toggleSubtitle)),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'turning the evening re-reminder on persists it, and off again',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.evening.toggle'));
      await tester.pumpAndSettle();
      var row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderEnabled, isTrue);

      await tester.tap(find.bySemanticsIdentifier('settings.evening.toggle'));
      await tester.pumpAndSettle();
      row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'the switch reflects a value written outside the widget',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await SettingsRepository(
        database,
      ).setEveningReminderEnabled(enabled: true);
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.evening.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isTrue);

      handle.dispose();
    },
  );
}
