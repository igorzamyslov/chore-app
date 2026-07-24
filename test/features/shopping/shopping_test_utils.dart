/// Shared helper for shopping widget tests.
library;

import 'package:flutter_test/flutter_test.dart';

/// Selects the Shopping tab in the already-pumped app shell.
///
/// Manages its own transient semantics handle (needed to look up
/// `shell.tab.shopping`), independent of any handle the calling test also
/// holds for its own `find.bySemanticsIdentifier` assertions.
Future<void> openShoppingTab(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
  await tester.pumpAndSettle();
  handle.dispose();
}
