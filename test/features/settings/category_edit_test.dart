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

  testChoreApp(
    'the icon grid is six columns per row regardless of the surface width '
    '(backlog G-15 -- a Wrap fits as many fixed tiles as happen to go in, '
    'which is thirteen on this test surface and six only on a phone)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openManageCategories(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();

      double topOf(String identifier) => tester
          .getTopLeft(
            find.bySemanticsIdentifier('settings.categories.icon.$identifier'),
          )
          .dy;

      // categoryIconIdentifiers[0..5] are cleaning_services, skillet,
      // local_laundry_service, yard, pets, build; [6] is directions_car.
      // Six equal columns per row (design canvas frames 1b/1d,
      // `grid-template-columns: repeat(6, 1fr)`) puts the first six on one
      // row and the seventh on the next -- at EVERY width, because the
      // columns flex. A Wrap of fixed 48px tiles instead fits
      // `floor((W + 8) / 56)` per row: thirteen at this suite's default
      // 800x2400 surface (`test/test_utils/pump_app.dart`), eight on a
      // 480dp phone, six only in the 360-415dp band.
      expect(
        topOf('build'),
        topOf('cleaning_services'),
        reason: 'the sixth icon belongs on the first row',
      );
      expect(
        topOf('directions_car'),
        greaterThan(topOf('cleaning_services')),
        reason:
            'the seventh icon belongs on the SECOND row -- it is on the '
            'first, so the grid is not six columns wide',
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the icon grid spans the sheet width on a phone-sized surface '
    '(backlog G-15 -- Igor saw the block sitting narrower than the sheet on '
    'a real Android device)',
    today: today,
    (tester, database) async {
      // Pin to a ~412dp Android phone. The suite's default 800x2400 surface
      // is more than twice as wide as any phone, which is why no existing
      // test could see this.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = tester.ensureSemantics();
      await openManageCategories(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.categories.add'));
      await tester.pumpAndSettle();

      // Ground truth for "the sheet's content edges": the name field fills
      // the sheet's content width, so measure it rather than re-deriving
      // the sheet's own padding arithmetic here.
      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('settings.categories.name'),
        matching: find.byType(TextField),
      );
      final contentLeft = tester.getTopLeft(nameField).dx;
      final contentRight = tester.getTopRight(nameField).dx;

      final firstTileLeft = tester
          .getTopLeft(
            find.bySemanticsIdentifier(
              'settings.categories.icon.cleaning_services',
            ),
          )
          .dx;
      final lastTileRight = tester
          .getTopRight(
            find.bySemanticsIdentifier('settings.categories.icon.build'),
          )
          .dx;

      // Six equal flexible columns across a 412-32=380px content box are
      // 63.3px wide, and a centred 48px tile is inset (63.3-48)/2 = 7.67px
      // from each end. A Wrap of fixed tiles stops dead at 6*48+5*8 = 328px
      // and is start-aligned, so it is flush left and 52px short on the
      // right. 20 separates 7.67 from 52 without sitting near either.
      expect(
        contentRight - lastTileRight,
        lessThan(20),
        reason:
            'the icon grid must span the sheet the way the colour grid below '
            'it already does (ColorSwatchPicker uses Row+Expanded); it '
            'stops ${(contentRight - lastTileRight).toStringAsFixed(1)}px '
            'short of the sheet content edge',
      );
      // Symmetry: the same inset on both sides is what proves the row was
      // divided into equal columns rather than merely pushed rightwards.
      expect(
        firstTileLeft - contentLeft,
        closeTo(contentRight - lastTileRight, 0.5),
        reason: 'six equal columns leave the same inset at both ends',
      );

      handle.dispose();
    },
  );
}
