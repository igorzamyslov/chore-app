/// Audits the shared "mark dirty" mechanism (spec
/// `docs/specs/sync-backend.md` §8.1, `lib/data/db/sync_dirty.dart`):
/// EVERY repository write to a synced table
/// (households/members/categories/chores/chore_assignees/
/// chore_occurrences/shopping_items) must set `syncDirty: true`, including
/// cross-table side effects (e.g. `CategoryRepository.softDeleteCategory`
/// clearing `categoryId` on chores/shopping items) and the one
/// service-level direct-write bypass (`ChoreService.reopenOccurrence`).
///
/// Every test that checks an UPDATE site first clears `syncDirty` back to
/// `false` via a raw write (never through the repository under test) so the
/// assertion actually proves the method under test is what set it, rather
/// than riding on a flag that was already true from an earlier insert.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

Future<void> _clearMemberDirty(AppDatabase db, String id) =>
    (db.update(db.members)..where((tbl) => tbl.id.equals(id))).write(
      const MembersCompanion(syncDirty: Value(false)),
    );

Future<void> _clearCategoryDirty(AppDatabase db, String id) =>
    (db.update(db.categories)..where((tbl) => tbl.id.equals(id))).write(
      const CategoriesCompanion(syncDirty: Value(false)),
    );

Future<void> _clearChoreDirty(AppDatabase db, String id) =>
    (db.update(db.chores)..where((tbl) => tbl.id.equals(id))).write(
      const ChoresCompanion(syncDirty: Value(false)),
    );

Future<void> _clearChoreAssigneesDirty(AppDatabase db, String choreId) =>
    (db.update(db.choreAssignees)..where((tbl) => tbl.choreId.equals(choreId)))
        .write(const ChoreAssigneesCompanion(syncDirty: Value(false)));

Future<void> _clearOccurrenceDirty(AppDatabase db, String id) =>
    (db.update(db.choreOccurrences)..where((tbl) => tbl.id.equals(id))).write(
      const ChoreOccurrencesCompanion(syncDirty: Value(false)),
    );

Future<void> _clearShoppingItemDirty(AppDatabase db, String id) =>
    (db.update(db.shoppingItems)..where((tbl) => tbl.id.equals(id))).write(
      const ShoppingItemsCompanion(syncDirty: Value(false)),
    );

Future<bool> _householdDirty(AppDatabase db, String id) async =>
    (await (db.select(
      db.households,
    )..where((tbl) => tbl.id.equals(id))).getSingle()).syncDirty;

Future<bool> _memberDirty(AppDatabase db, String id) async => (await (db.select(
  db.members,
)..where((tbl) => tbl.id.equals(id))).getSingle()).syncDirty;

Future<bool> _categoryDirty(AppDatabase db, String id) async =>
    (await (db.select(
      db.categories,
    )..where((tbl) => tbl.id.equals(id))).getSingle()).syncDirty;

Future<bool> _choreDirty(AppDatabase db, String id) async => (await (db.select(
  db.chores,
)..where((tbl) => tbl.id.equals(id))).getSingle()).syncDirty;

Future<List<bool>> _choreAssigneesDirty(AppDatabase db, String choreId) async {
  final rows = await (db.select(
    db.choreAssignees,
  )..where((tbl) => tbl.choreId.equals(choreId))).get();
  return [for (final row in rows) row.syncDirty];
}

Future<bool> _occurrenceDirty(AppDatabase db, String id) async =>
    (await (db.select(
      db.choreOccurrences,
    )..where((tbl) => tbl.id.equals(id))).getSingle()).syncDirty;

