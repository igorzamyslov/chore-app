/// Manages the household's shared shopping list.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/db/sync_dirty.dart';
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

/// A ranked type-ahead suggestion for the shopping quick-add field: one
/// distinct normalized name from the household's full add history
/// (including soft-deleted items), paired with the most recent non-null
/// category ever used for it.
///
/// Returned by [ShoppingRepository.suggestions]; see
/// `docs/specs/ux-round-2.md` B2.
class ShoppingSuggestion {
  /// Creates a suggestion.
  const ShoppingSuggestion({
    required this.name,
    this.categoryId,
    this.category,
  });

  /// The most recently used casing of this normalized name.
  final String name;

  /// The most recent non-null category id ever used for this normalized
  /// name, or `null` if no history row for it ever set one.
  final String? categoryId;

  /// [categoryId] resolved to a [Category], or `null` if [categoryId] is
  /// `null`.
  final Category? category;
}

/// One shopping item row paired with its resolved category, as read
/// directly off a join — the shared shape [ShoppingRepository.suggestions],
/// [ShoppingRepository.findActiveByNormalizedName], and
/// [ShoppingRepository.mostRecentCategoryIdForNormalizedName] all group and
/// filter in Dart.
typedef _HistoryRow = ({ShoppingItem item, Category? category});

