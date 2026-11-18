import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/shopping/shopping_suggestions_list.dart';
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
      // The category is shown as its ICON ONLY, and leading: a category
      // name is regularly longer than the item it describes, so drawing it
      // doubled the chip width and pushed the item name out of a glanceable
      // position. Three separate things are pinned here, because dropping
      // the text could silently drop the information too.
      final chip0 = find.bySemanticsIdentifier('shopping.suggestion.0');
      // 1. The name is NOT drawn any more.
      expect(
        find.descendant(of: chip0, matching: find.text('Dairy')),
        findsNothing,
      );
      // 2. But it IS still announced. An `Icon` without a `semanticLabel`
      //    is invisible to a screen reader, so this is the assertion that
      //    stops the change from being a regression for anyone not looking
      //    at the pixels. Asserted on the chip's MERGED label rather than as
      //    a node of its own: `ActionChip` is a semantics container and
      //    folds its descendants in, so what a screen reader actually reads
      //    out is one node carrying both halves.
      // 2. But it IS still announced. An `Icon` without a `semanticLabel`
      //    is invisible to a screen reader, so this is the assertion that
      //    stops the change from being a regression for anyone not looking
      //    at the pixels. Asserted on the CHIP's node, not the `semantic()`
      //    wrapper's: the wrapper carries the identifier and an empty label,
      //    while `ActionChip` is the semantics container that folds its
      //    descendants in. What a reader announces here is "Dairy\nmilk".
      expect(
        tester
            .getSemantics(
              find.descendant(of: chip0, matching: find.byType(ActionChip)),
            )
            .label,
        allOf(contains('Dairy'), contains('milk')),
      );
      // 3. The icon sits to the LEFT of the item name. Compared by x rather
      //    than by child order so it pins what the user actually sees.
      final iconX = tester
          .getTopLeft(find.descendant(of: chip0, matching: find.byType(Icon)))
          .dx;
      final nameX = tester
          .getTopLeft(find.descendant(of: chip0, matching: find.text('milk')))
          .dx;
      expect(iconX, lessThan(nameX));
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
      // `docs/specs/theme-v2.md` §4.3). This is now the ONLY place the
      // category name is drawn on this screen: the suggestion chip shows
      // the icon alone (asserted above), so a bare `find.text('DAIRY')`
      // can no longer be satisfied by a chip.
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
    'focusing the empty quick-add field shows the top suggestions by the '
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
      // exclusion, "Milk" would rank #2 overall and push every name after
      // Bananas down a slot; with exclusion, it must not appear at all.
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

      // Every eligible name by frequency (Bananas 4, Bread 2, then the
      // freq-1 trio by recency), with "Milk" excluded even though it would
      // otherwise outrank everything but Bananas -- so there is no 6th.
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
    'tapping a proposal removes it from the shown suggestions and pulls in '
    'the next candidate (bug 4, field feedback round 2)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      // One more equal-frequency (1 each) name than the limit, seeded
      // oldest first so recency ranks them newest-first: the last one
      // seeded is #0 and "Item00" (oldest) is left just outside the limit.
      final names = [
        for (var i = 0; i <= shoppingSuggestionPageSize; i++)
          'Item${i.toString().padLeft(2, '0')}',
      ];
      await seedBoughtHistory(database, householdId, names);
      final newest = names.last;

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();

      Finder suggestionText(int index, String text) => find.descendant(
        of: find.bySemanticsIdentifier('shopping.suggestion.$index'),
        matching: find.text(text),
      );
      const last = shoppingSuggestionPageSize - 1;

      // Newest-first up to the limit; "Item00" (oldest) is not shown yet.
      expect(suggestionText(0, newest), findsOneWidget);
      expect(suggestionText(last, names[1]), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          'shopping.suggestion.$shoppingSuggestionPageSize',
        ),
        findsNothing,
      );
      expect(find.text('Item00'), findsNothing);

      // Tap the top suggestion: it gets added (now active), so it drops out
      // of the candidate pool entirely, everything closes up one slot, and
      // "Item00" -- the previously-excluded one -- moves into the last slot.
      await tester.tap(find.bySemanticsIdentifier('shopping.suggestion.0'));
      await tester.pumpAndSettle();

      expect(find.text(newest), findsOneWidget); // now on the list
      expect(suggestionText(0, newest), findsNothing);
      expect(suggestionText(0, names[names.length - 2]), findsOneWidget);
      expect(suggestionText(last, 'Item00'), findsOneWidget);

      handle.dispose();
    },
  );

  // Amendment 2026-11-18 (`docs/specs/ui-shopping.md`): more suggestions,
  // without them taking the whole screen.
  Finder suggestionsArea() =>
      find.bySemanticsIdentifier('shopping.suggestions');
  Finder inArea(Finder matching) =>
      find.descendant(of: suggestionsArea(), matching: matching);
  // The mask is always in the tree (so the scroll view never remounts);
  // whether it fades is its blend mode.
  bool fading(WidgetTester tester) =>
      tester.widget<ShaderMask>(inArea(find.byType(ShaderMask))).blendMode ==
      BlendMode.dstIn;
  ScrollPosition areaPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(inArea(find.byType(Scrollable))).position;

  testChoreApp(
    'more suggestions than fit: the area is capped at three and a half chip '
    'rows and fades at the bottom; dragging the chips scrolls them without '
    'unfocusing the field, and a chip from the scrolled part can be tapped '
    'without losing the position',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      // Exactly one page of history, so the end of the strip is the end of
      // the history (paging has its own test below).
      final names = [
        for (var i = 0; i < shoppingSuggestionPageSize; i++)
          'Weekly staple ${i.toString().padLeft(2, '0')}',
      ];
      await seedBoughtHistory(database, householdId, names);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();

      // One page on the focus path: exactly that many chips.
      expect(
        find.bySemanticsIdentifier(
          'shopping.suggestion.${shoppingSuggestionPageSize - 1}',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'shopping.suggestion.$shoppingSuggestionPageSize',
        ),
        findsNothing,
      );

      // Capped: three full rows plus half of a fourth (spacing 8 between
      // rows), plus the area's own 8 bottom padding -- less than the wrap.
      final chipHeight = tester
          .getSize(find.bySemanticsIdentifier('shopping.suggestion.0'))
          .height;
      final areaHeight = tester.getSize(suggestionsArea()).height;
      expect(areaHeight, moreOrLessEquals(chipHeight * 3.5 + 3 * 8 + 8));
      expect(
        tester.getSize(inArea(find.byType(Wrap))).height,
        greaterThan(areaHeight + chipHeight),
      );
      // The cut row is what says "more": a chip in the FOURTH row straddles
      // the bottom edge of the visible area.
      final areaBottom = tester.getBottomLeft(suggestionsArea()).dy - 8;
      final straddling = [
        for (var i = 0; i < shoppingSuggestionPageSize; i++)
          tester.getRect(find.bySemanticsIdentifier('shopping.suggestion.$i')),
      ].where((r) => r.top < areaBottom && r.bottom > areaBottom);
      expect(straddling, isNotEmpty);
      // ...and the fade is on while more sits below.
      expect(fading(tester), isTrue);

      // Drag the chips to the end: they scroll, the fade goes, and the
      // field keeps focus (the list's Bug 3 unfocus is not triggered).
      await tester.drag(
        inArea(find.byType(SingleChildScrollView)),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      final position = areaPosition(tester);
      expect(position.pixels, greaterThan(0));
      expect(position.extentAfter, moreOrLessEquals(0));
      expect(fading(tester), isFalse);
      expect(tester.testTextInput.isVisible, isTrue);

      // The last chip is now in view and tappable; tapping it adds it and
      // keeps the scrolled position (same query), so the next one is a tap
      // away too.
      const lastId = 'shopping.suggestion.${shoppingSuggestionPageSize - 1}';
      final lastName = tester
          .widget<Text>(
            find.descendant(
              of: find.bySemanticsIdentifier(lastId),
              matching: find.byType(Text),
            ),
          )
          .data!;
      await tester.tap(find.bySemanticsIdentifier(lastId));
      await tester.pumpAndSettle();
      expect(find.text(lastName), findsOneWidget); // on the list, not a chip
      expect(areaPosition(tester).pixels, greaterThan(0));

      handle.dispose();
    },
  );

  testChoreApp(
    'scrolling near the end of the chips loads the next page until the '
    'history runs out; a chip tap keeps the loaded pages, a new query and '
    'losing focus go back to the first page',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      // Two full pages and a short third one.
      const total = shoppingSuggestionPageSize * 2 + 5;
      await seedBoughtHistory(database, householdId, [
        for (var i = 0; i < total; i++)
          'Pantry item ${i.toString().padLeft(2, '0')}',
      ]);
      Finder chip(int index) =>
          find.bySemanticsIdentifier('shopping.suggestion.$index');
      Future<void> dragToEnd() async {
        await tester.drag(
          inArea(find.byType(SingleChildScrollView)),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
      }

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(chip(shoppingSuggestionPageSize - 1), findsOneWidget);
      expect(chip(shoppingSuggestionPageSize), findsNothing);

      // Near the end: the next page arrives, appended below what was there
      // (same order, so the user's place is undisturbed), and there is more
      // to scroll again.
      await dragToEnd();
      expect(chip(shoppingSuggestionPageSize * 2 - 1), findsOneWidget);
      expect(chip(shoppingSuggestionPageSize * 2), findsNothing);
      expect(areaPosition(tester).extentAfter, greaterThan(0));
      expect(fading(tester), isTrue);

      // Again: the short last page, and then the end really is the end.
      await dragToEnd();
      expect(chip(total - 1), findsOneWidget);
      expect(chip(total), findsNothing);
      await dragToEnd();
      expect(chip(total - 1), findsOneWidget);
      expect(chip(total), findsNothing);
      expect(areaPosition(tester).extentAfter, moreOrLessEquals(0));
      expect(fading(tester), isFalse);

      // A chip tap re-queries the same (empty) text: everything loaded so
      // far stays, minus the one just added.
      await tester.tap(chip(total - 1));
      await tester.pumpAndSettle();
      expect(chip(total - 2), findsOneWidget);
      expect(chip(total - 1), findsNothing);

      // A new query starts over at one page...
      await tester.enterText(quickAddInput(), 'pan');
      await tester.pumpAndSettle();
      expect(chip(shoppingSuggestionPageSize - 1), findsOneWidget);
      expect(chip(shoppingSuggestionPageSize), findsNothing);

      // ...and so does coming back after losing focus.
      await tester.enterText(quickAddInput(), '');
      await dragToEnd();
      expect(chip(shoppingSuggestionPageSize), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      expect(chip(shoppingSuggestionPageSize - 1), findsOneWidget);
      expect(chip(shoppingSuggestionPageSize), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'when the suggestions fit, the area is exactly as tall as its chips, '
    'shows no fade, and starts at the left gutter',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await seedBoughtHistory(database, householdId, ['Bread', 'Eggs', 'Tea']);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();

      expect(
        tester.getSize(suggestionsArea()).height,
        moreOrLessEquals(tester.getSize(inArea(find.byType(Wrap))).height + 8),
      );
      expect(fading(tester), isFalse);
      // Left-aligned with the area's 16 dp gutter, not centred: a centred
      // wrap shrinks to its widest run, so its left edge moved per query.
      expect(
        tester
            .getTopLeft(find.bySemanticsIdentifier('shopping.suggestion.0'))
            .dx,
        16,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'a new query scrolls the suggestions back to the top; the type-ahead '
    'path uses the same page size',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await seedBoughtHistory(database, householdId, [
        for (var i = 0; i < shoppingSuggestionPageSize + 5; i++)
          'Bean variety ${i.toString().padLeft(2, '0')}',
      ]);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();
      await tester.tap(quickAddInput());
      await tester.pumpAndSettle();
      await tester.drag(
        inArea(find.byType(SingleChildScrollView)),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(areaPosition(tester).pixels, greaterThan(0));

      await tester.enterText(quickAddInput(), 'be');
      await tester.pumpAndSettle();

      expect(areaPosition(tester).pixels, 0);
      expect(
        find.bySemanticsIdentifier(
          'shopping.suggestion.${shoppingSuggestionPageSize - 1}',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          'shopping.suggestion.$shoppingSuggestionPageSize',
        ),
        findsNothing,
      );
      expect(fading(tester), isTrue);

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

  // Both row gestures are 'working the list' in exactly the sense bug 3
  // means, so they owe the same unfocus the check control and a scroll drag
  // already do -- otherwise the suggestion list sits open above a list the
  // user is actively editing, which is the reported bug. The pair used to be
  // swipe-to-delete and the long-press delete menu (backlog D-2/D-3); the
  // 2026-09-19 field report replaced them with tap-to-tick and
  // long-press-to-edit, and the obligation carried straight across.
  testChoreApp(
    'tapping a row to tick it hides the suggestions (bug 3, field feedback '
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
      await repo.addItem(householdId, name: 'Milk');
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

      // The row BODY, not the check ring: the ring's own unfocus is already
      // covered above, and this case exists to prove the row's new tap
      // target inherits it rather than reaching the repository by a second
      // path that forgot to.
      await tester.tap(find.text('Milk'));
      await settleTickBeat(tester);

      expect(
        find.bySemanticsIdentifier('shopping.suggestion.0'),
        findsNothing,
      );
      // Asserted together with the unfocus on purpose: the OLD row tap also
      // unfocused (it opened the edit sheet, equally 'working the list'), so
      // the suggestion assertion ALONE could not fail against the old code
      // and would have been a test that cannot fail. Pinning that the tap
      // also ticked the item is what makes this case load-bearing.
      expect(find.text('In the cart (1)'), findsOneWidget);

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
      // Asserted after backing out of the edit sheet, so the assertion can't
      // be confused by whether a modal route hides the routes below it from
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

/// Seeds [names] as bought-then-cleared history (one row each, oldest
/// first, a minute apart), so every one is an eligible focus-suggestion and
/// recency ranks them newest-first.
Future<void> seedBoughtHistory(
  AppDatabase database,
  String householdId,
  List<String> names,
) async {
  var clockTime = DateTime.utc(2026, 7);
  var nextId = 0;
  final repo = ShoppingRepository(
    database,
    newId: () => 'seed-${nextId++}',
    nowUtc: () => clockTime,
  );
  for (final name in names) {
    final item = await repo.addItem(householdId, name: name);
    await repo.setChecked(item.id, checked: true);
    await repo.deleteItem(item.id);
    clockTime = clockTime.add(const Duration(minutes: 1));
  }
}
