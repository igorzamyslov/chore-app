import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// A-5 "Mark done for…" (spec `docs/feedback/2026-08-07-field-feedback.md`
/// B1): the rare "I finished something for someone else" case, as ONE row
/// in the chore action sheet — offered only where the switcher was taken
/// away (linked AND signed in), never on the tile, and never on the
/// one-tap complete path.
const _user = AuthUser(id: 'u-1', email: 'me@example.com');

/// Links the household and mirrors [_user]'s claim onto [memberId], exactly
/// as `HouseholdLinkService.adopt` now does.
Future<void> _linkAndClaim(
  AppDatabase database, {
  required String householdId,
  required String memberId,
  required DateTime now,
}) async {
  await (database.update(
    database.members,
  )..where((tbl) => tbl.id.equals(memberId))).write(
    const MembersCompanion(userId: Value('u-1')),
  );
  await SettingsRepository(
    database,
  ).setSyncLinked(householdId: householdId, linkedAt: now);
}

Future<void> _pumpUntilVisible(WidgetTester tester, String id) async {
  for (var i = 0; i < 400; i++) {
    if (find.bySemanticsIdentifier(id).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('$id never appeared');
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<Chore> seedChore(AppDatabase database, String householdId) {
    return ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    ).createChore(
      householdId: householdId,
      title: 'Water plants',
      startDate: PlainDate(2026, 7, 24),
      assignmentMode: AssignmentMode.anyone,
    );
  }

  testChoreApp(
    'a local-only household never sees the Mark done for… row',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF112233);
      final chore = await seedChore(database, householdId);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.menu.skip'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.menu.markDoneFor'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'linked and signed in with someone else in the household, the row is '
    'there — and completing normally is still one tap',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: _user),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF112233);
      final chore = await seedChore(database, householdId);
      await _linkAndClaim(
        database,
        householdId: householdId,
        memberId: me.id,
        now: today,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await _pumpUntilVisible(tester, 'chores.menu.markDoneFor');
      expect(find.text('Mark done for…'), findsOneWidget);

      // Close the sheet and complete normally: ONE tap, no picker, no
      // prompt, credited to me (Igor's constraint).
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chores.markDoneFor.sheet'),
        findsNothing,
      );
      final closed =
          await (database.select(
                database.choreOccurrences,
              )..where((tbl) => tbl.status.equalsValue(OccurrenceStatus.done)))
              .getSingle();
      expect(closed.completedBy, me.id);

      handle.dispose();
    },
  );

  testChoreApp(
    'a linked household of one has nobody to credit, so no row',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(currentUser: _user),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
      final chore = await seedChore(database, householdId);
      await _linkAndClaim(
        database,
        householdId: householdId,
        memberId: me.id,
        now: today,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.menu.skip'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chores.menu.markDoneFor'),
        findsNothing,
      );

      handle.dispose();
    },
  );
}