/// Normalizes a shopping item name for matching and deduplication: trims
/// leading/trailing whitespace, lowercases, and collapses runs of inner
/// whitespace to a single space.
///
/// Shared by [ShoppingRepository.suggestions] (prefix matching),
/// [ShoppingRepository.findActiveByNormalizedName] (B3 duplicate
/// detection), and the quick-add row (to normalize its own input before
/// calling either). See `docs/specs/ux-round-2.md` B2/B3.
String normalizeShoppingItemName(String name) {
  return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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

  /// Returns up to [limit] suggestions for [prefix]: distinct normalized
  /// names (from ALL items ever added in [householdId], including
  /// soft-deleted ones) whose normalized form starts with [prefix]'s
  /// normalized form, ranked by frequency (row count for that normalized
  /// name) then recency (latest `created_at`).
  ///
  /// Each suggestion carries the most recent casing seen for its normalized
  /// name, plus the most recent non-null category used for it (which may
  /// come from an earlier row than the most recent one, if the most recent
  /// row itself had no category). Returns an empty list if [prefix] is
  /// non-empty but normalizes to the empty string (e.g. it's
  /// whitespace-only) — that's the type-ahead path (spec
  /// `docs/specs/ux-round-2.md` B2), and there's nothing meaningful to
  /// match there.
  ///
  /// A literal empty [prefix] (not whitespace — the field genuinely has no
  /// text) is the *focus-suggestions* path instead (field feedback F1,
  /// `docs/feedback/2026-08-01-field-feedback.md`): every name matches (no
  /// prefix filtering), but a name is excluded when either:
  /// - ANY of its rows is an active (non-deleted) item currently in
  ///   [householdId] — checked or unchecked — since surfacing something
  ///   already visible on the same screen is noise, or
  /// - its MOST RECENT row (by `created_at`) was deleted while still
  ///   unchecked (`deleted_at != null && checked_at == null`): the user
  ///   explicitly removed it from the list without buying it, so
  ///   re-offering it is unwanted (field feedback round 2, bug 1,
  ///   `docs/feedback/2026-08-01-field-feedback.md`).
  ///
  /// A name whose most recent row was instead checked off and THEN
  /// deleted (`checked_at != null`, i.e. cleared after shopping via
  /// [clearChecked]) stays eligible — re-suggesting staples already bought
  /// is the whole point of this feature. Because only the most recent row
  /// decides the second rule, adding the name again later (a newer row)
  /// makes it eligible again regardless of an earlier explicit deletion.
  ///
  /// The non-empty-prefix (type-ahead) path deliberately keeps including
  /// active items, and never applies the deleted-while-unchecked
  /// exclusion above: retyping an item that's already on the list is how
  /// a user reaches the existing "already on the list" / "moved back to
  /// the list" duplicate-prevention flow (spec B3), and changing that
  /// would regress it.
  Future<List<ShoppingSuggestion>> suggestions(
    String householdId,
    String prefix, {
    int limit = 8,
  }) async {
    final normalizedPrefix = normalizeShoppingItemName(prefix);
    if (prefix.isNotEmpty && normalizedPrefix.isEmpty) {
      return const [];
    }

    final rows = await _historyRows(householdId);
    final excludedNormalizedNames = prefix.isEmpty
        ? _namesToExcludeFromFocusSuggestions(rows)
        : const <String>{};

    final groups = <String, List<_HistoryRow>>{};
    for (final row in rows) {
      final normalized = normalizeShoppingItemName(row.item.name);
      if (!normalized.startsWith(normalizedPrefix) ||
          excludedNormalizedNames.contains(normalized)) {
        continue;
      }
      groups.putIfAbsent(normalized, () => []).add(row);
    }

    final ranked =
        <({ShoppingSuggestion suggestion, int frequency, DateTime recency})>[];
    for (final group in groups.values) {
      group.sort(
        (a, b) => DateTime.parse(
          b.item.createdAt,
        ).compareTo(DateTime.parse(a.item.createdAt)),
      );
      final mostRecent = group.first;
      final mostRecentWithCategory = group.firstWhere(
        (row) => row.item.categoryId != null,
        orElse: () => mostRecent,
      );
      ranked.add((
        suggestion: ShoppingSuggestion(
          name: mostRecent.item.name,
          categoryId: mostRecentWithCategory.item.categoryId,
          category: mostRecentWithCategory.category,
        ),
        frequency: group.length,
        recency: DateTime.parse(mostRecent.item.createdAt),
      ));
    }

    ranked.sort((a, b) {
      final byFrequency = b.frequency.compareTo(a.frequency);
      return byFrequency != 0 ? byFrequency : b.recency.compareTo(a.recency);
    });

    return [for (final entry in ranked.take(limit)) entry.suggestion];
  }

  /// Computes the set of normalized names to exclude from the
  /// focus-suggestions (empty-prefix) path of [suggestions], for the two
  /// independent reasons spelled out in [suggestions]' doc comment: ANY
  /// row of the name is still active (on the list right now), or the
  /// name's MOST RECENT row (by `created_at`) was deleted while unchecked
  /// (explicitly removed without being bought — field feedback round 2,
  /// bug 1). A name whose most recent row was checked-then-deleted
  /// (cleared after shopping) is left eligible.
  Set<String> _namesToExcludeFromFocusSuggestions(List<_HistoryRow> rows) {
    final excluded = <String>{};
    final mostRecentByName = <String, _HistoryRow>{};
    for (final row in rows) {
      final normalized = normalizeShoppingItemName(row.item.name);
      // Reason 1 — still on the list. Tested against EVERY row, not just
      // the name's most recent one: B3 duplicate prevention normally keeps
      // at most one active row per name (and it is the newest), but "never
      // propose something the user can already see on this screen" must
      // not silently depend on an invariant enforced in another feature.
      if (row.item.deletedAt == null) {
        excluded.add(normalized);
      }
      final current = mostRecentByName[normalized];
      if (current == null ||
          DateTime.parse(
            row.item.createdAt,
          ).isAfter(DateTime.parse(current.item.createdAt))) {
        mostRecentByName[normalized] = row;
      }
    }
    // Reason 2 — explicitly removed without ever being bought. Only the
    // most recent row decides this, so adding the name again later (a
    // newer row) makes it eligible again.
    for (final entry in mostRecentByName.entries) {
      final item = entry.value.item;
      if (item.deletedAt != null && item.checkedAt == null) {
        excluded.add(entry.key);
      }
    }
    return excluded;
  }

  /// Finds the ACTIVE (non-deleted) item in [householdId] whose normalized
  /// name equals [normalizedName], if any — regardless of checked state.
  ///
  /// Used to enforce B3 duplicate prevention on quick-add submit and
  /// suggestion tap (spec `docs/specs/ux-round-2.md` B3): soft-deleted
  /// items never count as a duplicate.
  Future<ShoppingItemWithCategory?> findActiveByNormalizedName(
    String householdId,
    String normalizedName,
  ) async {
    final rows = await _historyRows(householdId);
    for (final row in rows) {
      if (row.item.deletedAt == null &&
          normalizeShoppingItemName(row.item.name) == normalizedName) {
        return ShoppingItemWithCategory(item: row.item, category: row.category);
      }
    }
    return null;
  }

  /// Returns the most recent non-null category id ever used for
  /// [normalizedName] in [householdId]'s full history (including
  /// soft-deleted items), or `null` if no history row for it ever set one.
  ///
  /// Used by B3 duplicate prevention so a fresh insert from a plain-text
  /// submit (as opposed to a suggestion tap, which already carries its own
  /// category) inherits the right category. See `docs/specs/ux-round-2.md`
  /// B3.
  Future<String?> mostRecentCategoryIdForNormalizedName(
    String householdId,
    String normalizedName,
  ) async {
    final rows = await _historyRows(householdId);
    final matches =
        [
          for (final row in rows)
            if (normalizeShoppingItemName(row.item.name) == normalizedName) row,
        ]..sort(
          (a, b) => DateTime.parse(
            b.item.createdAt,
          ).compareTo(DateTime.parse(a.item.createdAt)),
        );
    for (final row in matches) {
      final categoryId = row.item.categoryId;
      if (categoryId != null) {
        return categoryId;
      }
    }
    return null;
  }

  /// Every item ever added to [householdId] (active or soft-deleted),
  /// joined with its resolved category — the shared raw fetch behind
  /// [suggestions], [findActiveByNormalizedName], and
  /// [mostRecentCategoryIdForNormalizedName].
  Future<List<_HistoryRow>> _historyRows(String householdId) async {
    final query = db.select(db.shoppingItems).join([
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.shoppingItems.categoryId),
      ),
    ])..where(db.shoppingItems.householdId.equals(householdId));

    final rows = await query.get();
    return [
      for (final row in rows)
        (
          item: row.readTable(db.shoppingItems),
          category: row.readTableOrNull(db.categories),
        ),
    ];
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
            syncDirty: syncDirtyOnWrite,
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
      syncDirty: true,
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
        syncDirty: syncDirtyOnWrite,
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
        syncDirty: syncDirtyOnWrite,
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
      ShoppingItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  /// Restores a previously soft-deleted item (spec
  /// `docs/specs/polish-round-1.md` C3): the UNDO action of the shopping
  /// delete snackbar. A plain `deleted_at` clear — soft delete never
  /// touched any other column, so there's nothing else to restore.
  Future<void> restoreItem(String id) async {
    await (db.update(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).write(
      ShoppingItemsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(_isoNow()),
        syncDirty: syncDirtyOnWrite,
      ),
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
          ShoppingItemsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            syncDirty: syncDirtyOnWrite,
          ),
        );
  }

  /// Unchecks every active, checked item in [householdId] — the "Put all
  /// back" bulk action (field feedback G1,
  /// `docs/feedback/2026-08-01-field-feedback.md`) for e.g. a failed
  /// checkout returning the whole cart to the main list in one action.
  /// Mirrors [setChecked]'s uncheck semantics (`checkedAt = null`, bumping
  /// `updatedAt`) for every matching row in a single UPDATE.
  Future<void> uncheckAll(String householdId) async {
    final now = _isoNow();
    await (db.update(db.shoppingItems)..where(
          (tbl) =>
              tbl.householdId.equals(householdId) &
              tbl.deletedAt.isNull() &
              tbl.checkedAt.isNotNull(),
        ))
        .write(
          ShoppingItemsCompanion(
            checkedAt: const Value(null),
            updatedAt: Value(now),
            syncDirty: syncDirtyOnWrite,
          ),
        );
  }

  /// Soft-deletes active, checked items in [householdId] whose `checked_at`
  /// is strictly older than [cutoffUtc].
  ///
  /// This is the 24h auto-clear called from `bootstrapProvider` (spec
  /// `docs/specs/ux-round-2.md` B4): the list self-cleans between shopping
  /// trips, restoring the original DESIGN.md §1 behavior. [cutoffUtc] is
  /// the caller's responsibility (typically the injected clock's `now()`
  /// minus 24 hours) so this stays testable with directly-manipulated
  /// `checked_at` timestamps.
  Future<void> clearCheckedOlderThan(
    String householdId, {
    required DateTime cutoffUtc,
  }) async {
    final rows =
        await (db.select(db.shoppingItems)..where(
              (tbl) =>
                  tbl.householdId.equals(householdId) &
                  tbl.deletedAt.isNull() &
                  tbl.checkedAt.isNotNull(),
            ))
            .get();

    final staleIds = [
      for (final row in rows)
        if (DateTime.parse(row.checkedAt!).isBefore(cutoffUtc)) row.id,
    ];
    if (staleIds.isEmpty) {
      return;
    }

    final now = _isoNow();
    await (db.update(
      db.shoppingItems,
    )..where((tbl) => tbl.id.isIn(staleIds))).write(
      ShoppingItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncDirty: syncDirtyOnWrite,
      ),
    );
  }

  String _isoNow() => nowUtc().toIso8601String();
}

String _defaultNewId() => const Uuid().v4();

DateTime _defaultNowUtc() => DateTime.now().toUtc();
