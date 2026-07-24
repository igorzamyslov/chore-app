/// Manages chore/shopping categories, including v1's seeded defaults.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A default category's seed name and Material Symbols icon identifier.
typedef _CategorySeed = ({String name, String icon});

/// Repository for chore and shopping categories.
class CategoryRepository {
  /// Creates a repository backed by [db].
  ///
  /// [newId] and [nowUtc] are injectable so tests can supply deterministic
  /// ids and a controllable clock; they default to a random UUIDv4
  /// generator and the real UTC clock, respectively.
  CategoryRepository(
    this.db, {
    this.newId = _defaultNewId,
    this.nowUtc = _defaultNowUtc,
  });

  /// Eight distinct, muted ARGB colors assigned to seeded default
  /// categories, in order.
  static const List<int> seedColors = [
    0xFF6D9F71, // muted green
    0xFF8C7BC9, // muted purple
    0xFFD98E73, // muted terracotta
    0xFF5FA8B8, // muted teal-blue
    0xFFC98CA7, // muted rose
    0xFFB8A15F, // muted ochre
    0xFF7B93C9, // muted blue
    0xFFA9A9A9, // muted gray
  ];

  static const List<_CategorySeed> _choreSeeds = [
    (name: 'Cleaning', icon: 'cleaning_services'),
    (name: 'Kitchen', icon: 'skillet'),
    (name: 'Laundry', icon: 'local_laundry_service'),
    (name: 'Garden', icon: 'yard'),
    (name: 'Pets', icon: 'pets'),
    (name: 'Maintenance', icon: 'build'),
    (name: 'Errands', icon: 'directions_car'),
  ];

  static const List<_CategorySeed> _shoppingSeeds = [
    (name: 'Produce', icon: 'nutrition'),
    (name: 'Dairy', icon: 'egg'),
    (name: 'Meat & Fish', icon: 'set_meal'),
    (name: 'Bakery', icon: 'bakery_dining'),
    (name: 'Frozen', icon: 'ac_unit'),
    (name: 'Drinks', icon: 'local_cafe'),
    (name: 'Household', icon: 'home'),
    (name: 'Other', icon: 'shopping_bag'),
  ];

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Generates the id for a newly inserted row.
  final String Function() newId;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Inserts the default chore and shopping category sets, one kind at a
  /// time and only if [householdId] doesn't already have active categories
  /// of that kind.
  ///
  /// Idempotent per kind: re-running this only fills in whichever kind is
  /// still empty.
  Future<void> seedDefaults(String householdId) async {
    await _seedKind(householdId, CategoryKind.chore, _choreSeeds);
    await _seedKind(householdId, CategoryKind.shopping, _shoppingSeeds);
  }

