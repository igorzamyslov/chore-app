import 'package:chore_app/data/db/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/settings_test_utils.dart';

/// Finds the [ChoiceChip] wrapped by the semantic id
/// `'chore_form.category.$id'`.
ChoiceChip _categoryChip(WidgetTester tester, String id) {
  return tester.widget<ChoiceChip>(
    find.descendant(
      of: find.bySemanticsIdentifier('chore_form.category.$id'),
      matching: find.byType(ChoiceChip),
    ),
  );
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'category picker: edit-categories button opens manage-categories on '
    'the chore kind; a category added there shows up back in the picker',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      // The affordance sits alongside the chore form's chips.
      expect(
        find.bySemanticsIdentifier('category_picker.manage'),
        findsOneWidget,
      );

      // The affordance trails the (horizontally-scrollable) chip row, so
      // scroll it into view before tapping.
      await tester.ensureVisible(
        find.bySemanticsIdentifier('category_picker.manage'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('category_picker.manage'));
      await tester.pumpAndSettle();

      // Opens on the chore section: chore category names show, shopping's
      // don't.
      expect(find.text('Cleaning'), findsOneWidget);
      expect(find.text('Produce'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();
      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Recycling');
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();
      expect(find.text('Recycling'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back in the chore form: the new category shows up in the picker
      // and is selectable like any other.
      final householdId = await currentHouseholdId(database);
      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final recycling = categories.firstWhere((c) => c.name == 'Recycling');
      final recyclingChip = find.bySemanticsIdentifier(
        'chore_form.category.${recycling.id}',
      );
      await tester.ensureVisible(recyclingChip);
      await tester.pumpAndSettle();
      await tester.tap(recyclingChip);
      await tester.pumpAndSettle();
      expect(_categoryChip(tester, recycling.id).selected, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'category picker falls back to None when the selected category is '
    'deleted while the manage-categories screen is open',
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

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.category.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      expect(_categoryChip(tester, cleaning.id).selected, isTrue);

      // Away to manage-categories: delete the category currently selected
      // in the (still-mounted, just covered) form behind it.
      // The affordance trails the (horizontally-scrollable) chip row, so
      // scroll it into view before tapping.
      await tester.ensureVisible(
        find.bySemanticsIdentifier('category_picker.manage'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('category_picker.manage'));
      await tester.pumpAndSettle();
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

      await tester.pageBack();
      await tester.pumpAndSettle();

      // The deleted category's chip is gone; 'None' is selected instead of
      // being left pointing at a category that no longer shows anywhere.
      expect(
        find.bySemanticsIdentifier('chore_form.category.${cleaning.id}'),
        findsNothing,
      );
      expect(_categoryChip(tester, 'none').selected, isTrue);

      // Saving now persists with no category — the fallback isn't just
      // cosmetic.
      final titleField = find.descendant(
        of: find.bySemanticsIdentifier('chore_form.title'),
        matching: find.byType(TextField),
      );
      await tester.enterText(titleField, 'Vacuum floors');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final saved = await (database.select(
        database.chores,
      )..where((tbl) => tbl.title.equals('Vacuum floors'))).getSingle();
      expect(saved.categoryId, isNull);

      handle.dispose();
    },
  );
}
