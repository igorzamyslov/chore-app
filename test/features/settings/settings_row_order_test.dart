import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the notification rows render in the order spec §12 binds, in ONE '
    'group, with the permission hint last (decision D12: this order is the '
    'whole of the evening re-reminder discoverability and a later tidy-up '
    'must not undo it)',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Turn both features on so all eight rows exist simultaneously.
      final settings = SettingsRepository(database);
      await settings.setEveningReminderEnabled(enabled: true);
      await settings.setQuietHoursEnabled(enabled: true);
      // A surface tall enough that the whole Preferences group is laid out
      // at once: `getTopLeft` needs a render box, and a ListView does not
      // lay out children that are far off-screen. `testChoreApp` already
      // registered `tester.view.resetPhysicalSize` as a tear-down.
      tester.view.physicalSize = const Size(800, 4000);
      await tester.pumpAndSettle();

      const ids = [
        'settings.digest.toggle',
        'settings.digest.time',
        'settings.evening.toggle',
        'settings.evening.time',
        'settings.quietHours.toggle',
        'settings.quietHours.start',
        'settings.quietHours.end',
        'settings.digest.permission',
      ];

      final tops = <String, double>{};
      for (final id in ids) {
        final finder = find.bySemanticsIdentifier(id);
        expect(finder, findsOneWidget, reason: '$id must be on screen');
        tops[id] = tester.getTopLeft(finder.first).dy;
      }

      for (var i = 1; i < ids.length; i++) {
        expect(
          tops[ids[i]],
          greaterThan(tops[ids[i - 1]]!),
          reason: '${ids[i]} must render below ${ids[i - 1]}',
        );
      }

      // One group, not two (§12 forbids a second section header).
      //
      // NOT `expect(find.text('Daily summary'), findsNothing)`, which the
      // plan originally asked for and which CANNOT PASS: "Daily summary" is
      // also `settingsDigestToggleTitle`, the digest toggle ROW's own
      // label, so it is on screen in every correct implementation. What §12
      // actually forbids is a second GROUP, so assert that: all eight rows
      // are inside the one `SettingsGroup` that holds the digest toggle.
      final group = find.ancestor(
        of: find.bySemanticsIdentifier('settings.digest.toggle'),
        matching: find.byType(SettingsGroup),
      );
      expect(group, findsOneWidget);
      for (final id in ids) {
        expect(
          find.descendant(of: group, matching: find.bySemanticsIdentifier(id)),
          findsOneWidget,
          reason: '$id must be in the SAME group as the digest toggle',
        );
      }
      // ...and the orphan `settingsDigestSectionTitle` has not been revived
      // to found one. `SettingsGroup` uppercases its own label, so the
      // header a revival would render is 'DAILY SUMMARY' -- which, unlike
      // the natural-case string, appears nowhere today.
      expect(find.text('DAILY SUMMARY'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the permission hint is shown when the digest is OFF but the evening '
    're-reminder is ON and the OS permission is denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final settings = SettingsRepository(database);
      await settings.setDigestEnabled(enabled: false);
      await settings.setEveningReminderEnabled(enabled: true);
      await tester.pumpAndSettle();

      // Without this, a user whose only notification is the evening
      // re-reminder sees a switch in its ON position while nothing is
      // delivered -- the exact lie B-5 built this row to remove.
      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the permission hint stays hidden when both notifications are off, even '
    'with the permission denied',
    today: today,
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // Guard against the assertion below passing for the wrong reason: the
      // hint has to be there BEFORE the digest is turned off.
      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsOneWidget,
      );

      await SettingsRepository(database).setDigestEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.digest.permission'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
