/// Widget coverage for the B4 24h shopping auto-clear (see
/// `docs/specs/ux-round-2.md` B4): `bootstrapProvider` calls
/// `ShoppingRepository.clearCheckedOlderThan` with a cutoff of `clock.now()
/// - 24h`, so only items checked more than 24h before "now" are gone after
/// a restart. Boundary coverage of `clearCheckedOlderThan` itself (the
/// repository method in isolation) lives in `shopping_repository_test.dart`;
/// this test exercises the `bootstrapProvider` wiring end to end.
library;

import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<void> setCheckedAt(
    AppDatabase database,
    String id,
    DateTime checkedAt,
  ) {
    return (database.update(
      database.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).write(
      ShoppingItemsCompanion(checkedAt: Value(checkedAt.toIso8601String())),
    );
  }

  Future<bool> isDeleted(AppDatabase database, String id) async {
    final item = await (database.select(
      database.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).getSingle();
    return item.deletedAt != null;
  }

  testChoreApp(
    'restarting the app (bootstrap re-running) soft-deletes a checked item '
    'checked 25h ago, but leaves one checked 23h ago alone',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);

      final freshItem = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(freshItem.id, checked: true);
      await setCheckedAt(
        database,
        freshItem.id,
        today.toUtc().subtract(const Duration(hours: 23)),
      );

      final staleItem = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(staleItem.id, checked: true);
      await setCheckedAt(
        database,
        staleItem.id,
        today.toUtc().subtract(const Duration(hours: 25)),
      );

      // Simulate a cold restart: pump a fresh `ChoreApp` on the SAME
      // database, so `bootstrapProvider` (and its auto-clear step) runs
      // again, with the clock still fixed at the same "today".
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock.fixed(today)),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(await isDeleted(database, freshItem.id), isFalse);
      expect(await isDeleted(database, staleItem.id), isTrue);
    },
  );
}
