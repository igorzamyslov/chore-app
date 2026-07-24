import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

class _FixedClock {
  _FixedClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  late AppDatabase db;
  late ShoppingRepository repo;
  late _FixedClock clock;
  const householdId = 'h1';

  Future<ShoppingItem> row(String id) => (db.select(
    db.shoppingItems,
  )..where((tbl) => tbl.id.equals(id))).getSingle();

  Future<Category> createCategory({
    required String id,
    required String name,
    required int sortOrder,
  }) async {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            householdId: householdId,
            kind: CategoryKind.shopping,
            name: name,
            icon: 'icon',
            color: 1,
            sortOrder: Value(sortOrder),
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
    return (db.select(
      db.categories,
    )..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = _FixedClock(DateTime.utc(2026));
    repo = ShoppingRepository(db, newId: _IdGen().call, nowUtc: clock.call);
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            id: householdId,
            name: 'H',
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
  });

  tearDown(() => db.close());

  test(
    'watchActiveItems orders unchecked-first, then category sort_order, '
    'then name',
    () async {
      final catLow = await createCategory(
        id: 'cat-low',
        name: 'Produce',
        sortOrder: 0,
      );
      final catHigh = await createCategory(
        id: 'cat-high',
        name: 'Dairy',
        sortOrder: 1,
      );

      await repo.addItem(householdId, name: 'Zucchini', categoryId: catLow.id);
      await repo.addItem(householdId, name: 'Apples', categoryId: catLow.id);
      final checkedItem = await repo.addItem(
        householdId,
        name: 'Bananas',
        categoryId: catLow.id,
      );
      await repo.setChecked(checkedItem.id, checked: true);
      await repo.addItem(householdId, name: 'Milk', categoryId: catHigh.id);

      final items = await repo.watchActiveItems(householdId).first;
      expect(
        [for (final i in items) i.item.name],
        ['Apples', 'Zucchini', 'Milk', 'Bananas'],
      );
    },
  );

  test('setChecked toggles checked_at', () async {
    final item = await repo.addItem(householdId, name: 'Bread');
    expect(item.checkedAt, isNull);

    await repo.setChecked(item.id, checked: true);
    expect((await row(item.id)).checkedAt, isNotNull);

    await repo.setChecked(item.id, checked: false);
    expect((await row(item.id)).checkedAt, isNull);
  });

  test('clearChecked only soft-deletes checked active items', () async {
    final checkedItem = await repo.addItem(householdId, name: 'A');
    final uncheckedItem = await repo.addItem(householdId, name: 'B');
    await repo.setChecked(checkedItem.id, checked: true);

    await repo.clearChecked(householdId);

    expect((await row(checkedItem.id)).deletedAt, isNotNull);
    expect((await row(uncheckedItem.id)).deletedAt, isNull);

    final active = await repo.watchActiveItems(householdId).first;
    expect(
      active.map((i) => i.item.id),
      isNot(contains(checkedItem.id)),
    );
    expect(active.map((i) => i.item.id), contains(uncheckedItem.id));
  });

  test('updateItem supports the Value-wrapped nullable fields', () async {
    final item = await repo.addItem(
      householdId,
      name: 'A',
      quantityNote: 'x2',
    );

    await repo.updateItem(item.id, name: 'A renamed');
    expect((await row(item.id)).quantityNote, 'x2');

    await repo.updateItem(item.id, quantityNote: const Value(null));
    expect((await row(item.id)).quantityNote, isNull);

    await repo.updateItem(item.id, quantityNote: const Value('x3'));
    expect((await row(item.id)).quantityNote, 'x3');
  });

  test('updated_at is bumped on every mutation', () async {
    final item = await repo.addItem(householdId, name: 'A');

    clock.advance(const Duration(minutes: 1));
    await repo.updateItem(item.id, name: 'A2');
    final afterUpdate = (await row(item.id)).updatedAt;
    expect(afterUpdate, isNot(item.updatedAt));

    clock.advance(const Duration(minutes: 1));
    await repo.setChecked(item.id, checked: true);
    final afterChecked = (await row(item.id)).updatedAt;
    expect(afterChecked, isNot(afterUpdate));

    clock.advance(const Duration(minutes: 1));
    await repo.clearChecked(householdId);
    final afterClear = (await row(item.id)).updatedAt;
    expect(afterClear, isNot(afterChecked));
  });

