/// Shared helper for shopping widget tests.
library;

import 'package:chore_app/features/shopping/shopping_list_screen.dart';
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

/// Opens the edit sheet for the item row showing [label], by LONG-PRESSING
/// it.
///
/// A helper rather than a bare `longPress` at each call site, so the gesture
/// that reaches the edit sheet is written down in exactly one place. It used
/// to be a plain tap; the 2026-09-19 field report moved ticking onto the
/// row's tap and editing onto its long-press (see `docs/specs/ui-shopping.md`
/// §"Amendment 2026-09-19"). A stray `tap` left behind in one of these files
/// would now silently tick the item and then assert against an edit sheet
/// that never opened — a confusing failure a long way from its cause.
Future<void> openItemMenu(WidgetTester tester, String label) async {
  await tester.longPress(find.text(label));
  await tester.pumpAndSettle();
}

/// Expands the collapsed-by-default 'In the cart' section by tapping its
/// header, whose text (`label`) carries the live checked count — e.g.
/// `'In the cart (1)'`.
///
/// Lives here rather than as a per-file local because several files need it
/// (`cart_section_test.dart`, `row_swipe_pages_test.dart`,
/// `row_tap_toggles_test.dart`, `long_press_menu_test.dart`): every gesture
/// on an item row has to be exercised on a checked row too, and checked rows
/// are only reachable through this header.
Future<void> expandCartSection(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Settles the tick beat: a row that was just ticked or unticked stays in
/// the section it was already in for [shoppingCheckedMoveDelay] before it
/// moves (field report 2026-09-19).
///
/// Use this, not a bare `pumpAndSettle`, after any tap that toggles an item
/// when the assertion that follows depends on the row having MOVED.
/// `pumpAndSettle` only keeps pumping while a frame is scheduled, so whether
/// it happens to outlast the beat depends on how long the tapped `InkWell`'s
/// ink splash animates — which is a `ThemeData.splashFactory` detail and no
/// business of these tests. Waiting the beat out explicitly makes the
/// outcome depend on the beat and nothing else.
Future<void> settleTickBeat(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(
    shoppingCheckedMoveDelay + const Duration(milliseconds: 50),
  );
  await tester.pumpAndSettle();
}
