import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's Appearance row/picker sheet
/// (spec `docs/feedback/2026-08-01-field-feedback.md` G2).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    "the appearance row's subtitle shows System before any choice is made",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      final row = find.bySemanticsIdentifier('settings.appearance');
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('System')),
        findsOneWidget,
      );
      // The app itself follows the OS theme until a choice is made.
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.system);

      handle.dispose();
    },
  );

  testChoreApp(
    'picking Dark in the sheet persists it, updates the row subtitle, and '
    "flips the pumped app's MaterialApp.themeMode to dark",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.appearance'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.appearance.sheet'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.appearance.dark'));
      await tester.pumpAndSettle();

      // The sheet closed...
      expect(
        find.bySemanticsIdentifier('settings.appearance.sheet'),
        findsNothing,
      );

      // ...the row's own subtitle now reads 'Dark'...
      final row = find.bySemanticsIdentifier('settings.appearance');
      expect(
        find.descendant(of: row, matching: find.text('Dark')),
        findsOneWidget,
      );

      // ...the choice persisted to the settings row...
      final settings = await database.select(database.settings).getSingle();
      expect(settings.themeMode, 'dark');

      // ...and the pumped app's own MaterialApp reflects it, the same way
      // `language_and_about_test.dart` asserts the locale override by
      // reading the live app's own state rather than the provider alone.
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);

      handle.dispose();
    },
  );

  testChoreApp(
    'picking System after Dark was chosen clears the stored value and '
    'flips the app back to ThemeMode.system',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).setThemeMode('dark');
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.appearance'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.appearance.system'),
      );
      await tester.pumpAndSettle();

      final row = find.bySemanticsIdentifier('settings.appearance');
      expect(
        find.descendant(of: row, matching: find.text('System')),
        findsOneWidget,
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.themeMode, isNull);

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.system);

      handle.dispose();
    },
  );
}
