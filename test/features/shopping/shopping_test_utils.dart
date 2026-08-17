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

/// Expands the collapsed-by-default 'In the cart' section by tapping its
/// header, whose text (`label`) carries the live checked count — e.g.
/// `'In the cart (1)'`.
///
/// Lives here rather than as a per-file local because three files now need
/// it (`cart_section_test.dart`, `swipe_delete_test.dart`,
/// `long_press_menu_test.dart`): every gesture on an item row has to be
/// exercised on a checked row too, and checked rows are only reachable
/// through this header.
Future<void> expandCartSection(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
