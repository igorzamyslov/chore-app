import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Persona review 2026-10-06 C7 (Maria P3-P): switching assignment mode
/// used to wipe the picked members, and no mode said what it meant.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'Rotation -> Fixed -> Rotation restores the ordered rotation, and Fixed '
    'keeps its own pick',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final households = HouseholdRepository(database);
      final anna = await households.addMember(
        householdId,
        name: 'Anna',
        color: 0xFF8C7BC9,
      );
      final ben = await households.addMember(
        householdId,
        name: 'Ben',
        color: 0xFF4E9A51,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      Future<void> tapId(String id) async {
        final target = find.bySemanticsIdentifier(id);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tapId('chore_form.assignment.rotation');
      await tapId('chore_form.assignee.${ben.id}');
      await tapId('chore_form.assignee.${anna.id}');
      expect(find.text('1. Ben'), findsOneWidget);
      expect(find.text('2. Anna'), findsOneWidget);
      expect(
        find.text('Takes turns in this order, starting at 1.'),
        findsOneWidget,
      );

      await tapId('chore_form.assignment.fixed');
      expect(find.text('Always the same person.'), findsOneWidget);
      await tapId('chore_form.assignee.${anna.id}');

      await tapId('chore_form.assignment.rotation');
      expect(find.text('1. Ben'), findsOneWidget);
      expect(find.text('2. Anna'), findsOneWidget);

      await tapId('chore_form.assignment.anyone');
      expect(find.text('Whoever gets to it.'), findsOneWidget);

      await tapId('chore_form.assignment.fixed');
      final annaChip = tester.widget<FilterChip>(
        find.descendant(
          of: find.bySemanticsIdentifier('chore_form.assignee.${anna.id}'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(annaChip.selected, isTrue);

      handle.dispose();
    },
  );
}
