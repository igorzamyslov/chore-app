import 'package:chore_app/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'digest section: enabled by default, time row shown, no permission hint',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // `DigestToggleTile` renders as a `SettingsRow` with a trailing
      // `Switch` (spec docs/specs/theme-v2.md §4.2), not the old
      // `SwitchListTile`.
      final toggle = tester.widget<Switch>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.digest.toggle'),
              matching: find.byType(Switch),
            )
            .first,
      );
      expect(toggle.value, isTrue);
      expect(
        find.bySemanticsIdentifier('settings.digest.time'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'toggling the digest off hides the time row and persists the change',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.digest.time'),
        findsNothing,
      );

      final row = await database.select(database.settings).getSingle();
      expect(row.digestEnabled, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'toggling the digest back on shows the time row again, time preserved',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.digest.time'),
        findsOneWidget,
      );
      final row = await database.select(database.settings).getSingle();
      expect(row.digestEnabled, isTrue);
      expect(row.digestMinutes, 480);

      handle.dispose();
    },
  );

  testChoreApp(
    'permission hint shows only while enabled and the OS permission is '
    'denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      // Disabling the digest hides the hint even though permission is
      // still denied — the hint only makes sense while the digest itself
      // is turned on.
      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'permission hint stays hidden when the OS permission is granted',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  // Backlog B-5: the switch sitting in its ON position while nothing is
  // being delivered is the lie this sub-line removes. Matched by its
  // literal English copy on purpose -- `testChoreApp` pumps the app with
  // no locale override, so the template ARB's text is what renders, and a
  // test that read the same `AppLocalizations` getter the widget reads
  // would pass no matter what that getter returned.
  const deniedSubline = 'Not delivering — notifications are off';

  testChoreApp(
    'toggle grows a "not delivering" sub-line when enabled but the OS '
    'permission is denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text(deniedSubline),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'toggle sub-line stays hidden while the permission is granted',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text(deniedSubline),
        ),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'toggle sub-line stays hidden when the digest itself is off, even with '
    'the permission denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Guard against this assertion passing for the wrong reason: the
      // sub-line has to be there BEFORE the toggle is flipped, or
      // `findsNothing` below proves nothing about the digest-off case.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text(deniedSubline),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text(deniedSubline),
        ),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'time picker round trip: picking a new time updates the row and '
    'persists it',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.digest.time'));
      await tester.pumpAndSettle();

      // The picker opens in `TimePickerEntryMode.input`: two `TextFormField`s
      // (hour, minute), deterministically driveable unlike the dial.
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.first, '9');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final row = await database.select(database.settings).getSingle();
      expect(row.digestMinutes, 9 * 60 + 30);

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.time'),
          matching: find.textContaining('9:30'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
