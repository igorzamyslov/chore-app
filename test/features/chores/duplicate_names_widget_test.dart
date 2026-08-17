import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget-level verification suite for `docs/next-session-plan.md` #4:
/// duplicate chore names are allowed by design (user decision 2026-07-24,
/// no prohibition/warning) -- two identically-titled chores must render as
/// two independent tiles, and every action (complete/skip/pause/delete,
/// plus member/category filters) must target the right row by id, never by
/// title.
///
/// See `test/application/duplicate_names_test.dart` for the service-level
/// half of this matrix (reopen, editing a title).
class _Seed {
  const _Seed({
    required this.me,
    required this.anna,
    required this.bedroom,
    required this.balcony,
    required this.choreBedroom,
    required this.choreBalcony,
  });

  final Member me;
  final Member anna;
  final Category bedroom;
  final Category balcony;
  final Chore choreBedroom;
  final Chore choreBalcony;
}

/// Seeds two chores both titled 'Water plants', both due [today], each with
/// a distinct category and (fixed) assignee -- the "bedroom vs balcony"
/// scenario from the plan's example.
Future<_Seed> _seedDuplicateChores(
  AppDatabase database,
  String householdId,
  PlainDate today,
) async {
  final me = await (database.select(
    database.members,
  )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  final households = HouseholdRepository(database);
  final anna = await households.addMember(
    householdId,
    name: 'Anna',
    color: 0xFF8C7BC9,
  );
  final categories = CategoryRepository(database);
  final bedroom = await categories.createCategory(
    householdId,
    kind: CategoryKind.chore,
    name: 'Bedroom',
    icon: 'bed',
    color: 0xFF6D9F71,
  );
  final balcony = await categories.createCategory(
    householdId,
    kind: CategoryKind.chore,
    name: 'Balcony',
    icon: 'yard',
    color: 0xFFD98E73,
  );
  final service = ChoreService(
    database: database,
    chores: ChoreRepository(database),
    clock: Clock.fixed(DateTime(today.year, today.month, today.day, 9)),
  );
  final choreBedroom = await service.createChore(
    householdId: householdId,
    title: 'Water plants',
    startDate: today,
    assignmentMode: AssignmentMode.fixed,
    assigneeMemberIds: [me.id],
    categoryId: bedroom.id,
  );
  final choreBalcony = await service.createChore(
    householdId: householdId,
    title: 'Water plants',
    startDate: today,
    assignmentMode: AssignmentMode.fixed,
    assigneeMemberIds: [anna.id],
    categoryId: balcony.id,
  );
  return _Seed(
    me: me,
    anna: anna,
    bedroom: bedroom,
    balcony: balcony,
    choreBedroom: choreBedroom,
    choreBalcony: choreBalcony,
  );
}

void main() {
  // 2026-07-22 is a Wednesday.
  final today = DateTime(2026, 7, 22, 9);
  final todayPlain = PlainDate(2026, 7, 22);

  testChoreApp(
    'two chores with the same title render as two independent tiles under '
    'the same section',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final seed = await _seedDuplicateChores(
        database,
        householdId,
        todayPlain,
      );
      await tester.pumpAndSettle();

      expect(find.text('Water plants'), findsNWidgets(2));
      // Section headers render uppercase (theme-v2.md §2/§4.1 item 2).
      expect(find.text('TODAY'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.complete',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'completing one same-named chore closes only that occurrence; the '
    'sibling stays pending, and Done-today shows exactly one entry with '
    'the right closer',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final seed = await _seedDuplicateChores(
        database,
        householdId,
        todayPlain,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.complete',
        ),
      );
      await tester.pumpAndSettle();

      // Only the bedroom occurrence closed: exactly one tile left pending.
      expect(find.text('Water plants'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('chores.done.header'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      // Now both the still-pending sibling's tile AND the single Done row
      // show the shared title -- exactly two matches, correctly split
      // between the two sections.
      expect(find.text('Water plants'), findsNWidgets(2));
      expect(find.text('by Me'), findsOneWidget);

      final closedBedroom = await repo.latestClosedOccurrence(
        seed.choreBedroom.id,
      );
      expect(closedBedroom!.completedBy, seed.me.id);
      expect(await repo.pendingOccurrenceOf(seed.choreBalcony.id), isNotNull);
      expect(await repo.latestClosedOccurrence(seed.choreBalcony.id), isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    "skip via one same-named chore's menu skips only that chore; the "
    'sibling stays pending and unaffected',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final seed = await _seedDuplicateChores(
        database,
        householdId,
        todayPlain,
      );
      await tester.pumpAndSettle();

      final balconyPendingBefore = await repo.pendingOccurrenceOf(
        seed.choreBalcony.id,
      );

      await tester.tap(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.menu',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.skip'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.complete',
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsOneWidget,
      );
      expect(find.text('Done today (1)'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();
      // Scoped to the Done section, not a bare text lookup: skipping a
      // one-off chore with no next occurrence also pops an undo snackbar
      // reading the same bare "Skipped" (see chores_list_screen.dart's
      // _showCloseSnackbar), which is still on screen at this point and
      // would otherwise double-match.
      expect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text('Skipped'),
        ),
        findsOneWidget,
      );

      final closedBedroom = await repo.latestClosedOccurrence(
        seed.choreBedroom.id,
      );
      expect(closedBedroom!.status, OccurrenceStatus.skipped);
      final stillPendingBalcony = await repo.pendingOccurrenceOf(
        seed.choreBalcony.id,
      );
      expect(stillPendingBalcony!.id, balconyPendingBefore!.id);
      expect(stillPendingBalcony.status, OccurrenceStatus.pending);

      handle.dispose();
    },
  );

  testChoreApp(
    "pause via one same-named chore's menu pauses only that chore; Paused "
    'shows exactly it while the sibling stays pending',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final seed = await _seedDuplicateChores(
        database,
        householdId,
        todayPlain,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.menu',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.pause'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.complete',
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chores.paused.header'),
        findsOneWidget,
      );
      expect(find.text('Paused (1)'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.paused.header'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier(
          'chores.paused.${seed.choreBedroom.id}.resume',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'chores.paused.${seed.choreBalcony.id}.resume',
        ),
        findsNothing,
      );

      final detailsBedroom = await repo.getChore(seed.choreBedroom.id);
      expect(detailsBedroom!.chore.pausedAt, isNotNull);
      final detailsBalcony = await repo.getChore(seed.choreBalcony.id);
      expect(detailsBalcony!.chore.pausedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    "delete (after confirm) via one same-named chore's menu deletes only "
    'that chore; the sibling stays pending and untouched',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final seed = await _seedDuplicateChores(
        database,
        householdId,
        todayPlain,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.menu',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.delete.confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Water plants'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsOneWidget,
      );

      final detailsBedroom = await repo.getChore(seed.choreBedroom.id);
      expect(detailsBedroom!.chore.deletedAt, isNotNull);
      expect(await repo.pendingOccurrenceOf(seed.choreBedroom.id), isNull);

      final detailsBalcony = await repo.getChore(seed.choreBalcony.id);
      expect(detailsBalcony!.chore.deletedAt, isNull);
      expect(await repo.pendingOccurrenceOf(seed.choreBalcony.id), isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'member and category filters affect two same-named chores '
    'independently',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final seed = await _seedDuplicateChores(
        database,
        householdId,
        todayPlain,
      );
      await tester.pumpAndSettle();

      expect(find.text('Water plants'), findsNWidgets(2));

      // Category filter: 'Bedroom' keeps only the bedroom chore, even
      // though both chores share a title.
      await tester.tap(find.bySemanticsIdentifier('chores.filter.category'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.filter.category.${seed.bedroom.id}'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Water plants'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.complete',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsNothing,
      );

      // Reset.
      await tester.tap(find.bySemanticsIdentifier('chores.filter.category'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.filter.category.all'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Water plants'), findsNWidgets(2));

      // Member filter: 'Anna' keeps only the balcony chore.
      await tester.tap(find.bySemanticsIdentifier('chores.filter.member'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.filter.member.${seed.anna.id}'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Water plants'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBalcony.id}.complete',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'chores.occurrence.${seed.choreBedroom.id}.complete',
        ),
        findsNothing,
      );

      // Reset.
      await tester.tap(find.bySemanticsIdentifier('chores.filter.member'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.filter.member.all'));
      await tester.pumpAndSettle();
      expect(find.text('Water plants'), findsNWidgets(2));

      handle.dispose();
    },
  );
}
