import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for B2's in-context "add a member" chip (spec
/// `docs/feedback/2026-08-01-ux-audit.md`): the chore form's assignee
/// picker gets a trailing 'Add member…' chip that opens the new-member
/// sheet inline, without abandoning the form.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    "the assignee row's trailing 'Add member…' chip opens the new-member "
    'sheet inline; saving adds the member and it becomes a selectable chip '
    'in the SAME pumped form (never navigating away)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.fixed'),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'Anna'), findsNothing);
      final addChip = find.bySemanticsIdentifier('chore_form.assignee.add');
      expect(addChip, findsOneWidget);

      await tester.ensureVisible(addChip);
      await tester.pumpAndSettle();
      await tester.tap(addChip);
      await tester.pumpAndSettle();

      final nameField = find.descendant(
        of: find.bySemanticsIdentifier('members.edit.name'),
        matching: find.byType(TextField),
      );
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Anna');
      // The save button only enables once the text-controller listener's
      // setState rebuilds it -- needs a pump between enterText and tap, or
      // the tap lands on a still-disabled (stale) button and is a no-op.
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('members.edit.save'));
      await tester.pumpAndSettle();

      // Sheet closed; still on the chore form -- its title field is proof
      // the form was never left/re-entered.
      expect(find.bySemanticsIdentifier('members.edit.name'), findsNothing);
      expect(find.bySemanticsIdentifier('chore_form.title'), findsOneWidget);

      final annaChip = find.widgetWithText(FilterChip, 'Anna');
      expect(annaChip, findsOneWidget);
      await tester.tap(annaChip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(annaChip).selected, isTrue);

      handle.dispose();
    },
  );
}
