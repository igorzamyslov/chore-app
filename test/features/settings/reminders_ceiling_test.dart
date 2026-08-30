/// The Settings ceiling sub-line (spec `docs/specs/notifications-n2.md`
/// §3.2, decision D4): factual, projection-only, shown only while more
/// chores want an individual reminder than the device can arm.
///
/// The copy is matched as literal English on purpose -- `testChoreApp` pumps
/// with no locale override, so the template ARB's text is what renders, and
/// a test reading the same `AppLocalizations` getter the widget reads would
/// pass whatever that getter returned.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 8, 30, 9);

  Future<void> seedReminderChores(AppDatabase database, int count) async {
    final household = await database.select(database.households).getSingle();
    final service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(today),
    );
    for (var i = 0; i < count; i++) {
      await service.createChore(
        householdId: household.id,
        title: 'Chore $i',
        // Inside reminderArmWindowDays (14) and still ahead of `today`'s
        // 09:00, so every one of these is a live candidate.
        startDate: PlainDate(2026, 8, 31),
        assignmentMode: AssignmentMode.anyone,
        reminderMinutes: defaultReminderMinutes,
      );
    }
  }

  testChoreApp('under the ceiling: no sub-line', today: today, (
    tester,
    database,
  ) async {
    final handle = tester.ensureSemantics();
    await seedReminderChores(database, 3);
    await tester.pumpAndSettle();
    await openSettingsTab(tester);

    expect(find.textContaining('stays in the daily summary'), findsNothing);
    expect(find.textContaining('stay in the daily summary'), findsNothing);

    handle.dispose();
  });

  testChoreApp(
    'over the ceiling: the sub-line names the overflow and the limit',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedReminderChores(database, reminderCeiling + 2);
      await tester.pumpAndSettle();
      await openSettingsTab(tester);

      // Derived, never the literal 33 (spec §3.1): the split must move as
      // one number when it moves at all.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('settings.digest.toggle'),
          matching: find.text(
            '2 chores stay in the daily summary — this device can hold '
            '$reminderCeiling reminders at once.',
          ),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'digest off: no sub-line, because the claim would be false',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedReminderChores(database, reminderCeiling + 2);
      await tester.pumpAndSettle();
      await openSettingsTab(tester);

      // Guard against `findsNothing` below passing for the wrong reason:
      // the sub-line has to be there BEFORE the toggle is flipped.
      expect(find.textContaining('stay in the daily summary'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('settings.digest.toggle'));
      await tester.pumpAndSettle();

      // Spec §2.5: with the digest off, coverage is reminders-only -- the
      // losers are NOT in a daily summary, because there isn't one.
      expect(find.textContaining('stay in the daily summary'), findsNothing);

      handle.dispose();
    },
  );
}
