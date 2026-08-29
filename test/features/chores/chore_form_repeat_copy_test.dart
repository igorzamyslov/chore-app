import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget-level tests for the chore form's repeat copy.
///
/// Field feedback G3 stage 1 fixed the wording; G-2 (stage 2,
/// `docs/plans/2026-08-18-repeat-form-sentence.md`) replaced the five
/// separate controls with one fill-in-the-blank sentence. What survives from
/// stage 1 and must keep working:
/// - the unit chip pluralizes live with the interval the user types;
/// - the after-last-completion card names the actual interval, not a
///   generic example.
///
/// What stage 2 changes: nothing in the pattern derives silently from the
/// start date any more, so the "Follows the start date" caption is retired
/// and the sentence names the day directly.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder intervalField() => find.descendant(
    of: find.bySemanticsIdentifier('chore_form.repeat.interval'),
    matching: find.byType(TextField),
  );

  Future<void> openRepeatForm(WidgetTester tester) async {
    await tester.tap(find.bySemanticsIdentifier('chores.add'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
    await tester.pumpAndSettle();
  }

  Future<void> pickUnit(WidgetTester tester, String unit) async {
    await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.unit'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('chore_form.repeat.unit.$unit'),
    );
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'the unit hole reads singular at interval 1 and pluralizes at interval '
    '2 ("2 Months"), with no re-tap',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openRepeatForm(tester);
      await pickUnit(tester, 'month');

      // Default interval is 1: singular.
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Months'), findsNothing);

      // Typing 2 into the interval hole re-pluralizes the unit hole beside
      // it live. The two are separate widgets in one Wrap, so nothing but
      // the shared rebuild connects them -- which is exactly what could
      // silently stop working.
      await tester.enterText(intervalField(), '2');
      await tester.pumpAndSettle();

      expect(find.text('Months'), findsOneWidget);
      expect(find.text('Month'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the after-last-completion card names the actual current interval',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openRepeatForm(tester);
      await pickUnit(tester, 'day');
      await tester.enterText(intervalField(), '3');
      await tester.pumpAndSettle();

      expect(find.text('3 days after last done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'nothing in the pattern follows the start date any more: the caption is '
    'gone and the sentence names the day itself',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      const retiredHint =
          'Follows the start date — change the start date to change the '
          'day.';

      await openRepeatForm(tester);

      // Week, the default. Stage 1 showed the caption here because an empty
      // weekday set silently derived the day from the start date; stage 2
      // seeds the start date's weekday into the chips instead, so the
      // pattern is visible rather than hinted at.
      expect(find.text(retiredHint), findsNothing);
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.5'),
        findsOneWidget,
      );

      // Month. Stage 1 always showed the caption here, because the day was
      // read off the start date and there was nowhere to see it.
      await pickUnit(tester, 'month');
      expect(find.text(retiredHint), findsNothing);
      // The day is now a hole in the sentence, showing the concrete day.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
          matching: find.text('24th'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the monthly mode options name the MODE, not the derived day',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openRepeatForm(tester);
      await pickUnit(tester, 'month');

      expect(find.text('A day of the month'), findsOneWidget);
      expect(find.text('A weekday'), findsOneWidget);
      // The derived labels are retired: the concrete day lives in the
      // sentence's own chip now, so naming it here too would be two places
      // to keep in step.
      expect(find.text('On the 24th'), findsNothing);
      expect(find.text('On the 4th Friday'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the anchor sits below a hairline under "Counting from"',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await openRepeatForm(tester);

      expect(find.text('COUNTING FROM'), findsOneWidget);
      final headerAt = tester.getTopLeft(find.text('COUNTING FROM')).dy;
      final anchorAt = tester
          .getTopLeft(
            find.bySemanticsIdentifier('chore_form.repeat.anchor.schedule'),
          )
          .dy;
      final sentenceAt = tester
          .getTopLeft(find.bySemanticsIdentifier('chore_form.repeat.unit'))
          .dy;
      expect(sentenceAt, lessThan(headerAt));
      expect(headerAt, lessThan(anchorAt));

      handle.dispose();
    },
  );
}
