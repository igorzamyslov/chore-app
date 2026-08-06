import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// Widget coverage for the checked-items ('In the cart') section's
/// expansion state (field feedback G1, `docs/feedback/2026-08-01-field-
/// feedback.md`): it must survive item moves within the section, default
/// to collapsed on every fresh appearance, and support the 'Put all back'
/// bulk action. See `ShoppingCheckedSection` / `ShoppingListScreen`.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<void> expandCartSection(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'unchecking one of several checked items leaves the cart section open',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final first = await repo.addItem(householdId, name: 'Milk');
      final second = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(first.id, checked: true);
      await repo.setChecked(second.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      // Collapsed by default: expand it to reach the tiles.
      expect(find.text('Milk'), findsNothing);
      await expandCartSection(tester, 'In the cart (2)');
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);

      // Uncheck one of the two — this rebuilds/re-parents the section
      // within the list (it moves "Milk" back under its category header)
      // but must NOT reset the expansion.
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${first.id}.check'),
      );
      await tester.pumpAndSettle();

      expect(find.text('In the cart (1)'), findsOneWidget);
      // Still expanded: the remaining checked tile is visible without
      // tapping the header again.
      expect(find.text('Bread'), findsOneWidget);
      // The unchecked item moved back to the main list.
      expect(find.text('Milk'), findsOneWidget);
      // Aisle headers render their category name uppercased at the widget
      // level (spec `docs/specs/theme-v2.md` §4.3) -- never in the ARB
      // source, since German capitalization rules differ.
      expect(find.text('UNCATEGORIZED'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'the cart section is collapsed by default on every fresh appearance, '
    'including after unmounting (last item unchecked) and reappearing',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      var nextId = 0;
      final repo = ShoppingRepository(
        database,
        newId: () => 'item-${nextId++}',
      );
      final first = await repo.addItem(householdId, name: 'Milk');
      final second = await repo.addItem(householdId, name: 'Bread');
      await repo.setChecked(first.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      // First appearance: collapsed.
      expect(find.text('In the cart (1)'), findsOneWidget);
      expect(find.text('Milk'), findsNothing);

      await expandCartSection(tester, 'In the cart (1)');
      expect(find.text('Milk'), findsOneWidget);

      // Uncheck the only checked item: the section unmounts entirely.
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${first.id}.check'),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );

      // Check a different item: the section reappears — collapsed again,
      // by design, even though it was left expanded before it unmounted.
      await tester.tap(
        find.bySemanticsIdentifier('shopping.item.${second.id}.check'),
      );
      await tester.pumpAndSettle();

      expect(find.text('In the cart (1)'), findsOneWidget);
      expect(find.text('Bread'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    "'Put all back' unchecks every checked item at once, returning them all "
    'to the main list and dismounting the section',
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
      final eggs = await repo.addItem(householdId, name: 'Eggs');
      await repo.setChecked(milk.id, checked: true);
      await repo.setChecked(bread.id, checked: true);
      await repo.setChecked(eggs.id, checked: true);

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      await expandCartSection(tester, 'In the cart (3)');
      expect(find.bySemanticsIdentifier('shopping.uncheckAll'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shopping.uncheckAll'));
      await tester.pumpAndSettle();

      // The section is gone (zero checked items left)...
      expect(
        find.bySemanticsIdentifier('shopping.checked.header'),
        findsNothing,
      );
      expect(find.bySemanticsIdentifier('shopping.uncheckAll'), findsNothing);
      // ...and all three are back, unchecked, in the main list.
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);
      expect(find.text('UNCATEGORIZED'), findsOneWidget);

      handle.dispose();
    },
  );
}
