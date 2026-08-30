/// `ChoreService`'s pass-through of `chores.reminder_minutes` (spec
/// `docs/specs/notifications-n2.md` §2.1, decision D1).
///
/// The chore form calls the service, never the repository directly
/// (`docs/specs/occurrence-lifecycle.md` §2), so without this pass-through
/// the form has nowhere to write.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late ChoreService service;
  late String householdId;
  final now = DateTime(2026, 8, 30, 9);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final household = await HouseholdRepository(
      database,
    ).createLocalHousehold('Me');
    householdId = household.id;
    service = ChoreService(
      database: database,
      chores: ChoreRepository(database),
      clock: Clock.fixed(now),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<int?> storedReminder(String choreId) async {
    final row = await (database.select(
      database.chores,
    )..where((tbl) => tbl.id.equals(choreId))).getSingle();
    return row.reminderMinutes;
  }

  test('createChore defaults reminderMinutes to null', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
    );

    expect(await storedReminder(chore.id), isNull);
  });

  test('createChore persists a given reminderMinutes', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
      reminderMinutes: 1080,
    );

    expect(await storedReminder(chore.id), 1080);
  });

  test(
    'updateChore with Value.absent leaves the stored reminder alone',
    () async {
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 9, 1),
        assignmentMode: AssignmentMode.anyone,
        reminderMinutes: 1080,
      );

      await service.updateChore(chore.id, title: 'Bins out');

      expect(await storedReminder(chore.id), 1080);
    },
  );

  test('updateChore with Value(null) clears the reminder', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
      reminderMinutes: 1080,
    );

    await service.updateChore(chore.id, reminderMinutes: const Value(null));

    // Turning the switch off writes NULL -- there is no separate enabled
    // flag to leave behind (D1).
    expect(await storedReminder(chore.id), isNull);
  });

  test('updateChore sets a new reminder time', () async {
    final chore = await service.createChore(
      householdId: householdId,
      title: 'Bins',
      startDate: PlainDate(2026, 9, 1),
      assignmentMode: AssignmentMode.anyone,
    );

    await service.updateChore(chore.id, reminderMinutes: const Value(1230));

    expect(await storedReminder(chore.id), 1230);
  });

  test(
    'changing only the reminder leaves the pending occurrence untouched',
    () async {
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Bins',
        startDate: PlainDate(2026, 9, 1),
        assignmentMode: AssignmentMode.anyone,
      );
      final before = await database
          .select(database.choreOccurrences)
          .getSingle();

      await service.updateChore(chore.id, reminderMinutes: const Value(1230));

      // A reminder time is a NOTIFICATION fact, not a schedule fact: it
      // must never join the recurrence/start-date comparison that
      // regenerates the occurrence (docs/specs/occurrence-lifecycle.md §2).
      // This is the same distinction D5 draws for snooze.
      final after = await database
          .select(database.choreOccurrences)
          .getSingle();
      expect(after.id, before.id);
      expect(after.dueDate, before.dueDate);
      expect(after.assignedMemberId, before.assignedMemberId);
    },
  );
}
