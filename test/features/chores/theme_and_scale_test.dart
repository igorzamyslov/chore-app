import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'both themes render the list screen without exceptions', // smoke test
    today: today,
    (tester, database) async {
      // Light is already exercised by every other test in this suite; this
      // additionally forces dark, which `ThemeMode.system` (this app's only
      // mode) then follows via the platform brightness.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Chores'),
        ),
        findsOneWidget,
      );
    },
  );

  testChoreApp(
    'text scale 2.0 renders the list and form without overflow exceptions',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      await service.createChore(
        householdId: householdId,
        title: 'A chore with a reasonably long title',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );

      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('A chore with a reasonably long title'), findsOneWidget);

      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsIdentifier('chore_form.save'), findsOneWidget);

      // G-2: the repeat block is now one sentence whose words and chips
      // flow in a Wrap, and it is by far the widest thing on this form.
      // Opening the form without turning the toggle on never renders it at
      // all, which made this gate vacuous for the whole redesign.
      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.toggle'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Every unit is a different sentence shape with a different number of
      // holes; the month + weekday shape is the longest of the four.
      for (final unit in ['day', 'month', 'week']) {
        await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.unit'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.bySemanticsIdentifier('chore_form.repeat.unit.$unit'),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the repeat sentence overflowed for the $unit unit at '
              'text scale 2.0 -- fix the chip constraint or the Wrap, never '
              'the tap-target size',
        );
      }

      await tester.tap(find.bySemanticsIdentifier('chore_form.repeat.unit'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.repeat.unit.month'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          'chore_form.repeat.monthly_mode.nth_weekday',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      handle.dispose();
    },
  );
}
