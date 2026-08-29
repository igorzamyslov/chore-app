/// Widget tests for `RepeatSentence`, the chore form's fill-in-the-blank
/// repeat sentence (G-2, `docs/plans/2026-08-18-repeat-form-sentence.md`
/// Task 5).
///
/// Driven through the real form via `testChoreApp` rather than a bare pump:
/// the holes only mean anything against the form's state, and a hand-rolled
/// `ProviderScope` pump that closes the database in `tearDown` hangs rather
/// than fails, taking the whole suite with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_utils/pump_app.dart';

void main() {
  // A Friday, and the 4th Friday of July 2026.
  final today = DateTime(2026, 7, 24, 9);

  /// Opens the new-chore form with the repeat toggle already on.
  Future<void> openRepeatForm(WidgetTester tester) async {
    await tester.tap(find.bySemanticsIdentifier('chores.add'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
    await tester.pumpAndSettle();
  }

  /// Picks [unit] through the sentence's unit hole, which is a menu now:
  /// tap the chip, then tap the entry.
  Future<void> pickUnit(WidgetTester tester, String unit) async {
    await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.unit'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('chore_form.repeat.unit.$unit'),
    );
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'the unit hole is a menu: its entries do not exist until it is tapped',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openRepeatForm(tester);

      expect(
        find.bySemanticsIdentifier('chore_form.repeat.unit'),
        findsOneWidget,
      );
      // The three unit ids are E2E API and still exist -- but inside a menu
      // that has not been opened, so three Maestro flows now need two taps.
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.unit.day'),
        findsNothing,
      );

      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.unit'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.unit.day'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.unit.week'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.unit.month'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'controls that do not apply to the chosen unit do not EXIST, they are '
    'not merely disabled',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openRepeatForm(tester);

      // Week is the default: weekday chips, no monthly holes.
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
        findsNothing,
      );

      await pickUnit(tester, 'month');

      // The swap is total in both directions.
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
        findsNothing,
      );

      await pickUnit(tester, 'day');

      // A day rule has no pattern at all beyond the interval.
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.1'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
        findsNothing,
      );
      // But the interval and unit holes are in every shape.
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.interval'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.unit'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the sentence renders its literal words as Text, in order, around the '
    'holes',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openRepeatForm(tester);
      await pickUnit(tester, 'day');

      // 'Repeat every {interval} {unit}' -- the two literal words, split on
      // whitespace so the Wrap can reflow them, with the holes between.
      expect(find.text('Repeat'), findsOneWidget);
      expect(find.text('every'), findsOneWidget);

      // In document order: the words come before both holes.
      final repeatAt = tester.getTopLeft(find.text('Repeat')).dx;
      final everyAt = tester.getTopLeft(find.text('every')).dx;
      final intervalAt = tester
          .getTopLeft(find.bySemanticsIdentifier('chore_form.repeat.interval'))
          .dx;
      final unitAt = tester
          .getTopLeft(find.bySemanticsIdentifier('chore_form.repeat.unit'))
          .dx;
      expect(repeatAt, lessThan(everyAt));
      expect(everyAt, lessThan(intervalAt));
      expect(intervalAt, lessThan(unitAt));

      // No sentinel ever reaches the screen.
      expect(find.textContaining('﷐'), findsNothing);
      expect(find.textContaining('﷑'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'the monthly mode swaps the day hole for the ordinal + weekday holes',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openRepeatForm(tester);
      await pickUnit(tester, 'month');

      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_ordinal'),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.nth_weekday',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_day'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_ordinal'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.repeat.monthly_weekday'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'every hole is at least a 40px tap target, the interval field included',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openRepeatForm(tester);
      await pickUnit(tester, 'month');

      for (final id in [
        'chore_form.repeat.interval',
        'chore_form.repeat.unit',
        'chore_form.repeat.monthly_day',
      ]) {
        final size = tester.getSize(find.bySemanticsIdentifier(id));
        expect(
          size.height,
          greaterThanOrEqualTo(40),
          reason: '$id is too short to hit',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(40),
          reason: '$id is too narrow to hit',
        );
      }

      handle.dispose();
    },
  );
}
