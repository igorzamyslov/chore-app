import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  testChoreApp(
    'empty state appears when nothing is pending',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('chores.empty'), findsOneWidget);
      expect(find.bySemanticsIdentifier('chores.add'), findsOneWidget);

      handle.dispose();
    },
  );
}
