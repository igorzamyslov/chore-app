import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's destructive 'Reset app data'
/// row and its double-confirm flow (spec `docs/specs/polish-round-1.md`
/// B2).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  /// Adds a second member, a chore (with its pending occurrence), and a
  /// shopping item to the bootstrap household, and marks both shown-once
  /// banner flags -- so there is real data to lose (or not lose, on
  /// cancel) beyond what bootstrap creates automatically.
  Future<void> seedExtraData(AppDatabase database, String householdId) async {
    await HouseholdRepository(
      database,
    ).addMember(householdId, name: 'Kid', color: 0xFF8C7BC9);

    final choreService = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    await choreService.createChore(
      householdId: householdId,
      title: 'Vacuum',
      startDate: PlainDate.fromDateTime(today),
      assignmentMode: AssignmentMode.anyone,
    );

    await ShoppingRepository(database).addItem(householdId, name: 'Milk');

    final settingsRepository = SettingsRepository(database);
    await settingsRepository.markOnboardingNamePromptShown();
    await settingsRepository.markDigestPrepromptShown();
  }

  testChoreApp(
    'cancelling the first dialog is a no-op: no data lost, second dialog '
    'never appears',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await seedExtraData(database, householdId);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.reset.confirm1'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.reset.cancel1'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.reset.confirm1'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.reset.confirm2'),
        findsNothing,
      );
      expect(await database.select(database.chores).get(), hasLength(1));
      expect(await database.select(database.members).get(), hasLength(2));

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the second (final) dialog is a no-op: no data lost',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await seedExtraData(database, householdId);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.reset.confirm2'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.reset.cancel'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.reset.confirm2'),
        findsNothing,
      );
      expect(await database.select(database.chores).get(), hasLength(1));
      expect(await database.select(database.shoppingItems).get(), hasLength(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'confirming both dialogs wipes every table and re-bootstraps to the '
    'fresh-install state',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await seedExtraData(database, householdId);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();

      // households: exactly one, freshly re-bootstrapped (a new row, since
      // the old one was deleted).
      final households = await database.select(database.households).get();
      expect(households, hasLength(1));
      final newHouseholdId = households.single.id;

      // members: exactly the bootstrap 'Me' admin, in the new household.
      final members = await database.select(database.members).get();
      expect(members, hasLength(1));
      expect(members.single.name, 'Me');
      expect(members.single.role, MemberRole.admin);
      expect(members.single.householdId, newHouseholdId);

      // categories: the default seed set reappears (7 chore + 8 shopping).
      final categories = await database.select(database.categories).get();
      expect(categories, hasLength(15));

      // Everything else is gone.
      expect(await database.select(database.chores).get(), isEmpty);
      expect(await database.select(database.choreAssignees).get(), isEmpty);
      expect(await database.select(database.choreOccurrences).get(), isEmpty);
      expect(await database.select(database.shoppingItems).get(), isEmpty);

      // settings: a fresh row, shown-once flags NULL again (so the A2/A3
      // banners can show once more, per the spec).
      final settings = await database.select(database.settings).getSingle();
      expect(settings.onboardingNamePromptShownAt, null);
      expect(settings.digestPrepromptShownAt, null);
      expect(settings.digestEnabled, true);
      expect(settings.digestMinutes, 480);

      // The app is usable again, not stuck on an error state: the digest
      // section (which watches settingsProvider, whose underlying row this
      // reset also deleted) is still rendering correctly.
      expect(
        find.bySemanticsIdentifier('settings.digest.toggle'),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('settings.reset'), findsOneWidget);

      handle.dispose();
    },
  );
}
