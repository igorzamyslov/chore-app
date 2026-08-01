import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_household_gateway.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the manage-members screen (spec
/// `docs/specs/members-management.md` §3, §6): bootstrap-only state, the
/// add flow (including the disabled-save guard and cross-screen
/// propagation into the chore form's assignee chips), rename, recolor, the
/// "duplicate names are allowed" invariant shared with chores (see
/// `test/features/chores/duplicate_names_widget_test.dart`), and the P2b
/// 'Invite' row (spec `docs/specs/sync-backend.md` §7.3).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<Member> soleBootstrapMember(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    return (database.select(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  }

  testChoreApp(
    'bootstrap-only state: Settings -> Members shows exactly one row, "Me"',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openManageMembers(tester);

      expect(find.text('Me'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);

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

      final circleAvatar = tester.widget<CircleAvatar>(
        find.descendant(
          of: find.bySemanticsIdentifier('members.row.${me.id}'),
          matching: find.byType(CircleAvatar),
        ),
      );
      expect(circleAvatar.backgroundColor, Color(newColor));

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
      // The bootstrap-only row is still the only one.
      expect(find.byType(ListTile), findsOneWidget);

      handle.dispose();
    },
  );

  final inviteGateway = FakeHouseholdGateway();
  testChoreApp(
    'invite row visible once linked; tap creates an invite and shows the '
    "sheet with the fake's code",
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

      handle.dispose();
    },
  );
}
