import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/household_archive.dart';
import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_utils/pump_app.dart';
import 'fake_archive_file_writer.dart';
import 'fake_auth_gateway.dart';
import 'fake_household_gateway.dart';
import 'fake_path_provider_platform.dart';
import 'settings_test_utils.dart';

Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

/// Widget-level tests for the P2c "Join an existing household" flow (spec
/// `docs/specs/sync-backend.md` §7.4, amended 2026-08-01): the join sheet's
/// code entry -> "Are you Anna?"/"I'm new here" chooser -> in-flow import
/// offer -> `HouseholdJoinService.join`
/// (`lib/application/household_join_service.dart`).
///
/// The archive write goes through [FakeArchiveFileWriter] (see that class
/// and `ArchiveFileWriter`'s doc comment in
/// `lib/application/household_archive.dart` for why: a real `dart:io`
/// write, triggered from inside a widget's fire-and-forget tap callback,
/// never reliably completes under `testWidgets`'s automated pumping). The
/// real write path is instead covered by
/// `test/application/household_archive_test.dart` and
/// `test/application/household_join_service_test.dart`, both plain
/// (non-widget) tests.
void main() {
  final today = DateTime(2026, 7, 24, 9);
  final todayDate = PlainDate.fromDateTime(today);
  final signedInAuth = [
    authGatewayProvider.overrideWithValue(
      FakeAuthGateway(
        currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
      ),
    ),
  ];

  late FakeArchiveFileWriter archiveWriter;

  setUp(() {
    PathProviderPlatform.instance = FakePathProviderPlatform('/fake-docs');
    archiveWriter = FakeArchiveFileWriter();
    ArchiveFileWriter.instance = archiveWriter;
  });

  final claimGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
      ClaimableMember(memberId: 'm-bob', name: 'Bob', color: 0xFF8C7BC9),
    ]
    ..claimResultHouseholdId = 'joined-hh'
    ..downloadSnapshotOverride = HouseholdSnapshot(
      household: const Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
      ),
      members: const [
        Member(
          id: 'm-anna',
          householdId: 'joined-hh',
          name: 'Anna',
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      ],
      chores: [
        Chore(
          id: 'jc1',
          householdId: 'joined-hh',
          title: 'Joined chore',
          startDate: todayDate,
          assignmentMode: AssignmentMode.anyone,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      ],
      choreOccurrences: [
        ChoreOccurrence(
          id: 'jo1',
          choreId: 'jc1',
          dueDate: todayDate,
          status: OccurrenceStatus.pending,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      ],
    );

  testChoreApp(
    'join via claim happy path: archive written, old household replaced '
    'with the downloaded snapshot, acting member + linked state set, '
    "chores list shows the JOINED household's data",
    today: today,
    overrides: [
      ...signedInAuth,
      householdGatewayProvider.overrideWithValue(claimGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final oldHouseholdId = await currentHouseholdId(database);
      final choreService = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      await choreService.createChore(
        householdId: oldHouseholdId,
        title: 'Old chore',
        startDate: todayDate,
        assignmentMode: AssignmentMode.anyone,
      );

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.join'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'abc12345',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Are you Anna?'), findsOneWidget);
      expect(find.text('Are you Bob?'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.claim.m-anna'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.join.import.decline'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.import.decline'),
      );
      await tester.pumpAndSettle();

      // Sheet closed; success snackbar names the archive file.
      expect(
        find.bySemanticsIdentifier('settings.account.join.sheet'),
        findsNothing,
      );
      expect(
        find.textContaining('famdo-archive-2026-07-24.json'),
        findsOneWidget,
      );

      expect(claimGateway.listClaimableMembersCalls, ['ABC12345']);
      expect(claimGateway.claimMemberCalls, [
        (code: 'ABC12345', memberId: 'm-anna'),
      ]);
      expect(claimGateway.joinAsNewMemberCalls, isEmpty);
      expect(claimGateway.downloadHouseholdCalls, ['joined-hh']);

      expect(
        archiveWriter.writtenFiles.keys,
        contains('/fake-docs/famdo-archive-2026-07-24.json'),
      );

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, 'm-anna');

      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), ['joined-hh']);

      final chores = await database.select(database.chores).get();
      expect(chores.map((c) => c.id), ['jc1']);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(find.text('Joined chore'), findsOneWidget);
      expect(find.text('Old chore'), findsNothing);

      handle.dispose();
    },
  );

  final newMemberGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
    ]
    ..joinResultHouseholdId = 'joined-hh'
    ..downloadSnapshotOverride = const HouseholdSnapshot(
      household: Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
      ),
    );

  testChoreApp(
    "join via 'I'm new here': joinAsNewMember called with the entered "
    'name and an auto-assigned color, acting member + linked state set',
    today: today,
    overrides: [
      ...signedInAuth,
      householdGatewayProvider.overrideWithValue(newMemberGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.join'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'XYZ98765',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.newMember'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.newMember.name'),
        'Chris',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.newMember.continue'),
      );
      await tester.pumpAndSettle();

      // Decline the import offer -- not the focus of this test.
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.import.decline'),
      );
      await tester.pumpAndSettle();

      expect(newMemberGateway.claimMemberCalls, isEmpty);
      expect(newMemberGateway.joinAsNewMemberCalls, hasLength(1));
      final call = newMemberGateway.joinAsNewMemberCalls.single;
      expect(call.code, 'XYZ98765');
      expect(call.memberName, 'Chris');
      // Anna already uses seedColors[0]; the auto-assigned color must be
      // the next free one in the same palette.
      expect(call.memberColor, CategoryRepository.seedColors[1]);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, 'joined-hh');
      expect(settings.actingMemberId, call.memberId);

      handle.dispose();
    },
  );

  final importGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
    ]
    ..claimResultHouseholdId = 'joined-hh'
    ..downloadSnapshotOverride = const HouseholdSnapshot(
      household: Household(
        id: 'joined-hh',
        name: 'Joined household',
        createdAt: 't0',
        updatedAt: 't0',
      ),
      members: [
        Member(
          id: 'm-anna',
          householdId: 'joined-hh',
          name: 'Anna',
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      ],
    );

  testChoreApp(
    'import accepted: the open chore (with history) becomes a NEW chore '
    '(new id, same title, categoryId null) with a fresh pending '
    'occurrence, only the unchecked shopping item is copied, and '
    'uploadHouseholdData is called with exactly those copies',
    today: today,
    overrides: [
      ...signedInAuth,
      householdGatewayProvider.overrideWithValue(importGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final oldHouseholdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(oldHouseholdId))).getSingle();

      final choreRepo = ChoreRepository(database);
      final choreService = ChoreService(
        database: database,
        chores: choreRepo,
        clock: Clock.fixed(today),
      );
      final oldChore = await choreService.createChore(
        householdId: oldHouseholdId,
        title: 'Recycling',
        startDate: todayDate,
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.weekly(weekdays: {today.weekday}),
      );
      final firstOccurrence = await choreRepo.pendingOccurrenceOf(
        oldChore.id,
      );
      await choreService.completeOccurrence(
        firstOccurrence!.id,
        completedBy: me.id,
      );
      final nextOccurrence = await choreRepo.pendingOccurrenceOf(oldChore.id);
      expect(nextOccurrence, isNotNull);
      expect(nextOccurrence!.dueDate, todayDate.addDays(7));

      final shoppingRepo = ShoppingRepository(database);
      await shoppingRepo.addItem(oldHouseholdId, name: 'Milk');
      final eggs = await shoppingRepo.addItem(oldHouseholdId, name: 'Eggs');
      await shoppingRepo.setChecked(eggs.id, checked: true);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.join'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'IMP0RT01',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.claim.m-anna'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.import.accept'),
      );
      await tester.pumpAndSettle();

      final newChores = await (database.select(
        database.chores,
      )..where((tbl) => tbl.householdId.equals('joined-hh'))).get();
      expect(newChores, hasLength(1));
      final newChore = newChores.single;
      expect(newChore.id, isNot(oldChore.id));
      expect(newChore.title, 'Recycling');
      expect(newChore.categoryId, isNull);
      expect(newChore.assignmentMode, AssignmentMode.anyone);

      final newOccurrences = await (database.select(
        database.choreOccurrences,
      )..where((tbl) => tbl.choreId.equals(newChore.id))).get();
      expect(newOccurrences, hasLength(1));
      final newOccurrence = newOccurrences.single;
      expect(newOccurrence.status, OccurrenceStatus.pending);
      expect(newOccurrence.dueDate, nextOccurrence.dueDate);
      expect(newOccurrence.id, isNot(nextOccurrence.id));

      final newItems = await (database.select(
        database.shoppingItems,
      )..where((tbl) => tbl.householdId.equals('joined-hh'))).get();
      expect(newItems.map((item) => item.name), ['Milk']);
      expect(newItems.single.checkedAt, isNull);
      expect(newItems.single.categoryId, isNull);

      expect(importGateway.uploadHouseholdDataCalls, hasLength(1));
      final uploaded = importGateway.uploadHouseholdDataCalls.single;
      expect(uploaded.chores.map((c) => c.id), [newChore.id]);
      expect(uploaded.choreOccurrences.map((o) => o.id), [newOccurrence.id]);
      expect(uploaded.shoppingItems.map((i) => i.id), [newItems.single.id]);
      expect(uploaded.members, isEmpty);
      expect(uploaded.categories, isEmpty);
      expect(uploaded.choreAssignees, isEmpty);

      // Old household and its history are entirely gone.
      final oldHouseholdRows = await (database.select(
        database.households,
      )..where((tbl) => tbl.id.equals(oldHouseholdId))).get();
      expect(oldHouseholdRows, isEmpty);
      final oldChoreRows = await (database.select(
        database.chores,
      )..where((tbl) => tbl.id.equals(oldChore.id))).get();
      expect(oldChoreRows, isEmpty);

      handle.dispose();
    },
  );

  final invalidCodeGateway = FakeHouseholdGateway()
    ..listClaimableMembersError = Exception('invalid or expired invite');

  testChoreApp(
    'invalid code: listClaimableMembers throwing shows an inline error '
    'and stays on the code step; nothing is deleted',
    today: today,
    overrides: [
      ...signedInAuth,
      householdGatewayProvider.overrideWithValue(invalidCodeGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final oldHouseholdId = await currentHouseholdId(database);

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.join'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'BADCODE1',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          "That code isn't valid or has expired. Please check it and try "
          'again.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join.code'),
        findsOneWidget,
      );

      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), [oldHouseholdId]);

      handle.dispose();
    },
  );

  final exportFailureGateway = FakeHouseholdGateway()
    ..claimableMembers = const [
      ClaimableMember(memberId: 'm-anna', name: 'Anna', color: 0xFF6D9F71),
    ]
    ..claimResultHouseholdId = 'joined-hh';

  testChoreApp(
    'export failure aborts the whole join BEFORE claimMember is ever '
    'called (archive-first ordering): old data stays fully intact',
    today: today,
    overrides: [
      ...signedInAuth,
      householdGatewayProvider.overrideWithValue(exportFailureGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final oldHouseholdId = await currentHouseholdId(database);

      // Force the archive write to fail deterministically.
      archiveWriter.errorToThrow = Exception('disk full');

      await openSettingsTab(tester);
      await tester.tap(find.bySemanticsIdentifier('settings.account.join'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _fieldFor('settings.account.join.code'),
        'ABC12345',
      );
      await tester.pump();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.continue'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.claim.m-anna'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.join.import.decline'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Something went wrong while joining the household. Please try '
          'again.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.join.retry'),
        findsOneWidget,
      );

      // Archive-first: the archive write failed BEFORE claimMember (or
      // downloadHousehold) was ever attempted.
      expect(exportFailureGateway.claimMemberCalls, isEmpty);
      expect(exportFailureGateway.joinAsNewMemberCalls, isEmpty);
      expect(exportFailureGateway.downloadHouseholdCalls, isEmpty);
      expect(archiveWriter.writtenFiles, isEmpty);

      final settings = await database.select(database.settings).getSingle();
      expect(settings.syncHouseholdId, isNull);

      final households = await database.select(database.households).get();
      expect(households.map((h) => h.id), [oldHouseholdId]);

      handle.dispose();
    },
  );
}
