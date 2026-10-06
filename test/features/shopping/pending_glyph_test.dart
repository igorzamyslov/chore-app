/// Persona finding E10: the "waiting to send" glyph on a dirty shopping row
/// while the household is linked -- see `docs/specs/ui-shopping.md`
/// amendment 2026-10-06.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
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

Override _pending(int count) =>
    syncPendingCountProvider.overrideWith((ref) => Stream.value(count));

void main() {
  final today = DateTime(2026, 7, 24, 9);

  group('waiting-to-send glyph (E10)', () {
    Finder glyphIn(String itemId) => find.descendant(
      of: find.bySemanticsIdentifier('shopping.item.$itemId'),
      matching: find.byIcon(Icons.schedule),
    );

    testChoreApp(
      'linked: a dirty row shows the glyph with a tooltip; a clean row '
      'does not',
      today: today,
      overrides: [_linked, _pending(1)],
      (tester, database) async {
        final handle = tester.ensureSemantics();
        final householdId = await currentHouseholdId(database);
        final repo = ShoppingRepository(database);
        final dirty = await repo.addItem(householdId, name: 'Milk');
        final clean = await repo.addItem(householdId, name: 'Bread');
        await (database.update(
          database.shoppingItems,
        )..where((tbl) => tbl.id.equals(clean.id))).write(
          const ShoppingItemsCompanion(syncDirty: Value(false)),
        );

        await openShoppingTab(tester);

        expect(glyphIn(dirty.id), findsOneWidget);
        expect(glyphIn(clean.id), findsNothing);
        expect(
          find.descendant(
            of: find.bySemanticsIdentifier('shopping.item.${dirty.id}'),
            matching: find.byTooltip('Waiting to send'),
          ),
          findsOneWidget,
        );
        expect(
          tester.getSize(glyphIn(dirty.id)),
          const Size(14, 14),
        );

        handle.dispose();
      },
    );

    testChoreApp(
      'unlinked: a dirty row shows no glyph (nothing is ever sent)',
      today: today,
      (tester, database) async {
        final handle = tester.ensureSemantics();
        final householdId = await currentHouseholdId(database);
        final dirty = await ShoppingRepository(
          database,
        ).addItem(householdId, name: 'Milk');

        await openShoppingTab(tester);

        expect(glyphIn(dirty.id), findsNothing);

        handle.dispose();
      },
    );
  });
}
