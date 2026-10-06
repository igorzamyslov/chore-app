import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'delete: cancel keeps it, confirm detaches referencing chores (they '
    'show as uncategorized)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = categories.firstWhere((c) => c.name == 'Cleaning');

      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await choreService.createChore(
        householdId: householdId,
        title: 'Vacuum',
        startDate: PlainDate.fromDateTime(today),
        assignmentMode: AssignmentMode.anyone,
        categoryId: cleaning.id,
      );

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.text('Vacuum'), findsOneWidget);
      expect(find.text('Cleaning'), findsOneWidget);

      await openManageCategories(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();

      // Cancel: the category (and its sheet) is untouched.
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.cancel'),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();
      expect(find.text('Cleaning'), findsOneWidget);

      // Confirm: soft-deletes and detaches.
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.confirm'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsNothing,
      );
      expect(find.text('Cleaning'), findsNothing);

      final choreRow = await (database.select(
        database.chores,
      )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
      expect(choreRow.categoryId, isNull);

      // The manage-categories screen is a pushed route, covering the
      // bottom tab bar; back out of it before switching tabs again.
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.text('Vacuum'), findsOneWidget);
      expect(find.text('Cleaning'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'delete: body names the exact count and reads differently at zero',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final choreCategories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = choreCategories.firstWhere((c) => c.name == 'Cleaning');

      Future<void> openDeleteDialog(String categoryId) async {
        await tester.tap(
          find.bySemanticsIdentifier('settings.categories.$categoryId'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier('settings.categories.delete'),
        );
        await tester.pumpAndSettle();
      }

      Future<void> cancelAndCloseSheet() async {
        await tester.tap(
          find.bySemanticsIdentifier('settings.categories.delete.cancel'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier('settings.categories.save'),
        );
        await tester.pumpAndSettle();
      }

      // Zero case: nothing references 'Cleaning' yet. It must read as its
      // own sentence, not as a "0 chores" plural.
      await openManageCategories(tester);
      await openDeleteDialog(cleaning.id);
      expect(
        find.text("This deletes 'Cleaning'. No chores use it right now."),
        findsOneWidget,
      );
      await cancelAndCloseSheet();

      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      Future<void> addChore(String title) => choreService.createChore(
        householdId: householdId,
        title: title,
        startDate: PlainDate.fromDateTime(today),
        assignmentMode: AssignmentMode.anyone,
        categoryId: cleaning.id,
      );

      // Exactly one reference: the ICU `one` branch.
      await addChore('Vacuum');
      await openDeleteDialog(cleaning.id);
      expect(
        find.text(
          "This deletes 'Cleaning'. 1 chore uses it.",
        ),
        findsOneWidget,
      );
      await cancelAndCloseSheet();

      // Three references: the ICU `other` branch, and the exact number —
      // this is the assertion that would catch an off-by-one or a count
      // that silently collapsed to 0.
      await addChore('Mop');
      await addChore('Dust');
      await openDeleteDialog(cleaning.id);
      expect(
        find.text(
          "This deletes 'Cleaning'. 3 chores use it.",
        ),
        findsOneWidget,
      );
      await cancelAndCloseSheet();

      // A shopping-kind category is worded with items, not chores, and
      // counts the shopping-items table rather than the chores table —
      // the three chores above must not leak into its number.
      final shoppingCategories = await activeCategories(
        database,
        householdId,
        CategoryKind.shopping,
      );
      final dairy = shoppingCategories.firstWhere((c) => c.name == 'Dairy');
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.kind.shopping'),
      );
      await tester.pumpAndSettle();
      await openDeleteDialog(dairy.id);
      expect(
        find.text("This deletes 'Dairy'. No shopping items use it right now."),
        findsOneWidget,
      );
      await cancelAndCloseSheet();

      final shoppingRepo = ShoppingRepository(database);
      await shoppingRepo.addItem(
        householdId,
        name: 'Milk',
        categoryId: dairy.id,
      );
      await shoppingRepo.addItem(
        householdId,
        name: 'Butter',
        categoryId: dairy.id,
      );
      await openDeleteDialog(dairy.id);
      expect(
        find.text(
          "This deletes 'Dairy'. 2 shopping items use it.",
        ),
        findsOneWidget,
      );
      await cancelAndCloseSheet();

      handle.dispose();
    },
  );

  // Persona review 2026-10-06 C10 (Maria P3-M): "I want to merge Kitchen
  // into Cleaning. I'd have to re-tag every chore by hand."
  testChoreApp(
    'category rows say how many chores use them',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = categories.firstWhere((c) => c.name == 'Cleaning');
      final other = categories.firstWhere((c) => c.id != cleaning.id);
      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      for (final title in ['Vacuum', 'Mop']) {
        await choreService.createChore(
          householdId: householdId,
          title: title,
          startDate: PlainDate.fromDateTime(today),
          assignmentMode: AssignmentMode.anyone,
          categoryId: cleaning.id,
        );
      }

      await openManageCategories(tester);

      String usageOf(String categoryId) => tester
          .widget<Text>(
            find.descendant(
              of: find.bySemanticsIdentifier(
                'settings.categories.$categoryId.usage',
              ),
              matching: find.byType(Text),
            ),
          )
          .data!;
      expect(usageOf(cleaning.id), 'Used by 2 chores');
      expect(usageOf(other.id), 'Not used yet');

      handle.dispose();
    },
  );

  testChoreApp(
    'delete with "Move them to" another category moves its chores there',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = categories.firstWhere((c) => c.name == 'Cleaning');
      final target = categories.firstWhere((c) => c.id != cleaning.id);
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Vacuum',
            startDate: PlainDate.fromDateTime(today),
            assignmentMode: AssignmentMode.anyone,
            categoryId: cleaning.id,
          );

      await openManageCategories(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete'),
      );
      await tester.pumpAndSettle();

      // Defaults to Uncategorized; pick the other category instead.
      expect(find.text('Move them to'), findsOneWidget);
      expect(find.text('Uncategorized'), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.moveTo'),
      );
      await tester.pumpAndSettle();
      // The dropdown's own menu shows its items once more on top of the
      // field; tap the menu's copy.
      await tester.tap(
        find
            .bySemanticsIdentifier(
              'settings.categories.delete.moveTo.${target.id}',
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.delete.confirm'),
      );
      await tester.pumpAndSettle();

      final choreRow = await (database.select(
        database.chores,
      )..where((tbl) => tbl.id.equals(chore.id))).getSingle();
      expect(choreRow.categoryId, target.id);
      final deleted = await (database.select(
        database.categories,
      )..where((tbl) => tbl.id.equals(cleaning.id))).getSingle();
      expect(deleted.deletedAt, isNotNull);

      handle.dispose();
    },
  );
}