Future<bool> _shoppingItemDirty(AppDatabase db, String id) async =>
    (await (db.select(
      db.shoppingItems,
    )..where((tbl) => tbl.id.equals(id))).getSingle()).syncDirty;

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('HouseholdRepository', () {
    test('ensureLocalHousehold marks the household and its bootstrap '
        'member dirty', () async {
      final repo = HouseholdRepository(db, newId: _IdGen().call);
      final household = await repo.ensureLocalHousehold();

      expect(household.syncDirty, isTrue);
      expect(await _householdDirty(db, household.id), isTrue);
      final member = await db.select(db.members).getSingle();
      expect(member.syncDirty, isTrue);
    });

    test('addMember marks the new member dirty', () async {
      final repo = HouseholdRepository(db, newId: _IdGen().call);
      final household = await repo.ensureLocalHousehold();

      final member = await repo.addMember(
        household.id,
        name: 'Jo',
        color: 0xFF123456,
      );

      expect(member.syncDirty, isTrue);
      expect(await _memberDirty(db, member.id), isTrue);
    });

    test('setMemberRole marks the member dirty', () async {
      final repo = HouseholdRepository(db, newId: _IdGen().call);
      final household = await repo.ensureLocalHousehold();
      final member = await repo.addMember(
        household.id,
        name: 'Jo',
        color: 0xFF123456,
      );
      await _clearMemberDirty(db, member.id);
      expect(await _memberDirty(db, member.id), isFalse);

      await repo.setMemberRole(member.id, MemberRole.admin);

      expect(await _memberDirty(db, member.id), isTrue);
    });

    test('renameMember marks the member dirty', () async {
      final repo = HouseholdRepository(db, newId: _IdGen().call);
      final household = await repo.ensureLocalHousehold();
      final member = await repo.addMember(
        household.id,
        name: 'Jo',
        color: 0xFF123456,
      );
      await _clearMemberDirty(db, member.id);

      await repo.renameMember(member.id, 'Joanna');

      expect(await _memberDirty(db, member.id), isTrue);
    });

    test('recolorMember marks the member dirty', () async {
      final repo = HouseholdRepository(db, newId: _IdGen().call);
      final household = await repo.ensureLocalHousehold();
      final member = await repo.addMember(
        household.id,
        name: 'Jo',
        color: 0xFF123456,
      );
      await _clearMemberDirty(db, member.id);

      await repo.recolorMember(member.id, 0xFF654321);

      expect(await _memberDirty(db, member.id), isTrue);
    });
  });

  group('CategoryRepository', () {
    late HouseholdRepository households;
    late CategoryRepository repo;
    late String householdId;

    setUp(() async {
      households = HouseholdRepository(db, newId: _IdGen().call);
      repo = CategoryRepository(db, newId: _IdGen().call);
      householdId = (await households.ensureLocalHousehold()).id;
    });

    test('seedDefaults marks every seeded category dirty', () async {
      await repo.seedDefaults(householdId);

      final rows = await db.select(db.categories).get();
      expect(rows, isNotEmpty);
      expect(rows.every((row) => row.syncDirty), isTrue);
    });

    test('createCategory marks the new category dirty', () async {
      final category = await repo.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'Cleaning',
        icon: 'cleaning_services',
        color: 0xFF123456,
      );

      expect(category.syncDirty, isTrue);
      expect(await _categoryDirty(db, category.id), isTrue);
    });

    test('updateCategory marks the category dirty', () async {
      final category = await repo.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'Cleaning',
        icon: 'cleaning_services',
        color: 0xFF123456,
      );
      await _clearCategoryDirty(db, category.id);

      await repo.updateCategory(category.id, name: 'Deep cleaning');

      expect(await _categoryDirty(db, category.id), isTrue);
    });

    test('reorderCategories marks every reordered category dirty', () async {
      final a = await repo.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'A',
        icon: 'a',
        color: 1,
      );
      final b = await repo.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'B',
        icon: 'b',
        color: 2,
      );
      await _clearCategoryDirty(db, a.id);
      await _clearCategoryDirty(db, b.id);

      await repo.reorderCategories(householdId, CategoryKind.chore, [
        b.id,
        a.id,
      ]);

      expect(await _categoryDirty(db, a.id), isTrue);
      expect(await _categoryDirty(db, b.id), isTrue);
    });

    test(
      'softDeleteCategory marks the category AND every chore/shopping '
      'item that referenced it dirty',
      () async {
        final category = await repo.createCategory(
          householdId,
          kind: CategoryKind.chore,
          name: 'Cleaning',
          icon: 'cleaning_services',
          color: 0xFF123456,
        );
        final chores = ChoreRepository(db, newId: _IdGen().call);
        final chore = await chores.createChore(
          householdId: householdId,
          title: 'Dishes',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          categoryId: category.id,
        );
        final shopping = ShoppingRepository(db, newId: _IdGen().call);
        final item = await shopping.addItem(
          householdId,
          name: 'Milk',
          categoryId: category.id,
        );
        await _clearCategoryDirty(db, category.id);
        await _clearChoreDirty(db, chore.id);
        await _clearShoppingItemDirty(db, item.id);

        await repo.softDeleteCategory(category.id);

        expect(await _categoryDirty(db, category.id), isTrue);
        expect(await _choreDirty(db, chore.id), isTrue);
        expect(await _shoppingItemDirty(db, item.id), isTrue);
      },
    );
  });

  group('ChoreRepository', () {
    late HouseholdRepository households;
    late ChoreRepository repo;
    late String householdId;
    late String memberId;

    setUp(() async {
      households = HouseholdRepository(db, newId: _IdGen().call);
      repo = ChoreRepository(db, newId: _IdGen().call);
      householdId = (await households.ensureLocalHousehold()).id;
      memberId = (await households.addMember(
        householdId,
        name: 'Jo',
        color: 1,
      )).id;
    });

    test('createChore marks the chore and its assignees dirty', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [memberId],
      );

      expect(chore.syncDirty, isTrue);
      expect(await _choreDirty(db, chore.id), isTrue);
      expect(await _choreAssigneesDirty(db, chore.id), everyElement(isTrue));
    });

    test('updateChore marks the chore dirty (and reassigned assignees, '
        'when replaced)', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [memberId],
      );
      await _clearChoreDirty(db, chore.id);
      await _clearChoreAssigneesDirty(db, chore.id);

      await repo.updateChore(chore.id, title: 'Dishes (evening)');

      expect(await _choreDirty(db, chore.id), isTrue);
    });

    test('softDeleteChore marks the chore dirty', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      await _clearChoreDirty(db, chore.id);

      await repo.softDeleteChore(chore.id);

      expect(await _choreDirty(db, chore.id), isTrue);
    });

    test('setPaused marks the chore dirty', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      await _clearChoreDirty(db, chore.id);

      await repo.setPaused(chore.id, paused: true);

      expect(await _choreDirty(db, chore.id), isTrue);
    });

    test('insertOccurrence marks the new occurrence dirty', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );

      final occurrence = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 8),
      );

      expect(occurrence.syncDirty, isTrue);
      expect(await _occurrenceDirty(db, occurrence.id), isTrue);
    });

    test('closeOccurrence marks the occurrence dirty', () async {
      final chore = await repo.createChore(
        householdId: householdId,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final occurrence = await repo.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 1),
      );
      await _clearOccurrenceDirty(db, occurrence.id);

      await repo.closeOccurrence(
        occurrence.id,
        status: OccurrenceStatus.done,
        closedOn: PlainDate(2026, 1, 1),
        completedBy: memberId,
      );

      expect(await _occurrenceDirty(db, occurrence.id), isTrue);
    });
  });

  group('ShoppingRepository', () {
    late String householdId;
    late ShoppingRepository repo;

    setUp(() async {
      final households = HouseholdRepository(db, newId: _IdGen().call);
      repo = ShoppingRepository(db, newId: _IdGen().call);
      householdId = (await households.ensureLocalHousehold()).id;
    });

    test('addItem marks the new item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');

      expect(item.syncDirty, isTrue);
      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('updateItem marks the item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await _clearShoppingItemDirty(db, item.id);

      await repo.updateItem(item.id, name: 'Oat milk');

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('setChecked marks the item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await _clearShoppingItemDirty(db, item.id);

      await repo.setChecked(item.id, checked: true);

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('deleteItem marks the item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await _clearShoppingItemDirty(db, item.id);

      await repo.deleteItem(item.id);

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('restoreItem marks the item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.deleteItem(item.id);
      await _clearShoppingItemDirty(db, item.id);

      await repo.restoreItem(item.id);

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('clearChecked marks every cleared item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(item.id, checked: true);
      await _clearShoppingItemDirty(db, item.id);

      await repo.clearChecked(householdId);

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('uncheckAll marks every unchecked item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(item.id, checked: true);
      await _clearShoppingItemDirty(db, item.id);

      await repo.uncheckAll(householdId);

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });

    test('clearCheckedOlderThan marks every auto-cleared item dirty', () async {
      final item = await repo.addItem(householdId, name: 'Milk');
      await repo.setChecked(item.id, checked: true);
      await _clearShoppingItemDirty(db, item.id);

      await repo.clearCheckedOlderThan(
        householdId,
        cutoffUtc: DateTime.utc(2027),
      );

      expect(await _shoppingItemDirty(db, item.id), isTrue);
    });
  });

  group('ChoreService', () {
    late String householdId;
    late String memberId;
    late ChoreRepository chores;
    late ChoreService service;

    setUp(() async {
      final households = HouseholdRepository(db, newId: _IdGen().call);
      chores = ChoreRepository(db, newId: _IdGen().call);
      householdId = (await households.ensureLocalHousehold()).id;
      memberId = (await db.select(db.members).getSingle()).id;
      service = ChoreService(
        database: db,
        chores: chores,
        clock: Clock.fixed(DateTime.utc(2026, 1, 8)),
      );
    });

    test(
      'completeOccurrence marks the closed occurrence AND its freshly '
      'inserted successor dirty (spec §8.1 widget-test-proof)',
      () async {
        final chore = await service.createChore(
          householdId: householdId,
          title: 'Weekly bins',
          startDate: PlainDate(2026, 1, 8),
          assignmentMode: AssignmentMode.anyone,
          recurrence: Recurrence.everyNDays(7),
        );
        final pending = (await chores.pendingOccurrenceOf(chore.id))!;
        await _clearOccurrenceDirty(db, pending.id);
        expect(await _occurrenceDirty(db, pending.id), isFalse);

        await service.completeOccurrence(pending.id, completedBy: memberId);

        // The just-closed occurrence became dirty...
        expect(await _occurrenceDirty(db, pending.id), isTrue);
        // ...and so did its freshly-inserted successor.
        final successor = (await chores.pendingOccurrenceOf(chore.id))!;
        expect(successor.id, isNot(pending.id));
        expect(await _occurrenceDirty(db, successor.id), isTrue);
      },
    );

    test('reopenOccurrence (a direct database write bypassing '
        'ChoreRepository) marks the occurrence dirty', () async {
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off',
        startDate: PlainDate(2026, 1, 8),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = (await chores.pendingOccurrenceOf(chore.id))!;
      await service.completeOccurrence(pending.id, completedBy: memberId);
      await _clearOccurrenceDirty(db, pending.id);
      expect(await _occurrenceDirty(db, pending.id), isFalse);

      await service.reopenOccurrence(pending.id);

      expect(await _occurrenceDirty(db, pending.id), isTrue);
    });
  });
}
