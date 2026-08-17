import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../application/fake_digest_notification_plugin.dart';
import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
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
    'confirming both dialogs wipes every table and returns to the welcome '
    'gate -- no silent re-bootstrap (spec docs/specs/onboarding-v2.md §0: '
    "'no household exists until the user chooses')",
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

      // Nothing household-scoped is silently recreated: the app is back at
      // the TRUE fresh-install state (the welcome gate), not a new
      // 'My household'/'Me' pair.
      expect(await database.select(database.households).get(), isEmpty);
      expect(await database.select(database.members).get(), isEmpty);
      expect(await database.select(database.categories).get(), isEmpty);
      expect(await database.select(database.chores).get(), isEmpty);
      expect(await database.select(database.choreAssignees).get(), isEmpty);
      expect(await database.select(database.choreOccurrences).get(), isEmpty);
      expect(await database.select(database.shoppingItems).get(), isEmpty);

      // settings: a fresh row, shown-once flags NULL again -- still needed
      // regardless of household state (ChoreApp watches settingsProvider
      // unconditionally for locale/theme).
      final settings = await database.select(database.settings).getSingle();
      expect(settings.onboardingNamePromptShownAt, null);
      expect(settings.digestPrepromptShownAt, null);
      expect(settings.digestEnabled, true);
      expect(settings.digestMinutes, 480);

      // The whole tab shell (including Settings) is torn down along with
      // the household -- the welcome gate's create card is what's showing
      // now.
      expect(find.bySemanticsIdentifier('settings.reset'), findsNothing);
      expect(find.bySemanticsIdentifier('welcome.create'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'linked device (spec docs/feedback/2026-08-01-ux-audit.md A6): the '
    "first dialog's body states the household stays online instead of the "
    "unlinked device's false 'no cloud backup' claim",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your household stays online — this phone just disconnects '
          'from it. You can reconnect by signing in again. This still '
          "permanently deletes this phone's local members, chores, and "
          'shopping list.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('There is no cloud backup'), findsNothing);

      handle.dispose();
    },
  );

  final fakeAuth = FakeAuthGateway(
    currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
  );
  testChoreApp(
    'confirming both dialogs signs out the current user (spec '
    'docs/feedback/2026-08-08-prerelease-audit.md P3): Reset is the '
    'opposite of Disconnect, which deliberately keeps the session',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(fakeAuth)],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();

      expect(fakeAuth.currentUser, isNull);

      handle.dispose();
    },
  );

  final fakePlugin = FakeDigestNotificationPlugin();
  testChoreApp(
    'confirming both dialogs cancels the scheduled digest notification '
    '(spec docs/feedback/2026-08-08-prerelease-audit.md P3)',
    today: today,
    overrides: [digestNotificationPluginProvider.overrideWithValue(fakePlugin)],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('settings.reset.confirm2'));
      await tester.pumpAndSettle();

      expect(fakePlugin.cancelCallCount, greaterThanOrEqualTo(1));

      handle.dispose();
    },
  );

  testChoreApp(
    'unlinked device: the first dialog also states that an active '
    'session ends too (spec docs/feedback/2026-08-08-prerelease-audit.md '
    'P3 -- the copy used to never mention an account at all, even though '
    'Reset is reachable while signed in but not yet linked, e.g. mid the '
    'P2b/P2c adopt-or-join choice)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.reset'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("If you're signed in, this also signs you out"),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
