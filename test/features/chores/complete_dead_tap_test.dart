import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// Regression test for the silent dead tap FIX 4(a) closes: before it,
/// `ChoresListScreen._complete` returned with no snackbar whenever
/// `actingMemberProvider` resolved to `null` AND the occurrence had no
/// assignee to fall back on -- reachable since T1.3 made
/// `actingMemberProvider` return `null` while pinned with no claim yet
/// resolved (spec `docs/specs/members-management.md` §4.2's "adopted
/// offline, or before the first pull" window), whereas before T1.3 it could
/// never be null while members existed.
const _user = AuthUser(id: 'u-1', email: 'me@example.com');

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'tapping complete with no resolvable acting member AND no assignee '
    'surfaces a snackbar instead of silently doing nothing',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: _user),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      // Linked AND signed in (pinned mode) but the claim has NOT reached
      // this device yet (no member's userId set to 'u-1') and no acting
      // member is stored either -- exactly the pre-claim window
      // `actingMemberProvider`'s doc comment describes, which resolves to
      // `null` rather than guessing the first admin.
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: today);

      // AssignmentMode.anyone with no assignees: the occurrence's own
      // assignedMember fallback is also null, so completedBy has nothing
      // left to resolve to.
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Water plants',
            startDate: PlainDate(2026, 7, 24),
            assignmentMode: AssignmentMode.anyone,
          );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      // Not silently dropped: a snackbar explains the device doesn't know
      // who the user is, and the occurrence stays open (no completion was
      // ever recorded).
      expect(
        find.text(
          "This device doesn't know who you are yet. Sign in again or "
          'reopen the app.',
        ),
        findsOneWidget,
      );
      final occurrences = await database
          .select(database.choreOccurrences)
          .get();
      expect(occurrences.single.status, OccurrenceStatus.pending);

      handle.dispose();
    },
  );
}
