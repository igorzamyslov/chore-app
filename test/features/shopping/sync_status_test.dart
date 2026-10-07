/// Persona findings F1/F10 (the app-bar status line) and E10 (the "waiting to
/// send" glyph on a dirty row) -- see `docs/specs/ui-shopping.md` amendments
/// 2026-10-06 and 2026-10-07 (the per-row added-by mark was removed).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// A linked, signed-in stand-in: anything that is not [NoopSyncEngine] makes
/// the screens treat the household as linked (`syncEngineProvider`'s own
/// contract), without any network or timer.
class _LinkedEngine implements SyncEngine {
  @override
  Future<void> pushDirty() async {}

  @override
  Future<void> pullSince() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<RefreshOutcome> refreshNow() async => RefreshOutcome.ok;

  @override
  void pauseBackgroundWork() {}

  @override
  void resumeBackgroundWork() {}
}

Override get _linked => syncEngineProvider.overrideWithValue(_LinkedEngine());

Override _pulledAt(DateTime at) =>
    syncLastPullCompletedAtProvider.overrideWith((ref) => at);

Override _pending(int count) =>
    syncPendingCountProvider.overrideWith((ref) => Stream.value(count));

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder status() => find.bySemanticsIdentifier('shopping.status');

  testChoreApp(
    'status line: unlinked shows only how many items are left (F1)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Milk');
      await repo.addItem(householdId, name: 'Bread');
      final eggs = await repo.addItem(householdId, name: 'Eggs');
      await repo.setChecked(eggs.id, checked: true);

      await openShoppingTab(tester);

      expect(find.text('2 left'), findsOneWidget);
      expect(find.textContaining('synced'), findsNothing);
      expect(find.textContaining('waiting'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: an empty list says nothing is left',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      expect(find.text('Nothing left'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: linked with nothing waiting adds "synced <relative>" (F10)',
    today: today,
    overrides: [
      _linked,
      _pulledAt(DateTime(2026, 7, 24, 8, 55)),
      _pending(0),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      expect(find.text('1 left · synced 5 min ago'), findsOneWidget);
      expect(status(), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: linked with changes waiting shows the pending count '
    'instead of the synced time',
    today: today,
    overrides: [
      _linked,
      _pulledAt(DateTime(2026, 7, 24, 8, 55)),
      _pending(2),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      expect(find.text('1 left · 2 changes waiting to send'), findsOneWidget);
      expect(find.textContaining('synced'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: linked but never pulled this session shows only the count',
    today: today,
    overrides: [_linked, _pending(0)],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      expect(find.text('1 left'), findsOneWidget);

      handle.dispose();
    },
  );
}
