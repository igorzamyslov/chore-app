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
}
