import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// Widget coverage for the quick-add field's type-ahead suggestions (see
/// `docs/specs/ux-round-2.md` B2). Duplicate-prevention on submit/tap (B3)
/// has its own suite in `duplicate_prevention_test.dart`.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder quickAddInput() => find.descendant(
    of: find.bySemanticsIdentifier('shopping.add.input'),
    matching: find.byType(TextField),
  );

  testChoreApp(
    'suggestions: typing >=1 char shows ranked matches (frequency beats '
    'recency) with name + most recent category; clearing the field hides '
    'them',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final dairy = await CategoryRepository(database).createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Dairy',
        icon: 'egg',
        color: 0xFF8C7BC9,
      );

      var clockTime = DateTime.utc(2026, 7);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'seed-${nextId++}',
        nowUtc: () => clockTime,
      );

      // "milk" was added twice (frequency 2, with "Dairy" set on the older
      // row) — it must outrank "Mint", added once but more recently.
      await repo.addItem(householdId, name: 'Milk', categoryId: dairy.id);
      clockTime = clockTime.add(const Duration(minutes: 1));
      await repo.addItem(householdId, name: 'milk');
      clockTime = clockTime.add(const Duration(minutes: 1));
      await repo.addItem(householdId, name: 'Mint');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      await tester.enterText(quickAddInput(), 'mi');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('milk'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Dairy'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.1'),
          matching: find.text('Mint'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.2'),
        findsNothing,
      );

      // Clearing the field hides the suggestions again.
      await tester.enterText(quickAddInput(), '');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'suggestions include items cleared from the list (soft-deleted), and '
    'tapping one adds it immediately with its most recent category',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final dairy = await CategoryRepository(database).createCategory(
        householdId,
        kind: CategoryKind.shopping,
        name: 'Dairy',
        icon: 'egg',
        color: 0xFF8C7BC9,
      );
      final repo = ShoppingRepository(database, newId: () => 'milk-1');
      final milk = await repo.addItem(
        householdId,
        name: 'Milk',
        categoryId: dairy.id,
      );
      await repo.setChecked(milk.id, checked: true);
      await repo.clearChecked(householdId);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsNothing);

      await tester.enterText(quickAddInput(), 'Mi');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Milk'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('shopping.suggestion.0'));
      await tester.pumpAndSettle();

      // Added immediately with the inherited category; suggestions gone,
      // input cleared, focus kept for the next entry.
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Dairy'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(quickAddInput()).controller?.text,
        isEmpty,
      );
      expect(tester.testTextInput.isVisible, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'focusing the empty quick-add field shows the top-5 suggestions by the '
    'same ranking, excluding a name that currently has an active item on '
    'the list; typing a prefix still narrows as before',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      var clockTime = DateTime.utc(2026, 7);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'seed-${nextId++}',
        nowUtc: () => clockTime,
      );
      Future<String> addAt(String name) async {
        final item = await repo.addItem(householdId, name: name);
        clockTime = clockTime.add(const Duration(minutes: 1));
        return item.id;
      }

      // Six distinct history names with varying frequencies. "Milk" ends
      // up the highest-frequency name overall but is left ACTIVE
      // (currently on the list) — everything else is soft-deleted
      // (cleared) history, same as other suggestion tests. Without
      // exclusion, "Milk" would rank #2 overall and bump "Butter" out of
      // the top 5; with exclusion, "Butter" must appear instead.
      final butter = await addAt('Butter'); // freq 1, oldest of the trio
      final eggs = await addAt('Eggs'); // freq 1, middle
      final cheese = await addAt('Cheese'); // freq 1, most recent of trio
      final bread1 = await addAt('Bread');
      final bread2 = await addAt('Bread'); // freq 2
      final milk1 = await addAt('Milk');
      final milk2 = await addAt('Milk');
      final milk3 = await addAt('Milk'); // freq 3 total — kept active below
      final bananas = [
        await addAt('Bananas'),
        await addAt('Bananas'),
        await addAt('Bananas'),
        await addAt('Bananas'), // freq 4 — highest overall
      ];

      // Soft-delete every history row except the one "Milk" instance that
      // represents it currently sitting on the list.
      for (final id in [
        butter,
        eggs,
        cheese,
        bread1,
        bread2,
        milk1,
        milk2,
        ...bananas,
      ]) {
        await repo.deleteItem(id);
      }
      expect(milk3, isNotEmpty);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);

      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();

      Finder suggestionText(int index, String text) => find.descendant(
        of: find.bySemanticsIdentifier('shopping.suggestion.$index'),
        matching: find.text(text),
      );

      // Top 5 by frequency (Bananas 4, Bread 2, then the freq-1 trio by
      // recency), with "Milk" excluded even though it would otherwise
      // outrank everything but Bananas.
      expect(suggestionText(0, 'Bananas'), findsOneWidget);
      expect(suggestionText(1, 'Bread'), findsOneWidget);
      expect(suggestionText(2, 'Cheese'), findsOneWidget);
      expect(suggestionText(3, 'Eggs'), findsOneWidget);
      expect(suggestionText(4, 'Butter'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.5'),
        findsNothing,
      );
      // "Milk" is on the list already — it must not show up as a
      // suggestion here even though its history outranks most of the above.
      for (var i = 0; i < 5; i++) {
        expect(suggestionText(i, 'Milk'), findsNothing);
      }

      // Typing a prefix narrows to the existing type-ahead behavior.
      await tester.enterText(quickAddInput(), 'ba');
      await tester.pumpAndSettle();
      expect(suggestionText(0, 'Bananas'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.1'),
        findsNothing,
      );

      // Blurring the field hides the list again.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
