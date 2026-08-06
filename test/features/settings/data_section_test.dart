import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's 'Data' section (spec
/// `docs/feedback/2026-08-01-field-feedback.md` B4/F7): a single section
/// header above the export row and the destructive reset row, grouped
/// together at the very bottom of Settings.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the Data section header is present, with the export row and the '
    'reset row both laid out beneath it in that order',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      // The group header is uppercased by `SettingsGroup` (spec
      // docs/specs/theme-v2.md §4.2: `Text(label.toUpperCase())`), so the
      // rendered text is 'DATA', not the ARB source's natural-case 'Data'.
      final header = find.text('DATA');
      expect(header, findsOneWidget);
      final exportRow = find.bySemanticsIdentifier('settings.export');
      final resetRow = find.bySemanticsIdentifier('settings.reset');
      expect(exportRow, findsOneWidget);
      expect(resetRow, findsOneWidget);

      // Layout order (top to bottom): header, then export, then reset --
      // matching `shopping_order_follows_reorder_test.dart`'s
      // `getTopLeft`-based ordering assertion, since there's no semantic id
      // on the plain section-header widget itself to assert tree order
      // via.
      final headerY = tester.getTopLeft(header).dy;
      final exportY = tester.getTopLeft(exportRow).dy;
      final resetY = tester.getTopLeft(resetRow).dy;
      expect(headerY, lessThan(exportY));
      expect(exportY, lessThan(resetY));

      handle.dispose();
    },
  );
}
