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

  /// Seeds a second member already claimed by [userId], so the edit sheet
  /// under test is looking at somebody else's claimed profile.
  ///
  /// Writes `members.userId` directly: `user_id` is server-owned (only the
  /// `create_household`/`claim_member`/`join_as_new_member` RPCs set it) and
  /// no local flow can produce a claim in a widget test.
  Future<Member> claimedMember(
    AppDatabase database, {
    required String name,
    required String userId,
  }) async {
    final householdId = await currentHouseholdId(database);
    final member = await HouseholdRepository(
      database,
    ).addMember(householdId, name: name, color: 0xFF8C7BC9);
    await (database.update(
      database.members,
    )..where((tbl) => tbl.id.equals(member.id))).write(
      MembersCompanion(userId: Value(userId)),
    );
    return member;
  }

  /// Marks this device linked to its bootstrap household, which together
  /// with a signed-in [FakeAuthGateway] is what
  /// `memberIdentityModeProvider` calls `pinned` -- the state the
  /// `remove_member` RPC needs.
  Future<void> linkThisDevice(AppDatabase database) async {
    await SettingsRepository(database).setSyncLinked(
      householdId: await currentHouseholdId(database),
      linkedAt: DateTime.utc(2026),
    );
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
      // `HouseholdRepository.createLocalHousehold` gives the bootstrap 'Me'
      // member `seedColors.first` (== `palette[0]`), so index 2 is
      // guaranteed to differ. It is also free: 'Me' is the only member, and
      // the member being edited is never marked taken by the G-4 uniqueness
      // rule, so every swatch in this household is selectable.
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
        matching: find.byType(MemberAvatar),
      );
      final decoration =
          tester
                  .widget<Container>(
                    find.descendant(
                      of: avatarFinder,
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      // G-4: the avatar is a RING in the member's theme-rendered tone on a
      // neutral ground -- it was a filled circle before that wave, and this
      // assertion checked `CircleAvatar.backgroundColor`. The tone, not the
      // raw stored ARGB, is still what is asserted (spec
      // `docs/specs/theme-v2.md` §1.3).
      expect(
        (decoration.border! as Border).top.color,
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
    "household's last remaining member -- T1.7: a visible explanation "
    'names the actual reason in its place',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);
      expect(
        find.bySemanticsIdentifier('members.edit.deleteBlockedReason'),
        findsOneWidget,
      );
      expect(
        find.text(
          "A household needs at least one member, so this one can't be "
          'removed.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'member delete action is hidden, not disabled, for a claimed member '
    'while this device is signed out and unlinked -- T1.7: a visible '
    'explanation names the actual reason in its place',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);
      final householdId = await currentHouseholdId(database);
      await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      // Claim 'Me' directly (no local claim flow exists offline) so the
      // claimed-target gate is exercised even though two members now exist.
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
      expect(
        find.bySemanticsIdentifier('members.edit.deleteBlockedReason'),
        findsOneWidget,
      );
      // Claim state alone no longer blocks removal (spec
      // `docs/specs/household-lifecycle.md` §3.2, F10) -- this test used to
      // assert the retired `memberEditDeleteBlockedClaimed` copy ("linked to
      // an account, so it can't be removed here"), which is now false. What
      // still blocks HERE is that this device is signed out AND unlinked, so
      // the `remove_member` RPC cannot be made at all.
      expect(
        find.text(
          "This profile is used on someone else's phone. Sign in and connect "
          'to the online household to remove it.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'T1.7: the delete-blocked explanation is specific to the member being '
    'edited -- an unclaimed, non-last member still shows the normal '
    'Delete button with no explanation',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);
      final householdId = await currentHouseholdId(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      // Claim 'Me' so a claimed member exists in the household, but edit
      // ANNA (unclaimed, and not the last member since 'Me' also exists).
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u1')),
      );
      await tester.pumpAndSettle();

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('members.edit.delete'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('members.edit.deleteBlockedReason'),
        findsNothing,
      );

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
      // Picking a non-default assignment mode is enough to dirty the form
      // (C4, docs/feedback/2026-08-06-conventions-audit.md), so backing out
      // now surfaces the discard-changes guard rather than popping
      // straight away -- confirm discarding to leave, since this test
      // doesn't care about the half-filled form itself.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
      );
      await tester.pumpAndSettle();

      // Done-today history still names the deleted member.
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();
      expect(find.text('by Me'), findsOneWidget);

      handle.dispose();
    },
  );

  // ---------------------------------------------------------------------
  // Claimed-member removal (spec `docs/specs/household-lifecycle.md` §3.2,
  // F10). Claim state alone no longer hides Delete: a claimed profile is
  // removable via the `remove_member` RPC by ANY member (D-L2 -- there is
  // no role gate). What still blocks is the last active member, the
  // caller's own claimed row, and a claimed target this device cannot
  // reach the server for.
  // ---------------------------------------------------------------------

  testChoreApp(
    'claimed target, linked and signed in: Delete is shown (spec '
    'docs/specs/household-lifecycle.md §3.2, D-L2 -- no role gate)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'me', email: 'me@x.y'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      await linkThisDevice(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('members.edit.deleteBlockedReason'),
        findsNothing,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'own claimed row: Delete stays hidden and the reason points at Leave '
    '(mirrors the server rejecting self-removal, §2.2)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'me', email: 'me@x.y'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);
      // A second member, so the last-member gate (which outranks this one)
      // is not what hides Delete here.
      await claimedMember(database, name: 'Anna', userId: 'anna-auth');
      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('me')),
      );
      await linkThisDevice(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);
      expect(find.textContaining('your own profile'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'claimed target while signed in but NOT linked: Delete hidden, and the '
    'reason explains the connection requirement rather than a permission',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'me', email: 'me@x.y'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      // Deliberately NO linkThisDevice: signed in is not enough, the
      // household must also be linked. Without this case a gate that
      // checked only "signed in" would stay green.

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('members.edit.delete'), findsNothing);
      expect(find.textContaining('Sign in and connect'), findsOneWidget);

      handle.dispose();
    },
  );

  // Declared out here, not inside the callbacks, so the `overrides` list and
  // the assertions below see the same gateway instance.
  final gatewayForRemoval = FakeHouseholdGateway();
  final failingGateway = FakeHouseholdGateway()
    ..removeMemberError = Exception('offline');

  testChoreApp(
    'removing a claimed member: the confirm names the consequence for their '
    'phone, and confirming calls remove_member then cleans up locally',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'me', email: 'me@x.y'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(gatewayForRemoval),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      await linkThisDevice(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('members.edit.delete'));
      await tester.pumpAndSettle();

      // The claimed body, not the unclaimed one: the effect on the removed
      // person's own phone is the one consequence the person tapping Delete
      // cannot see from here.
      expect(find.textContaining('their own phone'), findsOneWidget);

      await tester.tap(
        find.bySemanticsIdentifier('members.edit.delete.confirm'),
      );
      await tester.pumpAndSettle();

      expect(gatewayForRemoval.removeMemberCalls, [anna.id]);
      expect(find.text('Anna'), findsNothing);
      final removed = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(anna.id))).getSingle();
      expect(removed.deletedAt, isNotNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'a failed removal is shown inline and changes nothing (spec '
    'docs/specs/household-lifecycle.md §3.2)',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'me', email: 'me@x.y'),
        ),
      ),
      householdGatewayProvider.overrideWithValue(failingGateway),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final anna = await claimedMember(
        database,
        name: 'Anna',
        userId: 'anna-auth',
      );
      await linkThisDevice(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${anna.id}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('members.edit.delete'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('members.edit.delete.confirm'),
      );
      await tester.pumpAndSettle();

      // The sheet stays open, says why, and Anna is still a member. This is
      // the ONE failure this app surfaces rather than swallowing into a
      // silent retry (deliberately overriding docs/specs/sync-backend.md
      // §8.3): it needed the network, it changed nothing, and the person
      // the user tried to remove is still here.
      expect(
        find.bySemanticsIdentifier('members.remove.error'),
        findsOneWidget,
      );
      expect(find.textContaining("Couldn't remove Anna"), findsOneWidget);
      final after = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(anna.id))).getSingle();
      expect(after.deletedAt, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'a colour another member holds is disabled and badged with their '
    'initials',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = HouseholdRepository(database);
      // 'Me' (the bootstrap member) holds palette[0]; give Anna palette[3].
      await repo.addMember(
        householdId,
        name: 'Anna',
        color: CategoryRepository.palette[3],
      );
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.name.equals('Me'))).getSingle();

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      // Anna's initials badge her swatch, and tapping it does nothing.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.color.3'),
          matching: find.text('AN'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('members.edit.color.3'));
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      final unchanged = await (database.select(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(
        unchanged.color,
        CategoryRepository.palette.first,
        reason: "tapping Anna's colour must not recolour Me",
      );

      handle.dispose();
    },
  );

  testChoreApp(
    "the member's own current colour stays selectable while editing",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      await openManageMembers(tester);
      await tester.tap(find.bySemanticsIdentifier('members.row.${me.id}'));
      await tester.pumpAndSettle();

      // 'Me' holds palette[0]; it must show the check, not a taken badge.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.color.0'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      // The live preview avatar is present and reads the picked colour.
      final preview = tester.widget<MemberAvatar>(
        find.descendant(
          of: find.bySemanticsIdentifier('members.edit.avatar'),
          matching: find.byType(MemberAvatar),
        ),
      );
      expect(preview.member.color, CategoryRepository.palette.first);
      expect(preview.radius, 33);

      handle.dispose();
    },
  );
}
