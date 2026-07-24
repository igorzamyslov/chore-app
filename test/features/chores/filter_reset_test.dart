import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Regression test for the "All …" filter entries doing nothing.
///
/// A [PopupMenuItem] without a value pops `null`, which [PopupMenuButton]
/// treats as "menu dismissed" and never forwards to `onSelected` — so the
/// reset entries must fire via `onTap`. Selecting a *specific* member or
/// category always worked; only resetting back to "all" was broken.
void main() {
  Future<void> tapMenuEntry(WidgetTester tester, String text) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String?>),
        matching: find.text(text),
      ),
    );
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'category filter: filtering hides other chores, and "All categories" '
    'resets the filter',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final categories = CategoryRepository(database);
      final catA = await categories.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'FilterCatA',
        icon: 'cleaning_services',
        color: 0xFF6D9F71,
      );
      final catB = await categories.createCategory(
        householdId,
        kind: CategoryKind.chore,
        name: 'FilterCatB',
        icon: 'yard',
        color: 0xFF8C7BC9,
      );
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
      );
      await service.createChore(
        householdId: householdId,
        title: 'Chore Alpha',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
        categoryId: catA.id,
      );
      await service.createChore(
        householdId: householdId,
        title: 'Chore Beta',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
        categoryId: catB.id,
      );
      await tester.pumpAndSettle();

      expect(find.text('Chore Alpha'), findsOneWidget);
      expect(find.text('Chore Beta'), findsOneWidget);

      // Filter to category A — B disappears.
      await tester.tap(find.byIcon(Icons.label_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'FilterCatA');
      expect(find.text('Chore Alpha'), findsOneWidget);
      expect(find.text('Chore Beta'), findsNothing);

      // Reset via "All categories" — both come back. (The regression: this
      // used to be a silent no-op.)
      await tester.tap(find.byIcon(Icons.label_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'All categories');
      expect(find.text('Chore Alpha'), findsOneWidget);
      expect(find.text('Chore Beta'), findsOneWidget);
    },
  );

  testChoreApp(
    'member filter: "All members" resets the filter',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(DateTime(2026, 7, 24, 9)),
      );
      // Unassigned chore: filtering by the bootstrap member hides it.
      await service.createChore(
        householdId: householdId,
        title: 'Unassigned chore',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      expect(find.text('Unassigned chore'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'Me');
      expect(find.text('Unassigned chore'), findsNothing);

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tapMenuEntry(tester, 'All members');
      expect(find.text('Unassigned chore'), findsOneWidget);
    },
  );
}