  /// Watches active categories of [kind] in [householdId], ordered by
  /// sort order then name.
  Stream<List<Category>> watchCategories(
    String householdId,
    CategoryKind kind,
  ) {
    final query = db.select(db.categories)
      ..where(
        (tbl) =>
            tbl.householdId.equals(householdId) &
            tbl.kind.equalsValue(kind) &
            tbl.deletedAt.isNull(),
      )
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.sortOrder),
        (tbl) => OrderingTerm(expression: tbl.name),
      ]);
    return query.watch();
  }

  /// Creates a new category in [householdId].
  Future<Category> createCategory(
    String householdId, {
    required CategoryKind kind,
    required String name,
    required String icon,
    required int color,
    int sortOrder = 0,
  }) async {
    final now = _isoNow();
    final id = newId();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            householdId: householdId,
            kind: kind,
            name: name,
            icon: icon,
            color: color,
            sortOrder: Value(sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return Category(
      id: id,
      householdId: householdId,
      kind: kind,
      name: name,
      icon: icon,
      color: color,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Updates the given fields of an existing category; omitted (`null`)
  /// fields are left unchanged.
  ///
  /// None of this category's fields are nullable in the schema, so a plain
  /// `null` unambiguously means "don't change this field" — unlike
  /// `ChoreRepository.updateChore` or `ShoppingRepository.updateItem`, no
  /// `Value`-wrapped parameter is needed here.
  Future<void> updateCategory(
    String id, {
    String? name,
    String? icon,
    int? color,
    int? sortOrder,
  }) async {
    await (db.update(
      db.categories,
    )..where((tbl) => tbl.id.equals(id))).write(
      CategoriesCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        icon: icon != null ? Value(icon) : const Value.absent(),
        color: color != null ? Value(color) : const Value.absent(),
        sortOrder: sortOrder != null ? Value(sortOrder) : const Value.absent(),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Soft-deletes a category and, in the same transaction, clears
  /// `categoryId` on every active chore and shopping item that referenced
  /// it.
  Future<void> softDeleteCategory(String id) async {
    final now = _isoNow();
    await db.transaction(() async {
      await (db.update(
        db.categories,
      )..where((tbl) => tbl.id.equals(id))).write(
        CategoriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (db.update(db.chores)..where(
            (tbl) => tbl.categoryId.equals(id) & tbl.deletedAt.isNull(),
          ))
          .write(
            ChoresCompanion(
              categoryId: const Value(null),
              updatedAt: Value(now),
            ),
          );
      await (db.update(db.shoppingItems)..where(
            (tbl) => tbl.categoryId.equals(id) & tbl.deletedAt.isNull(),
          ))
          .write(
            ShoppingItemsCompanion(
              categoryId: const Value(null),
              updatedAt: Value(now),
            ),
          );
    });
  }

  /// Persists a manual sort order for [orderedCategoryIds] in a single
  /// transaction: category `orderedCategoryIds[i]` is written `sortOrder:
  /// i` (0-based).
  ///
  /// Every id in [orderedCategoryIds] must be an active category of [kind]
  /// in [householdId]; otherwise throws [ArgumentError] before writing
  /// anything (validated first, inside the same transaction).
  ///
  /// The chore/shopping lists both already sort by `sort_order`, so this is
  /// the only write manual drag-to-reorder needs (spec
  /// `docs/specs/ux-round-2.md` B1).
  Future<void> reorderCategories(
    String householdId,
    CategoryKind kind,
    List<String> orderedCategoryIds,
  ) async {
    await db.transaction(() async {
      final rows = await (db.select(
        db.categories,
      )..where((tbl) => tbl.id.isIn(orderedCategoryIds))).get();
      final rowsById = {for (final row in rows) row.id: row};
      for (final id in orderedCategoryIds) {
        final row = rowsById[id];
        if (row == null ||
            row.householdId != householdId ||
            row.kind != kind ||
            row.deletedAt != null) {
          throw ArgumentError.value(
            orderedCategoryIds,
            'orderedCategoryIds',
            "'$id' is not an active $kind category of household "
                "'$householdId'",
          );
        }
      }
      final now = _isoNow();
      for (var i = 0; i < orderedCategoryIds.length; i++) {
        await (db.update(
          db.categories,
        )..where((tbl) => tbl.id.equals(orderedCategoryIds[i]))).write(
          CategoriesCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        );
      }
    });
  }

  Future<void> _seedKind(
    String householdId,
    CategoryKind kind,
    List<_CategorySeed> seeds,
  ) async {
    final activeCount = await _activeCount(householdId, kind);
    if (activeCount > 0) {
      return;
    }
    final now = _isoNow();
    await db.transaction(() async {
      for (var i = 0; i < seeds.length; i++) {
        final seed = seeds[i];
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: newId(),
                householdId: householdId,
                kind: kind,
                name: seed.name,
                icon: seed.icon,
                color: seedColors[i % seedColors.length],
                sortOrder: Value(i),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<int> _activeCount(String householdId, CategoryKind kind) async {
    final rows =
        await (db.select(db.categories)..where(
              (tbl) =>
                  tbl.householdId.equals(householdId) &
                  tbl.kind.equalsValue(kind) &
                  tbl.deletedAt.isNull(),
            ))
            .get();
    return rows.length;
  }

  String _isoNow() => nowUtc().toIso8601String();
}

String _defaultNewId() => const Uuid().v4();

DateTime _defaultNowUtc() => DateTime.now().toUtc();
