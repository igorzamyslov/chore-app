import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the first-run name-prompt banner (spec
/// `docs/specs/polish-round-1.md` A2): show/dismiss/complete paths, plus
/// the upgrading-install silent-mark path.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<Member> soleBootstrapMember(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    return (database.select(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  }

  testChoreApp(
    'shown on a fresh install: message + Set my name + dismiss actions',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('onboarding.name'), findsOneWidget);
      expect(find.bySemanticsIdentifier('onboarding.name.set'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('onboarding.name.dismiss'),
        findsOneWidget,
      );
      expect(find.text("Who's doing the chores here?"), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'dismiss (X) marks the flag and hides the banner',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('onboarding.name.dismiss'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('onboarding.name'), findsNothing);
      final settings = await database.select(database.settings).getSingle();
      expect(settings.onboardingNamePromptShownAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'Set my name opens the member edit sheet prefilled for the bootstrap '
    'member; saving a new name renames it and the banner disappears',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      await tester.tap(find.bySemanticsIdentifier('onboarding.name.set'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.name'),
          matching: find.text('Me'),
        ),
        findsOneWidget,
      );

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('members.edit.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Jordan');
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('onboarding.name'), findsNothing);
      final updated = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(updated.name, 'Jordan');
      // The banner's general "not the bootstrap shape anymore" check marks
      // the flag as a side effect — the same code path an upgrading
      // install's silent mark uses.
      final settings = await database.select(database.settings).getSingle();
      expect(settings.onboardingNamePromptShownAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'upgrading install (household already has more than the bootstrap '
    'member): the banner never shows and the flag is marked silently',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      // Simulate an install that already added a second member before this
      // feature shipped — schema v5's flag defaults to NULL regardless of
      // when the household was first bootstrapped.
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Robin', color: 0xFF8C7BC9);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('onboarding.name'), findsNothing);
      final settings = await database.select(database.settings).getSingle();
      expect(settings.onboardingNamePromptShownAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'flag already marked: the banner stays hidden even though the '
    "household is still just the bootstrap 'Me' member",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).markOnboardingNamePromptShown();
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('onboarding.name'), findsNothing);

      handle.dispose();
    },
  );
}
