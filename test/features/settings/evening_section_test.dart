import 'package:chore_app/data/db/app_database.dart';
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

  // BINDING copy, spec docs/specs/notifications-n2.md §6 and §5.1, matched
  // literally for the same reason as the labels above.
  const collisionSubline = 'Inside your quiet hours — not delivering';

  /// Enables the evening re-reminder at [eveningMinutes], and quiet hours
  /// over [start]..[end] when [quietEnabled], then settles.
  Future<void> configure(
    WidgetTester tester,
    AppDatabase database, {
    required int eveningMinutes,
    required bool quietEnabled,
    int start = 1320,
    int end = 420,
  }) async {
    final settings = SettingsRepository(database);
    await settings.setEveningReminderEnabled(enabled: true);
    await settings.setEveningReminderTime(eveningMinutes);
    await settings.setQuietHoursEnabled(enabled: quietEnabled);
    await settings.setQuietHours(startMinutes: start, endMinutes: end);
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'the evening time row is hidden while the toggle is off and revealed '
    'when it is turned on',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(find.bySemanticsIdentifier('settings.evening.time'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('settings.evening.toggle'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.evening.time'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking an evening time persists it and re-renders the row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await SettingsRepository(
        database,
      ).setEveningReminderEnabled(enabled: true);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('settings.evening.time'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.eveningReminderMinutes, 9 * 60 + 30);
      // See quiet_hours_section_test.dart: 9:30 is the one time whose 12h
      // and 24h renders share a substring.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.evening.time'),
          matching: find.textContaining('9:30'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'no collision sub-line while quiet hours are off, even at a time that '
    'would be inside the window',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // 23:00, squarely inside 22:00-07:00 -- but quiet hours are off.
      await configure(
        tester,
        database,
        eveningMinutes: 1380,
        quietEnabled: false,
      );

      expect(find.text(collisionSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'no collision sub-line with the shipped defaults (20:00 evening, '
    '22:00-07:00 quiet hours)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      await configure(
        tester,
        database,
        eveningMinutes: 1200,
        quietEnabled: true,
      );

      // Spec §5.1: "the shipped defaults do not collide", so a user turning
      // the feature on with defaults gets a working feature and no sub-line.
      expect(find.text(collisionSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the collision sub-line appears when the evening time falls inside the '
    'window, and self-clears when the window moves off it',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // Spec §5.1's own example: quiet hours from 21:00, evening at 21:30.
      await configure(
        tester,
        database,
        eveningMinutes: 1290,
        quietEnabled: true,
        start: 1260,
      );

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.evening.time'),
          matching: find.text(collisionSubline),
        ),
        findsOneWidget,
      );

      // Move ONLY the quiet-hours start, to 22:00 (the end stays at the
      // 07:00 `configure` left it at). The sub-line is a pure projection of
      // the two settings -- no stored flag -- so it must vanish with no
      // other change and nothing to dismiss.
      await SettingsRepository(
        database,
      ).setQuietHours(startMinutes: 1320, endMinutes: 420);
      await tester.pumpAndSettle();

      expect(find.text(collisionSubline), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the collision sub-line appears for an evening time on the far side of '
    'midnight (06:00 inside a 22:00-07:00 window)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // 06:00 is inside the shipped wrapping window even though 360 < 1320.
      // A non-wrapping `start <= m <= end` comparison reports it as
      // outside, and this assertion is what catches that.
      await configure(
        tester,
        database,
        eveningMinutes: 360,
        quietEnabled: true,
      );

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.evening.time'),
          matching: find.text(collisionSubline),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'an EMPTY quiet-hours window never reports the evening time as inside '
    'it: the two sub-lines are mutually exclusive by construction',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      // start == end == the evening time itself -- the most adversarial
      // arrangement available. §6 makes a zero-length window OFF, so
      // isWithinQuietHours is false for EVERY minute including this one,
      // and the evening row must stay clean.
      await configure(
        tester,
        database,
        eveningMinutes: 1200,
        quietEnabled: true,
        start: 1200,
        end: 1200,
      );

      expect(find.text(collisionSubline), findsNothing);
      // The empty-window line (Task 2, OD2) is what speaks instead, and it
      // speaks on a DIFFERENT row -- so the two can never contend for one
      // `sublabel` slot.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.quietHours.toggle'),
          matching: find.text('Start and end are the same — no quiet time'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
