import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'each row exposes a >= 48dp drag handle, and reordering persists via '
    'the repository',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final categoryRepo = CategoryRepository(database);

      final before = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final cleaning = before.firstWhere((c) => c.name == 'Cleaning');
      final kitchen = before.firstWhere((c) => c.name == 'Kitchen');
      expect(before.indexOf(cleaning), lessThan(before.indexOf(kitchen)));

      await openManageCategories(tester);

      // The drag handle (design-language: touch targets >= 48dp) exists
      // for every row and is independently addressable by semantic id.
      final cleaningDragHandle = find.bySemanticsIdentifier(
        'settings.categories.${cleaning.id}.drag',
      );
      final kitchenDragHandle = find.bySemanticsIdentifier(
        'settings.categories.${kitchen.id}.drag',
      );
      expect(cleaningDragHandle, findsOneWidget);
      expect(kitchenDragHandle, findsOneWidget);
      final handleSize = tester.getSize(cleaningDragHandle);
      expect(handleSize.width, greaterThanOrEqualTo(48));
      expect(handleSize.height, greaterThanOrEqualTo(48));

      // Reordering (as the `ReorderableListView`'s `onReorderItem` callback
      // would drive by dragging `cleaningDragHandle` past `kitchenDragHandle`)
      // is a single batch write through `CategoryRepository.reorderCategories`
      // — call it directly here for a deterministic, environment-independent
      // check (gesture-simulated drags are covered, and known flaky under
      // concurrent test execution, in manual/E2E verification instead).
      await categoryRepo.reorderCategories(householdId, CategoryKind.chore, [
        kitchen.id,
        cleaning.id,
        for (final category in before)
          if (category.id != kitchen.id && category.id != cleaning.id)
            category.id,
      ]);
      await tester.pumpAndSettle();

      // Persisted: Kitchen now sorts before Cleaning.
      final after = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final afterNames = after.map((c) => c.name).toList();
      expect(
        afterNames.indexOf('Kitchen'),
        lessThan(afterNames.indexOf('Cleaning')),
      );

      // The manage-categories screen itself reflects the new order too.
      final cleaningY = tester.getCenter(cleaningDragHandle).dy;
      final kitchenY = tester.getCenter(kitchenDragHandle).dy;
      expect(kitchenY, lessThan(cleaningY));

      handle.dispose();
    },
  );
}
