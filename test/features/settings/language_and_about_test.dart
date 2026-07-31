import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's Language row/picker sheet and
/// About section (spec `docs/next-session-plan.md` #5).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Chores (mock)',
      packageName: 'com.example.chore_app',
      version: '9.9.9',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  testChoreApp(
    "the language row's subtitle shows System default before any choice "
    'is made',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final row = find.bySemanticsIdentifier('settings.language');
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('System default')),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'picking Deutsch in the sheet flips a visible UI string to German in '
    'the same pumped app, updates the row subtitle, and persists across a '
    'simulated app restart',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.language'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.language.sheet'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('settings.language.sheet.de'),
      );
      await tester.pumpAndSettle();

      // The sheet closed...
      expect(
        find.bySemanticsIdentifier('settings.language.sheet'),
        findsNothing,
      );

      // ...and the settings screen itself is now in German: its own
      // language row title (settingsLanguageEntry) flips from 'Language'
      // to 'Sprache', and its subtitle now reads 'Deutsch'.
      final row = find.bySemanticsIdentifier('settings.language');
      expect(
        find.descendant(of: row, matching: find.text('Sprache')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Deutsch')),
        findsOneWidget,
      );

      // Simulated restart: pump a brand-new widget tree/ProviderScope over
      // the exact same, still-open in-memory database (pattern:
      // test/features/chores/acting_member_widget_test.dart).
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock.fixed(today)),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      await openSettingsTab(tester);
      final rowAfterRestart = find.bySemanticsIdentifier('settings.language');
      expect(
        find.descendant(of: rowAfterRestart, matching: find.text('Sprache')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowAfterRestart,
          matching: find.text('Deutsch'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    "the About section's version row shows the mocked app name and "
    'version/build number',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final row = find.bySemanticsIdentifier('settings.about.version');
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('9.9.9'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('42')),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'tapping the licenses row opens the license page',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.about.licenses'));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'the donate placeholder row is disabled',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final tile = tester.widget<ListTile>(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.about.donate'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);

      handle.dispose();
    },
  );
}
