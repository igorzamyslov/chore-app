import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

DateTime _fixedNow() => DateTime.utc(2026);

Future<String> _insertHousehold(AppDatabase db, String id) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  return id;
}

void main() {
  late AppDatabase db;
  late CategoryRepository repo;
  late String householdId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = CategoryRepository(db, newId: _IdGen().call, nowUtc: _fixedNow);
    householdId = await _insertHousehold(db, 'h1');
  });

  tearDown(() => db.close());

  group('seedDefaults', () {
    test('inserts the correct counts per kind and is idempotent', () async {
      await repo.seedDefaults(householdId);

      final choreCats = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      final shoppingCats = await repo
          .watchCategories(householdId, CategoryKind.shopping)
          .first;
      expect(choreCats, hasLength(7));
      expect(shoppingCats, hasLength(8));

      await repo.seedDefaults(householdId);

      final choreCatsAgain = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      final shoppingCatsAgain = await repo
          .watchCategories(householdId, CategoryKind.shopping)
          .first;
      expect(choreCatsAgain, hasLength(7));
      expect(shoppingCatsAgain, hasLength(8));
    });

    test('reseeds a kind independently once it becomes empty', () async {
      await repo.seedDefaults(householdId);
      final choreCats = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      for (final category in choreCats) {
        await repo.softDeleteCategory(category.id);
      }

      await repo.seedDefaults(householdId);

      final choreCatsAfter = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      final shoppingCatsAfter = await repo
          .watchCategories(householdId, CategoryKind.shopping)
          .first;
      expect(choreCatsAfter, hasLength(7));
      expect(shoppingCatsAfter, hasLength(8));
    });
  });

  group('softDeleteCategory', () {
    test(
      'nulls category_id on active chores/items and leaves others alone',
      () async {
        final categoryA = await repo.createCategory(
          householdId,
          kind: CategoryKind.chore,
          name: 'A',
          icon: 'a',
          color: 1,
        );
        final categoryB = await repo.createCategory(
          householdId,
          kind: CategoryKind.chore,
          name: 'B',
          icon: 'b',
          color: 2,
        );

        final choreRepo = ChoreRepository(
          db,
          newId: _IdGen().call,
          nowUtc: _fixedNow,
        );
        final chore = await choreRepo.createChore(
          householdId: householdId,
          title: 'Vacuum',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          categoryId: categoryA.id,
        );

        final shoppingRepo = ShoppingRepository(
          db,
          newId: _IdGen().call,
          nowUtc: _fixedNow,
        );
        final itemA = await shoppingRepo.addItem(
          householdId,
          name: 'Milk',
          categoryId: categoryA.id,
        );
        final itemB = await shoppingRepo.addItem(
          householdId,
          name: 'Eggs',
          categoryId: categoryB.id,
        );

        await repo.softDeleteCategory(categoryA.id);

        final choreRow = await (db.select(
          db.chores,
        )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
        expect(choreRow.categoryId, isNull);

        final itemARow = await (db.select(
          db.shoppingItems,
        )..where((tbl) => tbl.id.equals(itemA.id))).getSingle();
        expect(itemARow.categoryId, isNull);

        final itemBRow = await (db.select(
          db.shoppingItems,
        )..where((tbl) => tbl.id.equals(itemB.id))).getSingle();
        expect(itemBRow.categoryId, categoryB.id);

        final activeChoreCats = await repo
            .watchCategories(householdId, CategoryKind.chore)
            .first;
        expect(
          activeChoreCats.map((c) => c.id),
          isNot(contains(categoryA.id)),
        );
        expect(activeChoreCats.map((c) => c.id), contains(categoryB.id));
      },
    );
  });

  group('reorderCategories', () {
    test('persists the given order as 0-based sort_order', () async {
      await repo.seedDefaults(householdId);
      final before = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      final reversed = before.reversed.map((c) => c.id).toList();

      await repo.reorderCategories(householdId, CategoryKind.chore, reversed);

      final after = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      expect(after.map((c) => c.id).toList(), reversed);
      for (var i = 0; i < after.length; i++) {
        expect(after[i].sortOrder, i);
      }
    });

    test('throws ArgumentError and writes nothing for an unknown id', () async {
      await repo.seedDefaults(householdId);
      final before = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      final ids = [...before.map((c) => c.id), 'does-not-exist'];

      await expectLater(
        () => repo.reorderCategories(householdId, CategoryKind.chore, ids),
        throwsArgumentError,
      );

      final after = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      expect(after.map((c) => c.sortOrder), before.map((c) => c.sortOrder));
    });

    test(
      'throws ArgumentError for a category belonging to a different '
      'household',
      () async {
        await repo.seedDefaults(householdId);
        final otherHouseholdId = await _insertHousehold(db, 'h2');
        await repo.seedDefaults(otherHouseholdId);
        final otherChoreCats = await repo
            .watchCategories(otherHouseholdId, CategoryKind.chore)
            .first;

        await expectLater(
          () => repo.reorderCategories(householdId, CategoryKind.chore, [
            otherChoreCats.first.id,
          ]),
          throwsArgumentError,
        );
      },
    );

    test(
      'throws ArgumentError for a category of the wrong kind',
      () async {
        await repo.seedDefaults(householdId);
        final shoppingCats = await repo
            .watchCategories(householdId, CategoryKind.shopping)
            .first;

        await expectLater(
          () => repo.reorderCategories(householdId, CategoryKind.chore, [
            shoppingCats.first.id,
          ]),
          throwsArgumentError,
        );
      },
    );

    test('throws ArgumentError for a soft-deleted category', () async {
      await repo.seedDefaults(householdId);
      final before = await repo
          .watchCategories(householdId, CategoryKind.chore)
          .first;
      await repo.softDeleteCategory(before.first.id);

      await expectLater(
        () => repo.reorderCategories(householdId, CategoryKind.chore, [
          before.first.id,
        ]),
        throwsArgumentError,
      );
    });
  });
}
