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

  testChoreApp(
    'the window rows are hidden while quiet hours are off and revealed when '
    'they are turned on',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Guard against the reveal assertion below passing for the wrong
      // reason: the rows must be genuinely absent first.
      expect(
        find.bySemanticsIdentifier('settings.quietHours.start'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.quietHours.end'),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier('settings.quietHours.toggle'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.quietHours.start'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.quietHours.end'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking a quiet-hours start persists it and re-renders the row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.quietHours.start'));
      await tester.pumpAndSettle();

      // The picker opens in `TimePickerEntryMode.input`: two
      // `TextFormField`s (hour, minute), deterministically driveable unlike
      // the dial.
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.quietStartMinutes, 9 * 60 + 30);
      // The end must NOT have moved: slice 1 exposes ONE window setter, so
      // the row that did not change has to pass its unchanged value through.
      expect(row.quietEndMinutes, 420);
      // 09:30 is the one time whose 12h render ("9:30 AM") and 24h render
      // ("09:30") share a substring -- these tests pump with no locale
      // override, so the host decides which one appears. Never assert a
      // 22:00-style default's digits.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.quietHours.start'),
          matching: find.textContaining('9:30'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking a quiet-hours end persists it independently of the start',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.quietHours.end'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.quietEndMinutes, 9 * 60 + 30);
      // The start must NOT have moved. With slice 1's single-setter API this
      // is the assertion that proves the End row passes the UNCHANGED start
      // alongside its own new value, rather than writing the picked minute
      // into both ends of the window.
      expect(row.quietStartMinutes, 1320);

      handle.dispose();
    },
  );

  // BINDING only in the sense that it is matched literally -- see the
  // comment in digest_section_test.dart: these tests pump with no locale
  // override, so the template ARB's text is what renders, and reading the
  // same AppLocalizations getter the widget reads would pass no matter
  // what that getter returned.
  const emptyWindowSubline = 'Start and end are the same — no quiet time';

  testChoreApp(
    'no empty-window sub-line while the window has a real length',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(database).setQuietHoursEnabled(enabled: true);
      await tester.pumpAndSettle();

      // The shipped 22:00-07:00 defaults.
      expect(find.text(emptyWindowSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a zero-length window says so on the toggle, and self-clears when '
    'either time moves',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      final settings = SettingsRepository(database);
      await settings.setQuietHoursEnabled(enabled: true);
      // Spec §6: start == end is OFF, not a 24-hour window. The switch
      // would otherwise sit in ON with nothing ever deferred.
      await settings.setQuietHours(startMinutes: 1320, endMinutes: 1320);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
          matching: find.text(emptyWindowSubline),
        ),
        findsOneWidget,
      );

      // Move ONLY the end, back to the shipped 07:00. A pure projection of
      // the two times: nothing stored, nothing to dismiss.
      await settings.setQuietHours(startMinutes: 1320, endMinutes: 420);
      await tester.pumpAndSettle();

      expect(find.text(emptyWindowSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'no empty-window sub-line while quiet hours are off, even with equal '
    'times',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      final settings = SettingsRepository(database);
      // Set the equal times while the feature is ON so the rows exist to
      // write through, then turn it off -- the stored times persist.
      await settings.setQuietHoursEnabled(enabled: true);
      await settings.setQuietHours(startMinutes: 1320, endMinutes: 1320);
      await tester.pumpAndSettle();
      // Guard: the sub-line must be present BEFORE the switch goes off, or
      // the findsNothing below proves nothing about the disabled case.
      expect(find.text(emptyWindowSubline), findsOneWidget);

      await settings.setQuietHoursEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(find.text(emptyWindowSubline), findsNothing);

      handle.dispose();
    },
  );
}
