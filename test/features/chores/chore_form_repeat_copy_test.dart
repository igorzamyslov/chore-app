import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget-level tests for field feedback G3 stage 1 (copy-level repeat-form
/// fixes, `docs/feedback/2026-08-01-field-feedback.md`):
/// - the unit chip pluralizes with the current interval (it's the only
///   place a unit noun renders next to the interval number, so it doubles
///   as the "composed reading" the feedback is about);
/// - the after-last-completion subtitle names the actual interval instead
///   of a generic example;
/// - a one-line hint appears whenever the monthly pattern (or an
///   empty-selection weekly pattern) silently derives from the start date.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder intervalField() => find.descendant(
    of: find.bySemanticsIdentifier('chore_form.repeat.interval'),
    matching: find.byType(TextField),
  );

  testChoreApp(
    'the unit chip reads singular at interval 1 and pluralizes at interval '
    '2 ("2 Months")',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.month'),
      );
      await tester.pumpAndSettle();

      // Default interval is 1: singular.
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Months'), findsNothing);

      // Typing 2 into the interval field re-pluralizes the same chip live,
      // with no need to re-tap the unit.
      await tester.enterText(intervalField(), '2');
      await tester.pumpAndSettle();

      expect(find.text('Months'), findsOneWidget);
      expect(find.text('Month'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the after-last-completion subtitle names the actual current interval',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.day'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(intervalField(), '3');
      await tester.pumpAndSettle();

      expect(find.text('3 days after last done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'the pattern-follows-start-date hint shows for monthly and for weekly '
    'with no weekday picked, not for plain daily',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      const hint =
          'Follows the start date — change the start date to change the '
          'day.';

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();

      // Default unit is week with no weekday picked yet: derives from the
      // start date, so the hint shows.
      expect(find.text(hint), findsOneWidget);

      // Day unit: nothing derives from the start date, no hint.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.day'),
      );
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);

      // Month unit (schedule anchor, the default): always derives from the
      // start date, hint shows.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.month'),
      );
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);

      // Back to week, then pick an explicit weekday: the pattern is now
      // fully visible in the chips, so the hidden-dependency hint goes
      // away.
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.week'),
      );
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.2'),
      );
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);

      handle.dispose();
    },
  );
}
