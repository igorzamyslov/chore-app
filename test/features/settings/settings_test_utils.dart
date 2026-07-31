/// Shared helper for settings widget tests.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selects the Settings tab in the already-pumped app shell.
///
/// Manages its own transient semantics handle (needed to look up
/// `shell.tab.settings`), independent of any handle the calling test also
/// holds for its own `find.bySemanticsIdentifier` assertions.
Future<void> openSettingsTab(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
  await tester.pumpAndSettle();
  handle.dispose();
}

/// Opens the Settings tab, then the manage-categories screen.
Future<void> openManageCategories(WidgetTester tester) async {
  await openSettingsTab(tester);
  final handle = tester.ensureSemantics();
  await tester.tap(find.bySemanticsIdentifier('settings.categories'));
  await tester.pumpAndSettle();
  handle.dispose();
}

/// Opens the Settings tab, then the manage-members screen.
Future<void> openManageMembers(WidgetTester tester) async {
  await openSettingsTab(tester);
  final handle = tester.ensureSemantics();
  await tester.tap(find.bySemanticsIdentifier('settings.members'));
  await tester.pumpAndSettle();
  handle.dispose();
}

/// A one-shot (non-streaming) read of [kind]'s active categories in
/// [householdId], in the same order `CategoryRepository.watchCategories`
/// returns (`sort_order` then name).
///
/// Deliberately NOT `CategoryRepository.watchCategories(...).first`:
/// opening a `.watch()` stream and immediately taking its first value races
/// the pumped screen's own identical-query stream subscription (both watch
/// the same table) and can deadlock drift's stream multiplexing under
/// `flutter test`. A plain one-shot `select` sidesteps that entirely.
Future<List<Category>> activeCategories(
  AppDatabase database,
  String householdId,
  CategoryKind kind,
) {
  return (database.select(database.categories)
        ..where(
          (tbl) =>
              tbl.householdId.equals(householdId) &
              tbl.kind.equalsValue(kind) &
              tbl.deletedAt.isNull(),
        )
        ..orderBy([
          (tbl) => OrderingTerm(expression: tbl.sortOrder),
          (tbl) => OrderingTerm(expression: tbl.name),
        ]))
      .get();
}
