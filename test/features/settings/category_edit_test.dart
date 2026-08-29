import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/features/categories/category_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'rename round-trip, empty-name error + recovery, icon/color change '
    'persists',
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

      await openManageCategories(tester);
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.categories.name'),
          matching: find.text('Cleaning'),
        ),
        findsOneWidget,
      );

      // Empty-name error blocks save, and the sheet stays open.
      await tester.enterText(nameField, '');
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();
      expect(find.text('Name is required'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsOneWidget,
      );

      // Recovery: a valid name, plus an icon and color change, saves fine.
      await tester.enterText(nameField, 'Tidying');
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.icon.yard'),
      );
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.color.1'),
      );
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.categories.save'),
        findsNothing,
      );
      expect(find.text('Tidying'), findsOneWidget);
      expect(find.text('Cleaning'), findsNothing);

      final updated = await (database.select(
        database.categories,
      )..where((tbl) => tbl.id.equals(cleaning.id))).getSingle();
      expect(updated.name, 'Tidying');
      expect(updated.icon, 'yard');
      expect(updated.color, CategoryRepository.seedColors[1]);

      // Re-open: the rename round-tripped into the prefilled field.
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.${cleaning.id}'),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.categories.name'),
          matching: find.text('Tidying'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'add flow creates a category with the default icon and first free '
    'color, appended at the end',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      await openManageCategories(tester);

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

      final categories = await activeCategories(
        database,
        householdId,
        CategoryKind.chore,
      );
      final created = categories.firstWhere((c) => c.name == 'Recycling');

      // 7 seeded chore categories use seedColors[0..6]; the 8th (last) is
      // the only free one.
      expect(created.icon, 'label');
      expect(created.color, CategoryRepository.seedColors[7]);
      expect(created.sortOrder, 7);

      handle.dispose();
    },
  );

  testChoreApp(
    'the icon grid renders every identifier, and picking one of the nine '
    'new ones (backlog G-5a) persists',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openManageCategories(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();

      // Every identifier in the real list has a rendered, tappable tile --
      // if any were missing its semantic id, this loop catches it directly,
      // independent of theme_test.dart's pure-function check.
      for (final identifier in categoryIconIdentifiers) {
        expect(
          find.bySemanticsIdentifier('settings.categories.icon.$identifier'),
          findsOneWidget,
          reason: 'missing icon tile for "$identifier"',
        );
      }

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Bathroom');
      await tester.tap(
        find.bySemanticsIdentifier('settings.categories.icon.bathtub'),
      );
      await tester.tap(find.bySemanticsIdentifier('settings.categories.save'));
      await tester.pumpAndSettle();

      expect(find.text('Bathroom'), findsOneWidget);

      final categories = await activeCategories(
        database,
        await currentHouseholdId(database),
        CategoryKind.chore,
      );
      final created = categories.firstWhere((c) => c.name == 'Bathroom');
      expect(created.icon, 'bathtub');

      handle.dispose();
    },
  );
}
