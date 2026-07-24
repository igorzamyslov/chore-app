import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'kind switcher toggles between chore and shopping categories',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openManageCategories(tester);

      expect(find.text('Cleaning'), findsOneWidget);
      expect(find.text('Produce'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.kind.shopping'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Produce'), findsOneWidget);
      expect(find.text('Cleaning'), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.kind.chore'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cleaning'), findsOneWidget);
      expect(find.text('Produce'), findsNothing);

      handle.dispose();
    },
  );
}
