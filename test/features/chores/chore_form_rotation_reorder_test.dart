import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Full-flow coverage for backlog B-4 / triage T2.5: build a rotation by
/// tapping members, reorder it, remove one, and confirm the saved chore
/// persists the final order (not the tap order).
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'reordering and removing a rotation in the form persists the final '
    'order on save',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final householdRepo = HouseholdRepository(database);
      final anna = await householdRepo.addMember(
        householdId,
        name: 'Anna',
        color: 0xFF8C7BC9,
      );
      final ben = await householdRepo.addMember(
        householdId,
        name: 'Ben',
        color: 0xFF4E9A51,
      );
      final me = (await database.select(database.members).get()).firstWhere(
        (member) => member.id != anna.id && member.id != ben.id,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      final titleField = find.descendant(
        of: find.bySemanticsIdentifier('chore_form.title'),
        matching: find.byType(TextField),
      );
      await tester.enterText(titleField, 'Dishes');
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.rotation'),
      );
      await tester.pumpAndSettle();

      // Tap order: Anna, Ben, Me.
      for (final id in [anna.id, ben.id, me.id]) {
        await tester.tap(find.bySemanticsIdentifier('chore_form.assignee.$id'));
        await tester.pumpAndSettle();
      }
      expect(find.text('1. Anna'), findsOneWidget);
      expect(find.text('2. Ben'), findsOneWidget);
      expect(find.text('3. Me'), findsOneWidget);

      // Reorder to Ben, Anna, Me: move index 0 (Anna) to index 1, the same
      // already-adjusted semantics ReorderableListView.builder's
      // onReorderItem provides.
      final reorderable = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      reorderable.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(find.text('1. Ben'), findsOneWidget);
      expect(find.text('2. Anna'), findsOneWidget);
      expect(find.text('3. Me'), findsOneWidget);

      // Remove Anna via her row's remove button. She leaves the rotation
      // list (no drag handle, no order label) and drops back into the
      // not-yet-selected chip row -- so assert on the ROW disappearing,
      // not on her name disappearing from the screen entirely.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignee.${anna.id}.remove'),
      );
      await tester.pumpAndSettle();
      expect(find.text('1. Ben'), findsOneWidget);
      expect(find.text('2. Me'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('chore_form.assignee.${anna.id}.drag'),
        findsNothing,
      );
      expect(find.textContaining('. Anna'), findsNothing);

      // Reorder once more, AFTER the removal. This is what makes the
      // persistence assertion below order-discriminating: the first
      // reorder moved Anna, who was then removed, so [Ben, Me] would be
      // the saved order with or without it. Swapping the two survivors
      // makes the saved order differ from the tap order (Anna, Ben, Me
      // minus Anna = Ben, Me) on the member sequence itself.
      final afterRemoval = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      afterRemoval.onReorderItem!(0, 1);
      await tester.pumpAndSettle();
      expect(find.text('1. Me'), findsOneWidget);
      expect(find.text('2. Ben'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = (await database.select(database.chores).get()).firstWhere(
        (c) => c.title == 'Dishes',
      );
      final details = await ChoreRepository(database).getChore(chore.id);
      // Tap order was Anna, Ben, Me; dropping Anna would leave [Ben, Me].
      // Seeing [Me, Ben] proves chore_assignees.position followed the
      // reordered list, not the order the members were tapped in.
      expect(details!.assigneeMemberIds, [me.id, ben.id]);

      handle.dispose();
    },
  );
}