  group('clearCheckedOlderThan', () {
    test(
      'soft-deletes an active checked item whose checked_at is older than '
      'the cutoff (checked 25h ago, 24h cutoff)',
      () async {
        final item = await repo.addItem(householdId, name: 'Milk');
        await repo.setChecked(item.id, checked: true);
        await (db.update(db.shoppingItems)..where(
              (tbl) => tbl.id.equals(item.id),
            ))
            .write(
              ShoppingItemsCompanion(
                checkedAt: Value(
                  clock
                      .call()
                      .subtract(const Duration(hours: 25))
                      .toIso8601String(),
                ),
              ),
            );

        await repo.clearCheckedOlderThan(
          householdId,
          cutoffUtc: clock.call().subtract(const Duration(hours: 24)),
        );

        expect((await row(item.id)).deletedAt, isNotNull);
      },
    );

    test(
      'keeps an active checked item whose checked_at is within the cutoff '
      'window (checked 23h ago, 24h cutoff)',
      () async {
        final item = await repo.addItem(householdId, name: 'Milk');
        await repo.setChecked(item.id, checked: true);
        await (db.update(db.shoppingItems)..where(
              (tbl) => tbl.id.equals(item.id),
            ))
            .write(
              ShoppingItemsCompanion(
                checkedAt: Value(
                  clock
                      .call()
                      .subtract(const Duration(hours: 23))
                      .toIso8601String(),
                ),
              ),
            );

        await repo.clearCheckedOlderThan(
          householdId,
          cutoffUtc: clock.call().subtract(const Duration(hours: 24)),
        );

        expect((await row(item.id)).deletedAt, isNull);
      },
    );

    test('leaves unchecked items alone regardless of cutoff', () async {
      final item = await repo.addItem(householdId, name: 'Bread');

      await repo.clearCheckedOlderThan(
        householdId,
        cutoffUtc: clock.call().add(const Duration(days: 1)),
      );

      expect((await row(item.id)).deletedAt, isNull);
    });

    test('ignores items already soft-deleted', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(item.id, checked: true);
      await repo.deleteItem(item.id);
      final deletedAtBeforeClear = (await row(item.id)).deletedAt;

      await repo.clearCheckedOlderThan(
        householdId,
        cutoffUtc: clock.call().add(const Duration(days: 1)),
      );

      expect((await row(item.id)).deletedAt, deletedAtBeforeClear);
    });
  });

  group('normalizeShoppingItemName', () {
    test('trims, lowercases, and collapses inner whitespace', () {
      expect(normalizeShoppingItemName('  Milk  '), 'milk');
      expect(normalizeShoppingItemName('Oat   Milk'), 'oat milk');
      expect(normalizeShoppingItemName('MILK'), 'milk');
      expect(normalizeShoppingItemName('   '), '');
    });
  });

  group('suggestions', () {
    test(
      'ranks by frequency first, then recency, deduplicating by '
      'normalized name',
      () async {
        // "Milk" added twice (frequency 2), "Milkshake" once (frequency 1)
        // but most recent overall — frequency must still win.
        await repo.addItem(householdId, name: 'Milk');
        clock.advance(const Duration(minutes: 1));
        await repo.addItem(householdId, name: 'milk');
        clock.advance(const Duration(minutes: 1));
        await repo.addItem(householdId, name: 'Milkshake');

        final results = await repo.suggestions(householdId, 'mil');
        expect(results.map((s) => s.name), ['milk', 'Milkshake']);
      },
    );

    test(
      'among equal frequency, ranks the more recently-created name first',
      () async {
        await repo.addItem(householdId, name: 'Milk');
        clock.advance(const Duration(minutes: 1));
        await repo.addItem(householdId, name: 'Mint');

        final results = await repo.suggestions(householdId, 'mi');
        expect(results.map((s) => s.name), ['Mint', 'Milk']);
      },
    );

    test(
      'includes soft-deleted (cleared) items from the household history',
      () async {
        final item = await repo.addItem(householdId, name: 'Milk');
        await repo.deleteItem(item.id);

        final results = await repo.suggestions(householdId, 'mi');
        expect(results.map((s) => s.name), ['Milk']);
      },
    );

    test(
      'resolves the most recent non-null category, even if a later row '
      'had none',
      () async {
        final dairy = await createCategory(
          id: 'dairy',
          name: 'Dairy',
          sortOrder: 0,
        );
        await repo.addItem(householdId, name: 'Milk', categoryId: dairy.id);
        clock.advance(const Duration(minutes: 1));
        // Most recent row for "milk" has no category; the earlier one does.
        await repo.addItem(householdId, name: 'Milk');

        final results = await repo.suggestions(householdId, 'milk');
        expect(results, hasLength(1));
        expect(results.single.categoryId, dairy.id);
        expect(results.single.category?.name, 'Dairy');
      },
    );

    test('matches only names starting with the (normalized) prefix', () async {
      await repo.addItem(householdId, name: 'Milk');
      await repo.addItem(householdId, name: 'Oat milk');

      final results = await repo.suggestions(householdId, 'MI');
      expect(results.map((s) => s.name), ['Milk']);
    });

    test('returns nothing for a blank/whitespace-only prefix', () async {
      await repo.addItem(householdId, name: 'Milk');

      expect(await repo.suggestions(householdId, '   '), isEmpty);
    });

    test('caps results at limit', () async {
      for (var i = 0; i < 10; i++) {
        await repo.addItem(householdId, name: 'Item $i');
      }

      final results = await repo.suggestions(householdId, 'item');
      expect(results, hasLength(8));
    });
  });

  group('findActiveByNormalizedName', () {
    test('matches active items regardless of case/whitespace', () async {
      await repo.addItem(householdId, name: 'Oat   Milk');

      final found = await repo.findActiveByNormalizedName(
        householdId,
        'oat milk',
      );
      expect(found?.item.name, 'Oat   Milk');
    });

    test('ignores soft-deleted items', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.deleteItem(item.id);

      expect(
        await repo.findActiveByNormalizedName(householdId, 'milk'),
        isNull,
      );
    });

    test('matches regardless of checked state', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(item.id, checked: true);

      final found = await repo.findActiveByNormalizedName(
        householdId,
        'milk',
      );
      expect(found?.item.id, item.id);
      expect(found?.item.checkedAt, isNotNull);
    });

    test('returns null when there is no match', () async {
      expect(
        await repo.findActiveByNormalizedName(householdId, 'milk'),
        isNull,
      );
    });
  });

  group('mostRecentCategoryIdForNormalizedName', () {
    test('returns the most recent non-null category from history', () async {
      final dairy = await createCategory(
        id: 'dairy',
        name: 'Dairy',
        sortOrder: 0,
      );
      final produce = await createCategory(
        id: 'produce',
        name: 'Produce',
        sortOrder: 1,
      );
      await repo.addItem(householdId, name: 'Milk', categoryId: dairy.id);
      clock.advance(const Duration(minutes: 1));
      await repo.addItem(householdId, name: 'Milk', categoryId: produce.id);

      expect(
        await repo.mostRecentCategoryIdForNormalizedName(householdId, 'milk'),
        produce.id,
      );
    });

    test(
      'falls back to an earlier non-null category when the most recent '
      'row has none',
      () async {
        final dairy = await createCategory(
          id: 'dairy',
          name: 'Dairy',
          sortOrder: 0,
        );
        await repo.addItem(householdId, name: 'Milk', categoryId: dairy.id);
        clock.advance(const Duration(minutes: 1));
        await repo.addItem(householdId, name: 'Milk');

        expect(
          await repo.mostRecentCategoryIdForNormalizedName(
            householdId,
            'milk',
          ),
          dairy.id,
        );
      },
    );

    test('includes soft-deleted rows from history', () async {
      final dairy = await createCategory(
        id: 'dairy',
        name: 'Dairy',
        sortOrder: 0,
      );
      final item = await repo.addItem(
        householdId,
        name: 'Milk',
        categoryId: dairy.id,
      );
      await repo.deleteItem(item.id);

      expect(
        await repo.mostRecentCategoryIdForNormalizedName(householdId, 'milk'),
        dairy.id,
      );
    });

    test(
      'returns null when no row for this name ever had a category',
      () async {
        await repo.addItem(householdId, name: 'Milk');

        expect(
          await repo.mostRecentCategoryIdForNormalizedName(householdId, 'milk'),
          isNull,
        );
      },
    );
  });
}
