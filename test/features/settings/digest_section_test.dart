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

      final toggle = tester.widget<SwitchListTile>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.digest.toggle'),
              matching: find.byType(SwitchListTile),
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
