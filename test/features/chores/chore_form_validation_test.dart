import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Finds the [TextField] wrapped by the semantic id [identifier].
Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'empty title: inline error, then recovery on a valid title',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();
      expect(find.text('Title is required'), findsOneWidget);

      await tester.enterText(_fieldFor('chore_form.title'), 'Wash dishes');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      // Recovery: the form pops back to the list, which now shows it.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);
      expect(find.text('Wash dishes'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'rotation with one member: inline error, then recovery on two',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final household = HouseholdRepository(database);
      final alex = await household.addMember(
        householdId,
        name: 'Alex',
        color: 0xFF112233,
      );

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Take out trash');

      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignment.rotation'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignee.${alex.id}'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();
      expect(find.text('Pick at least two'), findsOneWidget);

      // Recovery: pick a second member.
      final members = await database.select(database.members).get();
      final me = members.firstWhere((member) => member.id != alex.id);
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.assignee.${me.id}'),
      );
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);
      expect(find.text('Take out trash'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'interval 0: inline error, then recovery on a valid interval',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Water plants');

      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.repeat.interval'), '0');

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();
      expect(find.text('Must be at least 1'), findsOneWidget);

      await tester.enterText(_fieldFor('chore_form.repeat.interval'), '2');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);
      expect(find.text('Water plants'), findsOneWidget);

      handle.dispose();
    },
  );

  // OPD-4's empty-state obligation, and the crash it turned out to hide.
  // The repeat block re-renders on every keystroke, and since G-2 the
  // preview line feeds the interval to the recurrence engine, whose week
  // and month branches divide by it. `int.tryParse(text) ?? 1` covers an
  // unparseable field but not a parseable 0, which reached
  // `weeksDiff ~/ interval` and threw IntegerDivisionByZeroException while
  // the user was still typing.
  testChoreApp(
    'an empty or zero interval keeps the repeat block rendering, preview '
    'included, instead of crashing mid-keystroke',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();

      for (final raw in ['0', '', '-1', 'abc']) {
        await tester.enterText(_fieldFor('chore_form.repeat.interval'), raw);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'the repeat block threw on interval "$raw"',
        );
        expect(
          find.bySemanticsIdentifier('chore_form.repeat.preview'),
          findsOneWidget,
          reason: 'the preview vanished on interval "$raw"',
        );
      }

      handle.dispose();
    },
  );
}
