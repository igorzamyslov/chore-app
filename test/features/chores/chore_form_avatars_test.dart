import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget-level tests for field feedback F3
/// (`docs/feedback/2026-08-01-field-feedback.md`): the chore form's
/// assignee chips (fixed and rotation modes alike — they're the same
/// widget, the rotation order badge is just a label variant) show a
/// [MemberAvatar] per member, not just their name.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder chipFor(String memberId) =>
      find.bySemanticsIdentifier('chore_form.assignee.$memberId');

  testChoreApp(
    'fixed-mode assignee chips each show a MemberAvatar before the name',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      final me = (await database.select(database.members).get()).firstWhere(
        (member) => member.id != anna.id,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.fixed'),
      );
      await tester.pumpAndSettle();

      for (final memberId in [me.id, anna.id]) {
        expect(
          find.descendant(
            of: chipFor(memberId),
            matching: find.byType(MemberAvatar),
          ),
          findsOneWidget,
        );
      }

      handle.dispose();
    },
  );

  testChoreApp(
    'rotation-mode assignee chips keep their avatar alongside the tap-order '
    'label',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      final me = (await database.select(database.members).get()).firstWhere(
        (member) => member.id != anna.id,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.rotation'),
      );
      await tester.pumpAndSettle();

      // Tap order: Anna first, then Me.
      await tester.tap(chipFor(anna.id));
      await tester.pumpAndSettle();
      await tester.tap(chipFor(me.id));
      await tester.pumpAndSettle();

      expect(find.text('1. Anna'), findsOneWidget);
      expect(find.text('2. Me'), findsOneWidget);
      for (final memberId in [me.id, anna.id]) {
        expect(
          find.descendant(
            of: chipFor(memberId),
            matching: find.byType(MemberAvatar),
          ),
          findsOneWidget,
        );
      }

      handle.dispose();
    },
  );
}
