import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'fake_household_gateway.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the manage-members screen (spec
/// `docs/specs/members-management.md` §3, §6; extended by spec
/// `docs/feedback/2026-08-01-ux-audit.md` A1/A2/A3): bootstrap-only state,
/// the add flow (including the disabled-save guard and cross-screen
/// propagation into the chore form's assignee chips), rename, recolor, the
/// "duplicate names are allowed" invariant shared with chores (see
/// `test/features/chores/duplicate_names_widget_test.dart`), the P2b
/// 'Invite' row (spec `docs/specs/sync-backend.md` §7.3, revoke-then-create
/// per A3), household rename (A2), and member deletion (A1).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<Member> soleBootstrapMember(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    return (database.select(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  }

  testChoreApp(
    'bootstrap-only state: Settings -> Members shows the household-name row '
    'plus exactly one member row, "Me"',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openManageMembers(tester);

      expect(find.text('My household'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));

      handle.dispose();
    },
  );

  testChoreApp(
    'add flow: save disabled on empty/whitespace name; new member appears '
    'in the list and as a chip in the chore form (cross-screen '
    'propagation)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openManageMembers(tester);

      await tester.tap(find.bySemanticsIdentifier('members.add'));
      await tester.pumpAndSettle();

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('members.edit.name'),
        matching: find.byType(TextField),
      );
      FilledButton saveButton() => tester.widget<FilledButton>(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.save'),
          matching: find.byType(FilledButton),
        ),
      );

      // Blank name: save disabled.
      expect(saveButton().onPressed, isNull);

      // Whitespace-only name: still disabled.
      await tester.enterText(nameField, '   ');
      await tester.pump();
      expect(saveButton().onPressed, isNull);

      // A real name enables save.
      await tester.enterText(nameField, 'Anna');
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);

      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      // Appears in the members list.
      expect(find.text('Anna'), findsOneWidget);

      // Cross-screen propagation: back out of the pushed members screen
      // (it covers the bottom tab bar) and into the chore form's assignee
      // chips, which default to the "anyone" mode and need "fixed" tapped
      // to reveal the chip row.
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.fixed'),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'Anna'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'rename: tapping the "Me" row opens a prefilled sheet; saving a new '
    'name updates the list',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      await openManageMembers(tester);

      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('members.edit.name'),
        matching: find.byType(TextField),
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.name'),
          matching: find.text('Me'),
        ),
        findsOneWidget,
      );

      await tester.enterText(nameField, 'Papa');
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      expect(find.text('Papa'), findsOneWidget);
      expect(find.text('Me'), findsNothing);

      final updated = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(updated.name, 'Papa');

      handle.dispose();
    },
  );

  testChoreApp(
    "recolor: picking a different swatch updates the member's avatar color",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);
      // The bootstrap 'Me' member's fixed color isn't part of the seed
      // palette, so any swatch pick below is guaranteed to differ.
      const newColorIndex = 2;
      final newColor = CategoryRepository.seedColors[newColorIndex];

      await openManageMembers(tester);

      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('members.edit.color.$newColorIndex'),
      );
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      final updated = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(updated.color, newColor);

      final avatar = tester.widget<MemberAvatar>(
        find.descendant(
          of: find.bySemanticsIdentifier('members.row.${me.id}'),
          matching: find.byType(MemberAvatar),
        ),
      );
      expect(avatar.member.color, newColor);

      final avatarFinder = find.descendant(
        of: find.bySemanticsIdentifier('members.row.${me.id}'),
        matching: find.byType(CircleAvatar),
      );
      final circleAvatar = tester.widget<CircleAvatar>(avatarFinder);
      // Theme v2 (spec docs/specs/theme-v2.md §1.3): the avatar fill is the
      // seed color's theme-rendered tone, not the raw stored ARGB -- assert
      // via categoryTone rather than the literal `Color(newColor)` this
      // asserted before that wave.
      expect(
        circleAvatar.backgroundColor,
        categoryTone(tester.element(avatarFinder), newColor),
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'duplicate member name is accepted: adding a second "Anna" produces '
    'two rows with no error',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);

      // Seed the first 'Anna' directly through the repository -- this
      // test is about the second (UI-driven) add being accepted despite
      // the collision, not about the add flow itself (covered above).
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      await tester.pumpAndSettle();

      await openManageMembers(tester);
      expect(find.text('Anna'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('members.add'));
      await tester.pumpAndSettle();

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('members.edit.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Anna');
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      expect(find.text('Anna'), findsNWidgets(2));

      handle.dispose();
    },
  );

  testChoreApp(
    'invite row hidden while unlinked',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openManageMembers(tester);

      expect(
        find.bySemanticsIdentifier('settings.members.invite'),
        findsNothing,
      );
      // The household-name row and the bootstrap-only member row are still
      // the only ones.
      expect(find.byType(ListTile), findsNWidgets(2));

      handle.dispose();
    },
  );

  final inviteGateway = FakeHouseholdGateway();
  testChoreApp(
    'invite row visible once linked; tap revokes any previous invite THEN '
    "creates a new one (spec A3), and shows the sheet with the fake's code",
    today: today,
    overrides: [
      householdGatewayProvider.overrideWithValue(inviteGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openManageMembers(tester);

      expect(
        find.bySemanticsIdentifier('settings.members.invite'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.members.invite'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.members.invite.sheet'),
        findsOneWidget,
      );
      expect(find.text('AB3D7XQ9'), findsOneWidget);
      expect(inviteGateway.createInviteCalls, [householdId]);
      expect(inviteGateway.revokeActiveInvitesCalls, [householdId]);
      expect(inviteGateway.inviteCallOrder, ['revoke', 'create']);

      handle.dispose();
    },
  );

  testChoreApp(
    'household rename (spec A2): tapping the household-name row opens a '
    'prefilled sheet; saving updates the row and the linked account '
    'subtitle',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: DateTime.utc(2026));

      await openManageMembers(tester);
      expect(find.text('My household'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('members.household.rename'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.household.rename.name'),
          matching: find.text('My household'),
        ),
        findsOneWidget,
      );

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('members.household.rename.name'),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'The Smiths');
      await tester.tap(
        find.bySemanticsIdentifier('members.household.rename.save'),
      );
      await tester.pumpAndSettle();

      // Members screen row reflects it immediately.
      expect(find.text('The Smiths'), findsOneWidget);
      expect(find.text('My household'), findsNothing);

      final updated = await (database.select(
        database.households,
      )..where((tbl) => tbl.id.equals(householdId))).getSingle();
      expect(updated.name, 'The Smiths');
      expect(updated.syncDirty, isTrue);

      // The linked Account section subtitle (existing stream) reflects it
      // too.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Synced with The Smiths'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'member delete action (spec A1) is hidden, not disabled, for the '
    "household's last remaining member",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'member delete action (spec A1) is hidden, not disabled, for a '
    'claimed member',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);
      final householdId = await currentHouseholdId(database);
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      // Claim 'Me' directly (no local claim flow exists offline) so the
      // "claimed members are undeletable" guard is exercised even though
      // two members now exist.
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u1')),
      );
      await tester.pumpAndSettle();

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'member delete flow (spec A1): deleting a member removes them from the '
    'roster, the chore-form assignee chips, and the acting-member switcher '
    '-- but done-today history still names them',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await soleBootstrapMember(database);
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      await tester.pumpAndSettle();

      // Give 'Me' some done-today history before deleting them.
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = await ChoreRepository(
        database,
      ).pendingOccurrenceOf(chore.id);
      await service.completeOccurrence(pending!.id, completedBy: me.id);
      await tester.pumpAndSettle();

      await openManageMembers(tester);
      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Anna'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('members.edit.delete'));
      await tester.pumpAndSettle();

      // Confirm dialog states the referential consequences; confirm it.
      expect(
        find.bySemanticsIdentifier('members.edit.delete.confirm'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier('members.edit.delete.confirm'),
      );
      await tester.pumpAndSettle();

      // Gone from the members screen roster.
      expect(find.text('Me'), findsNothing);
      expect(find.text('Anna'), findsOneWidget);

      final deleted = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(deleted.deletedAt, isNotNull);

      // Gone from the acting-member switcher (on the Chores tab).
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.actingMember'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('actingMember.sheet.row.${me.id}'),
        findsNothing,
      );
      expect(find.text('Anna'), findsOneWidget);
      await tester.tap(find.text('Anna'));
      await tester.pumpAndSettle();

      // Gone from the chore-form assignee chips.
      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.fixed'),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Me'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Anna'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Done-today history still names the deleted member.
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();
      expect(find.text('by Me'), findsOneWidget);

      handle.dispose();
    },
  );
}
