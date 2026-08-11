import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the membership-revoked notice (spec
/// `docs/specs/household-lifecycle.md` §3.5): the honest replacement for a
/// device that silently stopped syncing. Uses the project's shared
/// [testChoreApp] harness (a real pumped `ChoreApp` against a real
/// in-memory database), which owns the database's lifecycle -- unlike two
/// earlier drafts of this test that hand-rolled a `ProviderScope` pump and
/// closed the database in `tearDown`, both of which hung `flutter test`
/// (see `test/test_utils/pump_app.dart`'s header for why).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'renders nothing when the flag is not set',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('membership.revoked.banner'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'explains the revocation when the flag is set',
    today: today,
    (tester, database) async {
      await SettingsRepository(database).setMembershipRevoked();

      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('membership.revoked.banner'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'acknowledging without ticking the box keeps local data (D-L3)',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(database).setMembershipRevoked();

      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.acknowledge'),
      );
      await tester.pumpAndSettle();
      // Deliberately NOT ticking `membership.revoked.deleteLocal` -- the
      // default is to keep this phone's copy.
      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.confirm'),
      );
      await tester.pumpAndSettle();

      final households = await database.select(database.households).get();
      expect(
        households.map((h) => h.id),
        contains(householdId),
        reason: "D-L3: the default is to keep this phone's copy",
      );
      final settings = await SettingsRepository(database).ensureSettings();
      expect(settings.membershipRevoked, isFalse);

      handle.dispose();
    },
  );

  testChoreApp(
    'acknowledging with the box ticked wipes this device',
    today: today,
    (tester, database) async {
      await SettingsRepository(database).setMembershipRevoked();

      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.acknowledge'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.deleteLocal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.confirm'),
      );
      await tester.pumpAndSettle();

      // resetAppData clears every table, which is what returns the app to
      // the welcome screen. This is the destructive path; without a test
      // it is the one nobody finds out is broken until a user runs it.
      final households = await database.select(database.households).get();
      expect(households, isEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'cancelling the sheet leaves the notice in place and deletes nothing',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(database).setMembershipRevoked();

      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.acknowledge'),
      );
      await tester.pumpAndSettle();
      // Even with the wipe box ticked, Cancel must still delete nothing --
      // this pins that the checkbox state never leaks out on a decline.
      await tester.tap(
        find.bySemanticsIdentifier('membership.revoked.deleteLocal'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('membership.revoked.cancel'));
      await tester.pumpAndSettle();

      final households = await database.select(database.households).get();
      expect(
        households.map((h) => h.id),
        contains(householdId),
        reason: 'cancelling must not delete local data',
      );
      final settings = await SettingsRepository(database).ensureSettings();
      expect(
        settings.membershipRevoked,
        isTrue,
        reason:
            'the user has not yet made a choice -- clearing the flag here '
            'would silence the notice forever while the device stays '
            'unsynced',
      );
      expect(
        find.bySemanticsIdentifier('membership.revoked.banner'),
        findsOneWidget,
        reason: 'the notice must still be showing after a decline',
      );

      handle.dispose();
    },
  );
}
