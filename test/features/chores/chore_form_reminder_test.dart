/// The chore form's per-chore reminder row, end to end (spec
/// `docs/specs/notifications-n2.md` §2.1 / AC1): default off, the 18:00
/// pre-fill, load on edit, clearing to NULL, and the unsaved-changes guard.
///
/// Nothing here asserts a RENDERED time. `flutter test` pumps with no locale
/// override and CI resolves a 12-hour locale, so `defaultReminderMinutes`
/// renders "6:00 PM", not "18:00"; persistence is asserted against the
/// database instead.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/features/chores/chore_form/reminder_row.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 8, 30, 9);

  ChoreService serviceFor(AppDatabase database) => ChoreService(
    database: database,
    chores: ChoreRepository(database),
    clock: Clock.fixed(today),
  );

  Future<int?> storedReminder(AppDatabase database, String choreId) async {
    final row = await (database.select(
      database.chores,
    )..where((tbl) => tbl.id.equals(choreId))).getSingle();
    return row.reminderMinutes;
  }

  Finder titleField() => find.descendant(
    of: find.bySemanticsIdentifier('chore_form.title'),
    matching: find.byType(TextField),
  );

  Future<void> openEditForm(WidgetTester tester, String choreId) async {
    await tester.tap(
      find.bySemanticsIdentifier('chores.occurrence.$choreId.menu'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
    await tester.pumpAndSettle();
  }

  testChoreApp(
    'new chore: reminder off by default, saving writes NULL, and the '
    'pinned Save stays reachable',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('chore_form.reminder.time'),
        findsNothing,
      );

      await tester.enterText(titleField(), 'Bins');
      // The Save button lives in the Scaffold's bottomNavigationBar (C15);
      // adding a row to the BODY must not have moved it into the list.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await database.select(database.chores).getSingle();
      expect(chore.reminderMinutes, isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'new chore: turning the reminder on reveals the time card and saves '
    'the 18:00 default',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(titleField(), 'Bins');
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.reminder.time'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await database.select(database.chores).getSingle();
      expect(chore.reminderMinutes, defaultReminderMinutes);

      handle.dispose();
    },
  );

  testChoreApp(
    'new chore: a time picked through the row is what gets saved',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.enterText(titleField(), 'Bins');
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      // Drives the row's own callback rather than Material's time picker:
      // no test in this repo opens `showTimePicker` (the digest time row's
      // tests assert the row and the persisted value only), and inventing
      // a dial/input-field driving technique here would test Flutter, not
      // this form. The picker itself is covered by the E2E flow.
      tester
          .widget<ChoreFormReminderRow>(find.byType(ChoreFormReminderRow))
          .onChanged(7 * 60 + 30);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      final chore = await database.select(database.chores).getSingle();
      expect(chore.reminderMinutes, 450);

      handle.dispose();
    },
  );

  testChoreApp(
    'edit: an existing reminder loads on, and turning it off saves NULL',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore = await serviceFor(database).createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 8, 30),
        assignmentMode: AssignmentMode.anyone,
        reminderMinutes: defaultReminderMinutes,
      );
      await tester.pumpAndSettle();

      await openEditForm(tester, chore.id);

      expect(
        find.bySemanticsIdentifier('chore_form.reminder.time'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      expect(await storedReminder(database, chore.id), isNull);

      handle.dispose();
    },
  );

  testChoreApp(
    'edit: changing only the reminder does not touch the pending occurrence',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore = await serviceFor(database).createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 8, 30),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();
      final before = await database
          .select(database.choreOccurrences)
          .getSingle();

      await openEditForm(tester, chore.id);
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      // Belt to the guard: the save must actually have written the
      // reminder, or the occurrence assertions below would hold for the
      // trivial reason that nothing happened at all.
      expect(
        await storedReminder(database, chore.id),
        defaultReminderMinutes,
      );

      // A reminder time is a notification fact, not a schedule fact: it
      // must not regenerate the occurrence the way a recurrence or
      // start-date change does (docs/specs/occurrence-lifecycle.md §2).
      final after = await database
          .select(database.choreOccurrences)
          .getSingle();
      expect(after.id, before.id);
      expect(after.dueDate, before.dueDate);
      expect(after.assignedMemberId, before.assignedMemberId);

      handle.dispose();
    },
  );

  testChoreApp(
    'dirty guard: toggling the reminder on and backing out raises the '
    'discard dialog',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore = await serviceFor(database).createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 8, 30),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await openEditForm(tester, chore.id);

      // Guard against this passing for the wrong reason: an edit form that
      // arrived already dirty would raise the dialog no matter what the
      // toggle did.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsNothing,
      );

      await openEditForm(tester, chore.id);
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'dirty guard: toggling the reminder on and back off is pristine again',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('chores.add'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      );
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      // D1 paying off a second time: one nullable scalar returns to null,
      // so no extra bookkeeping is needed to read pristine again.
      expect(
        find.bySemanticsIdentifier('chore_form.discard.confirm'),
        findsNothing,
      );
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);

      handle.dispose();
    },
  );
}
