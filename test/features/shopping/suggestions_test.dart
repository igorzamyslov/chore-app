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
      // The aisle header renders the category name uppercased (spec
      // `docs/specs/theme-v2.md` §4.3) -- unlike the suggestion chip's own
      // `CategoryBadge`, which stays natural-case (asserted above).
      expect(find.text('DAIRY'), findsOneWidget);
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
      // represents it currently sitting on the list. Each is checked
      // before being cleared (bought-then-cleared, like a real
      // `clearChecked` trip) so bug 1's deleted-while-unchecked exclusion
      // (field feedback round 2) does not apply to them — that exclusion
      // is only for items explicitly removed without ever being bought;
      // see the dedicated test below for that case.
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
        await repo.setChecked(id, checked: true);
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

  testChoreApp(
    'tapping an already-focused field re-queries suggestions (bug 2, '
    'field feedback round 2): focus alone only fires on a CHANGE, so a '
    'tap that does not change focus must still refresh the list',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database, newId: () => 'bread-1');
      final bread = await repo.addItem(householdId, name: 'Bread');

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      // First tap: focus goes from none -> focused, and the (empty)
      // history so far shows nothing since "Bread" is still active.
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      // Without ever losing focus, "Bread" gets bought and cleared behind
      // the scenes — it's now eligible, but nothing re-queried the focus
      // node (no focus change happened).
      await repo.setChecked(bread.id, checked: true);
      await repo.clearChecked(householdId);

      // Tapping the field again does NOT change its focus state (it's
      // already focused) — only the explicit `onTap` handler can produce
      // a fresh query here.
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Bread'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'tapping a proposal removes it from the top-5 and pulls in the next '
    'candidate (bug 4, field feedback round 2)',
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

      // Six distinct, equal-frequency (1 each) names, seeded oldest first
      // so recency ranks them newest-first: item5 > item4 > ... > item0.
      // Each is bought-then-cleared so all six are eligible focus
      // suggestions, with "item0" left just outside the initial top 5.
      final names = ['Item0', 'Item1', 'Item2', 'Item3', 'Item4', 'Item5'];
      for (final name in names) {
        final item = await repo.addItem(householdId, name: name);
        await repo.setChecked(item.id, checked: true);
        await repo.deleteItem(item.id);
        clockTime = clockTime.add(const Duration(minutes: 1));
      }

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();

      Finder suggestionText(int index, String text) => find.descendant(
        of: find.bySemanticsIdentifier('shopping.suggestion.$index'),
        matching: find.text(text),
      );

      // Top 5 newest-first; "Item0" (oldest) is the 6th, not shown yet.
      expect(suggestionText(0, 'Item5'), findsOneWidget);
      expect(suggestionText(1, 'Item4'), findsOneWidget);
      expect(suggestionText(2, 'Item3'), findsOneWidget);
      expect(suggestionText(3, 'Item2'), findsOneWidget);
      expect(suggestionText(4, 'Item1'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('shopping.suggestion.5'),
        findsNothing,
      );

      // Tap the top suggestion ("Item5"): it gets added (now active), so
      // it drops out of the candidate pool entirely, and "Item0" — the
      // previously-excluded 6th — moves into the newly-opened 5th slot.
      await tester.tap(find.bySemanticsIdentifier('shopping.suggestion.0'));
      await tester.pumpAndSettle();

      expect(find.text('Item5'), findsOneWidget); // now on the list
      expect(suggestionText(0, 'Item5'), findsNothing);
      expect(suggestionText(0, 'Item4'), findsOneWidget);
      expect(suggestionText(1, 'Item3'), findsOneWidget);
      expect(suggestionText(2, 'Item2'), findsOneWidget);
      expect(suggestionText(3, 'Item1'), findsOneWidget);
      expect(suggestionText(4, 'Item0'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'checking an item off hides the suggestions (bug 3, field feedback '
    'round 2): the quick-add field loses focus once the user works the '
    'list',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final milk = await repo.addItem(householdId, name: 'Milk');
      final bread = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(bread.id, checked: true);
      await repo.deleteItem(bread.id); // an eligible focus-suggestion

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Bread'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${milk.id}.check'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'scrolling the shopping list hides the suggestions (bug 3, field '
    'feedback round 2)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      // Shrink the viewport so a modest number of items overflows it,
      // guaranteeing the drag below is a real, extent-backed scroll.
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);

      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final bread = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(bread.id, checked: true);
      await repo.deleteItem(bread.id); // an eligible focus-suggestion
      for (var i = 0; i < 20; i++) {
        await repo.addItem(householdId, name: 'Filler item $i');
      }

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Bread'),
        ),
        findsOneWidget,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  // The two gestures added by backlog D-2/D-3 are 'working the list' in
  // exactly the sense bug 3 means, so they owe the same unfocus the check
  // control and a scroll drag already do -- otherwise the suggestion list
  // sits open above a list the user is actively editing, which is the
  // reported bug.
  testChoreApp(
    'swiping an item away hides the suggestions (bug 3, field feedback '
    'round 2)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final milk = await repo.addItem(householdId, name: 'Milk');
      final bread = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(bread.id, checked: true);
      await repo.deleteItem(bread.id); // an eligible focus-suggestion

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Bread'),
        ),
        findsOneWidget,
      );

      await tester.drag(
        find.bySemanticsIdentifier('shopping.item.${milk.id}'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'long-pressing an item hides the suggestions (bug 3, field feedback '
    'round 2)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final milk = await repo.addItem(householdId, name: 'Milk');
      final bread = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(bread.id, checked: true);
      await repo.deleteItem(bread.id); // an eligible focus-suggestion

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('shopping.suggestion.0'),
          matching: find.text('Bread'),
        ),
        findsOneWidget,
      );

      await tester.longPress(
        find.bySemanticsIdentifier('shopping.item.${milk.id}'),
      );
      await tester.pumpAndSettle();
      // Asserted after backing out of the menu, so the assertion can't be
      // confused by whether a modal route hides the routes below it from
      // the semantics tree. The unfocus happened at long-press time either
      // way, and nothing refocuses the field on the way back.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );
      expect(find.text('Milk'), findsOneWidget);

      handle.dispose();
    },
  );
}
