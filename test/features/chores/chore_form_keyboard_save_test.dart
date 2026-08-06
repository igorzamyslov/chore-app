/// Regression test for C15
/// (`docs/feedback/2026-08-06-conventions-audit.md`): the chore form's Save
/// action must stay on screen while the on-screen keyboard is up.
///
/// `Scaffold` applies `resizeToAvoidBottomInset` to its BODY only — it lays
/// `bottomNavigationBar` out at the bottom of the SCREEN — so before the
/// fix this button sat behind the keyboard and vanished from the
/// accessibility tree entirely (verified on a Pixel emulator 2026-08-06).
/// A user who typed a title had no visible way to save.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the Save action stays above the on-screen keyboard (C15)',
    today: today,
    (tester, database) async {
      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      final save = find.bySemanticsIdentifier('chore_form.save');
      expect(save, findsOneWidget);
      final withoutKeyboard = tester.getRect(save);

      // Simulate the keyboard by inflating the view insets, exactly as the
      // platform does when a field gains focus.
      const keyboardHeight = 320.0;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboardHeight * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final withKeyboard = tester.getRect(save);

      expect(
        withKeyboard.bottom,
        lessThanOrEqualTo(screenHeight - keyboardHeight + 1),
        reason:
            'Save must sit ABOVE the keyboard, not behind it — otherwise a '
            'user who typed a title cannot see how to save',
      );
      expect(
        withKeyboard.top,
        lessThan(withoutKeyboard.top),
        reason: 'the bar should have moved up, not stayed put',
      );
    },
  );
}
