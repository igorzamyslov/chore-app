import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/ui_state_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// Persona review 2026-10-06 E1 (Leon A4): a signed-in member opens the
/// chores list on THEIR chores (and unassigned "anyone" chores, which the
/// digest also counts), the member menu marks who "you" are, and an
/// unassigned tile says "Anyone" where the avatar would be.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  final authOverride = authGatewayProvider.overrideWithValue(
    FakeAuthGateway(
      currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
    ),
  );

  /// Household of Me + Anna with three chores: "Mine" (Me), "Annas" (Anna),
  /// "Free" (unassigned). When [pinned], this device is linked + signed in
  /// as Me (the member carrying `userId: u-1`).
  Future<({String meId, String annaId})> seed(
    AppDatabase database, {
    required bool pinned,
  }) async {
    final householdId = await currentHouseholdId(database);
    final me = await database.select(database.members).getSingle();
    final anna = await HouseholdRepository(
      database,
    ).addMember(householdId, name: 'Anna', color: 0xFF112233);
    final service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    Future<void> create(String title, {String? assignee}) =>
        service.createChore(
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 7, 24),
          assignmentMode: assignee == null
              ? AssignmentMode.anyone
              : AssignmentMode.fixed,
          assigneeMemberIds: assignee == null ? const [] : [assignee],
        );
    await create('Mine', assignee: me.id);
    await create('Annas', assignee: anna.id);
    await create('Free');
    if (pinned) {
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u-1')),
      );
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: today);
    }
    return (meId: me.id, annaId: anna.id);
  }

  Future<String?> storedMemberFilter(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    final boxed = await tester.runAsync(
      () async => [(await UiStateRepository(database).readUiState())],
    );
    return boxed!.single?.choresMemberFilter;
  }

  testChoreApp(
    'pinned with no stored filter: opens on my chores plus unassigned, and '
    'stores the default so it persists',
    today: today,
    overrides: [authOverride],
    seed: (database) async {
      await seed(database, pinned: true);
    },
    (tester, database) async {
      final me = await database.select(database.members).get();
      final meId = me.firstWhere((m) => m.name == 'Me').id;

      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Annas'), findsNothing);
      expect(await storedMemberFilter(tester, database), meId);
    },
  );

  testChoreApp(
    'pinned but with a stored choice: the stored filter wins',
    today: today,
    overrides: [authOverride],
    seed: (database) async {
      final ids = await seed(database, pinned: true);
      await UiStateRepository(
        database,
      ).setChoresFilters(memberId: ids.annaId, categoryId: null);
    },
    (tester, database) async {
      expect(find.text('Annas'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Mine'), findsNothing);
    },
  );

  testChoreApp(
    'pinned with an explicit stored "All members": stays All, no default',
    today: today,
    overrides: [authOverride],
    seed: (database) async {
      await seed(database, pinned: true);
      await UiStateRepository(database).setChoresFilters(
        memberId: UiStateRepository.allMembersFilter,
        categoryId: null,
      );
    },
    (tester, database) async {
      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('Annas'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(
        await storedMemberFilter(tester, database),
        UiStateRepository.allMembersFilter,
      );
    },
  );

  testChoreApp(
    'a pinned user choosing All members stores it, so it survives a restart',
    today: today,
    overrides: [authOverride],
    seed: (database) async {
      await seed(database, pinned: true);
    },
    (tester, database) async {
      // Opens on "mine" (the default); pick "All members".
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String?>),
          matching: find.text('All members'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Annas'), findsOneWidget);
      expect(
        await storedMemberFilter(tester, database),
        UiStateRepository.allMembersFilter,
      );
    },
  );

  testChoreApp(
    'a local (switching) household still opens unfiltered',
    today: today,
    (tester, database) async {
      await seed(database, pinned: false);
      await tester.pumpAndSettle();

      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('Annas'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(await storedMemberFilter(tester, database), isNull);
    },
  );

  testChoreApp(
    "the member filter keeps unassigned chores and drops other people's",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final ids = await seed(database, pinned: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chores.filter.member.${ids.annaId}'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Annas'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Mine'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the member menu marks the acting member "(you)" once there is more '
    'than one member',
    today: today,
    (tester, database) async {
      await seed(database, pinned: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();

      Finder inMenu(String text) => find.descendant(
        of: find.byType(PopupMenuItem<String?>),
        matching: find.text(text),
      );
      expect(inMenu('Me (you)'), findsOneWidget);
      expect(inMenu('Anna'), findsOneWidget);
      expect(inMenu('Anna (you)'), findsNothing);
    },
  );

  testChoreApp(
    'an unassigned tile shows the "Anyone" chip where the avatar would be',
    today: today,
    (tester, database) async {
      await seed(database, pinned: false);
      await tester.pumpAndSettle();

      // Exactly one unassigned chore ("Free") in the list.
      expect(find.text('Anyone'), findsOneWidget);
    },
  );
}
