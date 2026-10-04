import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// The About section's "Send error reports" switch (spec
/// `docs/specs/client-error-reporting.md` §6).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Switch switchOf(WidgetTester tester) => tester.widget<Switch>(
    find
        .descendant(
          of: find.bySemanticsIdentifier('settings-error-reports-switch'),
          matching: find.byType(Switch),
        )
        .first,
  );

  testChoreApp(
    'the switch is shown (also signed out), starts on, and toggles '
    'Settings.errorReportsEnabled both ways',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);
      final row = find.bySemanticsIdentifier('settings-error-reports-switch');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Send error reports'), findsOneWidget);
      expect(switchOf(tester).value, isTrue);
      expect(
        (await SettingsRepository(
          database,
        ).ensureSettings()).errorReportsEnabled,
        isTrue,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(switchOf(tester).value, isFalse);
      expect(
        (await SettingsRepository(
          database,
        ).ensureSettings()).errorReportsEnabled,
        isFalse,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(switchOf(tester).value, isTrue);
      expect(
        (await SettingsRepository(
          database,
        ).ensureSettings()).errorReportsEnabled,
        isTrue,
      );

      handle.dispose();
    },
  );
}
