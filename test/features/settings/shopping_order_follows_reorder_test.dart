import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../shopping/shopping_test_utils.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    "a category reorder is reflected in the shopping list's order",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categoryRepo = CategoryRepository(database);
      final shoppingRepo = ShoppingRepository(database);

      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.shopping,
      );
      final produce = categories.firstWhere((c) => c.name == 'Produce');
      final dairy = categories.firstWhere((c) => c.name == 'Dairy');
      expect(categories.indexOf(produce), lessThan(categories.indexOf(dairy)));

      // One item per category, so the shopping list's category-run order
      // reflects the categories' own sort order.
      await shoppingRepo.addItem(
        householdId,
        name: 'Milk',
        categoryId: dairy.id,
      );
      await shoppingRepo.addItem(
        householdId,
        name: 'Apple',
        categoryId: produce.id,
      );

      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      // Baseline: Produce (Apple) sorts before Dairy (Milk).
      var appleY = tester.getTopLeft(find.text('Apple')).dy;
      var milkY = tester.getTopLeft(find.text('Milk')).dy;
      expect(appleY, lessThan(milkY));

      // Reorder so Dairy now sorts before Produce — this is exactly the
      // write `ManageCategoriesScreen`'s drag handler performs (see
      // `manage_categories_reorder_test.dart` for the UI gesture wiring
      // to this same repository call, and
      // `test/data/repositories/category_repository_test.dart` for the
      // repository method's own dedicated coverage).
      await categoryRepo.reorderCategories(householdId, CategoryKind.shopping, [
        dairy.id,
        produce.id,
        for (final category in categories)
          if (category.id != dairy.id && category.id != produce.id) category.id,
      ]);
      await tester.pumpAndSettle();

      // The shopping list itself now shows Dairy's item (Milk) before
      // Produce's item (Apple).
      appleY = tester.getTopLeft(find.text('Apple')).dy;
      milkY = tester.getTopLeft(find.text('Milk')).dy;
      expect(milkY, lessThan(appleY));

      handle.dispose();
    },
  );
}
