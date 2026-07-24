/// Manages the household's shared shopping list.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A shopping item joined with its resolved category.
class ShoppingItemWithCategory {
  /// Creates a shopping item detail view.
  const ShoppingItemWithCategory({required this.item, this.category});

  /// The shopping item row itself.
  final ShoppingItem item;

  /// The item's category, or `null` if uncategorized.
  final Category? category;
}

/// Repository for the household's shared shopping list.
class ShoppingRepository {
  /// Creates a repository backed by [db].
  ///
  /// [newId] and [nowUtc] are injectable so tests can supply deterministic
  /// ids and a controllable clock; they default to a random UUIDv4
  /// generator and the real UTC clock, respectively.
  ShoppingRepository(
    this.db, {
    this.newId = _defaultNewId,
    this.nowUtc = _defaultNowUtc,
  });

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Generates the id for a newly inserted row.
  final String Function() newId;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Watches every active item in [householdId], both checked and
  /// unchecked, ordered: unchecked first, then by category sort order,
  /// then by name.
  Stream<List<ShoppingItemWithCategory>> watchActiveItems(
    String householdId,
  ) {
    final query =
        db.select(db.shoppingItems).join([
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.shoppingItems.categoryId),
            ),
          ])
          ..where(
            db.shoppingItems.householdId.equals(householdId) &
                db.shoppingItems.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.shoppingItems.checkedAt.isNull(),
              mode: OrderingMode.desc,
            ),
            OrderingTerm(expression: db.categories.sortOrder),
            OrderingTerm(expression: db.shoppingItems.name),
          ]);

    return query.watch().map((rows) {
      return [
        for (final row in rows)
          ShoppingItemWithCategory(
            item: row.readTable(db.shoppingItems),
            category: row.readTableOrNull(db.categories),
          ),
      ];
    });
  }

  /// Adds a new item to [householdId]'s shopping list.
  Future<ShoppingItem> addItem(
    String householdId, {
    required String name,
    String? quantityNote,
    String? categoryId,
    String? addedBy,
  }) async {
    final now = _isoNow();
    final id = newId();
    await db
        .into(db.shoppingItems)
        .insert(
          ShoppingItemsCompanion.insert(
            id: id,
            householdId: householdId,
            name: name,
            quantityNote: Value(quantityNote),
            categoryId: Value(categoryId),
            addedBy: Value(addedBy),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return ShoppingItem(
      id: id,
      householdId: householdId,
      name: name,
      quantityNote: quantityNote,
      categoryId: categoryId,
      addedBy: addedBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Updates the given fields of an existing item.
  ///
  /// [name] is a plain "leave unchanged if omitted" parameter.
  /// [quantityNote] and [categoryId] are themselves nullable in the
  /// schema, so a bare `null` would be ambiguous between "unchanged" and
  /// "clear it"; they use drift's `Value` wrapper instead — omit the
  /// parameter (default `Value.absent()`) to leave it unchanged, or pass
  /// `Value(null)` to write `NULL`.
  Future<void> updateItem(
    String id, {
    String? name,
    Value<String?> quantityNote = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
  }) async {
    await (db.update(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).write(
      ShoppingItemsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        quantityNote: quantityNote,
        categoryId: categoryId,
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Checks or unchecks an item.
  Future<void> setChecked(String id, {required bool checked}) async {
    final now = _isoNow();
    await (db.update(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).write(
      ShoppingItemsCompanion(
        checkedAt: Value(checked ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Soft-deletes a single item immediately.
  ///
  /// Unlike a chore delete, this isn't gated behind a confirmation dialog —
  /// shopping items are cheap and low-stakes (see
  /// `docs/specs/design-language.md`).
  Future<void> deleteItem(String id) async {
    final now = _isoNow();
    await (db.update(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).write(
      ShoppingItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Soft-deletes every active, checked item in [householdId].
  Future<void> clearChecked(String householdId) async {
    final now = _isoNow();
    await (db.update(db.shoppingItems)..where(
          (tbl) =>
              tbl.householdId.equals(householdId) &
              tbl.deletedAt.isNull() &
              tbl.checkedAt.isNotNull(),
        ))
        .write(
          ShoppingItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
  }

  String _isoNow() => nowUtc().toIso8601String();
}

String _defaultNewId() => const Uuid().v4();

DateTime _defaultNowUtc() => DateTime.now().toUtc();
