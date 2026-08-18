import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../test_utils/pump_app.dart';
import 'fake_url_launcher_platform.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's Language row/picker sheet and
/// About section (spec `docs/next-session-plan.md` #5).
void main() {
  final today = DateTime(2026, 7, 24, 9);
  final fakeUrlLauncher = FakeUrlLauncherPlatform();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Famdo (mock)',
      packageName: 'io.github.igorzamyslov.famdo',
      version: '9.9.9',
      buildNumber: '42',
      buildSignature: '',
    );
    fakeUrlLauncher.reset();
    UrlLauncherPlatform.instance = fakeUrlLauncher;
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
    'the donate row is enabled and opens a sheet with Ko-fi and PayPal '
    'links',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // `AboutDonateTile` renders as a `SettingsRow` (spec
      // docs/specs/theme-v2.md §4.2), not the old `ListTile` -- its own
      // `onTap` isn't publicly inspectable, so assert the tap actually
      // opens the sheet below instead of reading a widget field.
      expect(
        find.bySemanticsIdentifier('settings.about.donate'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.about.donate'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.about.donate.sheet'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.about.donate.kofi'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.about.donate.paypal'),
        findsOneWidget,
      );

      // Tapping the Ko-fi row launches its URL externally and closes the
      // sheet; the launching boundary is faked (fakeUrlLauncher), so no
      // real OS "open URL" action happens.
      await tester.tap(
        find.bySemanticsIdentifier('settings.about.donate.kofi'),
      );
      await tester.pumpAndSettle();

      expect(fakeUrlLauncher.lastLaunchedUrl, 'https://ko-fi.com/igorzamyslov');
      expect(
        fakeUrlLauncher.lastOptions?.mode,
        PreferredLaunchMode.externalApplication,
      );
      expect(
        find.bySemanticsIdentifier('settings.about.donate.sheet'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
