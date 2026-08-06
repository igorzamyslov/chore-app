/// C4 (conventions audit, docs/feedback/2026-08-06-conventions-audit.md):
/// the chore form's unsaved-changes guard. `design-language.md` interaction
/// rule 7 ("never lose user input") is the rule this fixes -- backing out
/// of a half-filled form used to silently discard it.
library;

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
    'pristine form: backing out pops immediately, no discard dialog',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsNothing,
      );
      // Back on the chores list: the form's save button is gone.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'dirty form: backing out shows the discard-confirm dialog only, and '
    "'Keep editing' keeps the entered value",
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Wash dishes');
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.discard.keepEditing'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('chore_form.discard.keepEditing'),
      );
      await tester.pumpAndSettle();

      // Still on the form, with the typed title intact.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsOneWidget);
      expect(find.text('Wash dishes'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'dirty form: confirming Discard pops the form and loses the value',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('chore_form.title'), 'Wash dishes');
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);
      expect(find.text('Wash dishes'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'toggling repeat on and back off without changing anything else stays '
    'pristine (recurrence sub-fields only count while repeat is enabled)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsNothing,
      );
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);

      handle.dispose();
    },
  );
}
