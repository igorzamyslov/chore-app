import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/ui_state_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

/// Chores-filter restore (spec `docs/specs/last-tab-restore.md` §5): the
/// Chores list reopens with the member/category filters the user left, drops
/// stale ids to "All", and records every change.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  /// Seeds a category "CatA"/"CatB" pair and three chores:
  /// "Mine A" (cat A, assigned to Me), "Mine B" (cat B, assigned to Me),
  /// "Free A" (cat A, unassigned). Returns (memberId, catAId).
  Future<({String memberId, String catAId})> seedChores(
    AppDatabase database,
  ) async {
    final householdId = await currentHouseholdId(database);
    final member = await database.select(database.members).getSingle();
    final categories = CategoryRepository(database);
    final catA = await categories.createCategory(
      householdId,
      kind: CategoryKind.chore,
      name: 'CatA',
      icon: 'cleaning_services',
      color: 0xFF6D9F71,
    );
    final catB = await categories.createCategory(
      householdId,
      kind: CategoryKind.chore,
      name: 'CatB',
      icon: 'yard',
      color: 0xFF8C7BC9,
    );
    final service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    Future<void> create(
      String title,
      String categoryId, {
      required bool mine,
    }) async {
      await service.createChore(
        householdId: householdId,
        title: title,
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: mine ? AssignmentMode.fixed : AssignmentMode.anyone,
        categoryId: categoryId,
        assigneeMemberIds: mine ? [member.id] : const [],
      );
    }

    await create('Mine A', catA.id, mine: true);
    await create('Mine B', catB.id, mine: true);
    await create('Free A', catA.id, mine: false);
    return (memberId: member.id, catAId: catA.id);
  }

  Future<void> seedFilters(
    AppDatabase database, {
    String? memberId,
    String? categoryId,
  }) async {
    await database
        .into(database.uiState)
        .insert(
          UiStateCompanion.insert(
            id: 'device',
            choresMemberFilter: Value(memberId),
            choresCategoryFilter: Value(categoryId),
          ),
        );
  }

  Future<UiStateRow?> storedRow(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    // Boxed in a list: `runAsync` returns `T?`, indistinguishable from a
    // stored `null` otherwise.
    final boxed = await tester.runAsync(
      () async => [await UiStateRepository(database).readUiState()],
    );
    return boxed!.single;
  }

  testChoreApp(
    'a stored member + category filter opens filtered on the first frame',
    today: today,
    seed: (database) async {
      final ids = await seedChores(database);
      await seedFilters(
        database,
        memberId: ids.memberId,
        categoryId: ids.catAId,
      );
    },
    (tester, database) async {
      expect(find.text('Mine A'), findsOneWidget);
      expect(find.text('Mine B'), findsNothing);
      // E1: an unassigned chore in the category passes the member filter.
      expect(find.text('Free A'), findsOneWidget);
    },
  );

  testChoreApp(
    'stale stored ids open unfiltered and are not written back',
    today: today,
    seed: (database) async {
      await seedChores(database);
      await seedFilters(
        database,
        memberId: 'gone-member',
        categoryId: 'gone-category',
      );
    },
    (tester, database) async {
      expect(find.text('Mine A'), findsOneWidget);
      expect(find.text('Mine B'), findsOneWidget);
      expect(find.text('Free A'), findsOneWidget);

      final row = await storedRow(tester, database);
      expect(row?.choresMemberFilter, 'gone-member');
      expect(row?.choresCategoryFilter, 'gone-category');
    },
  );

  testChoreApp(
    'picking a filter persists it, and All members stores the sentinel',
    today: today,
    seed: (database) async {
      await seedChores(database);
    },
    (tester, database) async {
      final member = await database.select(database.members).getSingle();

      // Category B: only "Mine B" remains.
      await tester.tap(find.byIcon(Icons.label_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('CatB'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mine B'), findsOneWidget);
      expect(find.text('Mine A'), findsNothing);

      var row = await storedRow(tester, database);
      expect(row?.choresCategoryFilter, isNotNull);
      expect(row?.choresMemberFilter, isNull);

      // Plus the member filter: nothing matches both -> filtered-empty.
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('Me'),
        ),
      );
      await tester.pumpAndSettle();

      row = await storedRow(tester, database);
      expect(row?.choresMemberFilter, member.id);
      expect(row?.choresCategoryFilter, isNotNull);

      // "All categories" -> category null, member kept.
      await tester.tap(find.byIcon(Icons.label_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('All categories'),
        ),
      );
      await tester.pumpAndSettle();
      row = await storedRow(tester, database);
      expect(row?.choresMemberFilter, member.id);
      expect(row?.choresCategoryFilter, isNull);

      // "All members" -> explicit sentinel for the member, category null.
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('All members'),
        ),
      );
      await tester.pumpAndSettle();
      row = await storedRow(tester, database);
      expect(row?.choresMemberFilter, UiStateRepository.allMembersFilter);
      expect(row?.choresCategoryFilter, isNull);
    },
  );

  testChoreApp(
    'a stored explicit "All members" opens unfiltered',
    today: today,
    seed: (database) async {
      await seedChores(database);
      await seedFilters(
        database,
        memberId: UiStateRepository.allMembersFilter,
      );
    },
    (tester, database) async {
      expect(find.text('Mine A'), findsOneWidget);
      expect(find.text('Mine B'), findsOneWidget);
      expect(find.text('Free A'), findsOneWidget);
    },
  );

  testChoreApp(
    'Show everything on the filtered-empty state stores an explicit All',
    today: today,
    seed: (database) async {
      final ids = await seedChores(database);
      // A filter combination nothing matches: member Me plus a real
      // category with no chores.
      final householdId = await currentHouseholdId(database);
      final empty = await CategoryRepository(database).createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'CatEmpty',
        icon: 'yard',
        color: 0xFF8C7BC9,
      );
      await seedFilters(
        database,
        memberId: ids.memberId,
        categoryId: empty.id,
      );
    },
    (tester, database) async {
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsIdentifier('chores.empty.filtered'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.filter.clear'));
      await tester.pumpAndSettle();

      expect(find.text('Mine A'), findsOneWidget);
      expect(find.text('Free A'), findsOneWidget);
      final row = await storedRow(tester, database);
      expect(row?.choresMemberFilter, UiStateRepository.allMembersFilter);
      expect(row?.choresCategoryFilter, isNull);

      handle.dispose();
    },
  );
}
