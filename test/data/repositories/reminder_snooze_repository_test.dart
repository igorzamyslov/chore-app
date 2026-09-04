/// [ReminderSnoozeRepository] tests (spec
/// `docs/specs/notifications-n2.md` §4.2).
///
/// Real in-memory `AppDatabase`, per this project's convention, because the
/// two behaviours worth testing here are both database ones: the
/// insert-or-replace that makes a double tap on Snooze idempotent, and the
/// garbage collection that keeps the table from growing.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/reminder_snooze_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late ReminderSnoozeRepository repo;

  /// Seeds a household, a chore and one PENDING occurrence with id
  /// [occurrenceId].
  ///
  /// Written directly against the tables rather than through
  /// `ChoreService`, because the occurrence ids have to be nameable: every
  /// assertion below is about which occurrence a row belongs to.
  Future<void> seedOccurrence(String occurrenceId) async {
    await db
        .into(db.chores)
        .insert(
          ChoresCompanion.insert(
            id: 'chore-$occurrenceId',
            householdId: 'h1',
            title: 'Bins',
            startDate: PlainDate(2026, 8, 30),
            assignmentMode: AssignmentMode.anyone,
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
    await db
        .into(db.choreOccurrences)
        .insert(
          ChoreOccurrencesCompanion.insert(
            id: occurrenceId,
            choreId: 'chore-$occurrenceId',
            dueDate: PlainDate(2026, 8, 30),
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReminderSnoozeRepository(
      db,
      nowUtc: () => DateTime.utc(2026, 8, 30),
    );
    await db
        .into(db.households)
        .insert(
          HouseholdsCompanion.insert(
            id: 'h1',
            name: 'H',
            createdAt: 't0',
            updatedAt: 't0',
          ),
        );
    for (final id in ['o1', 'o2', 'o3']) {
      await seedOccurrence(id);
    }
  });

  tearDown(() => db.close());

  test(
    'upsertSnooze writes a row, and a second call for the same occurrence '
    'REPLACES it rather than throwing (idempotent double tap, spec '
    'docs/specs/notifications-n2.md §13.2)',
    () async {
      await repo.upsertSnooze(
        occurrenceId: 'o1',
        snoozedUntilUtc: DateTime.utc(2026, 8, 31, 18),
      );
      await repo.upsertSnooze(
        occurrenceId: 'o1',
        snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
      );
      final rows = await db.select(db.reminderSnoozes).get();
      expect(rows, hasLength(1));
      expect(rows.single.snoozedUntil, '2026-09-01T18:00:00.000Z');
    },
  );

  test('activeSnoozes returns a map keyed by occurrence id, with UTC '
      'DateTimes', () async {
    await repo.upsertSnooze(
      occurrenceId: 'o1',
      snoozedUntilUtc: DateTime.utc(2026, 8, 31, 18),
    );
    expect(await repo.activeSnoozes(), {'o1': DateTime.utc(2026, 8, 31, 18)});
  });

  test(
    'upsertSnooze stores a LOCAL DateTime as its UTC instant -- every other '
    'timestamp column in this schema is UTC and the planner converts back',
    () async {
      final local = DateTime.utc(2026, 8, 31, 18).toLocal();
      await repo.upsertSnooze(occurrenceId: 'o1', snoozedUntilUtc: local);
      expect(await repo.activeSnoozes(), {'o1': DateTime.utc(2026, 8, 31, 18)});
    },
  );

  test(
    'collectGarbage deletes rows whose occurrence is no longer pending AND '
    'rows whose snoozed_until has passed, and keeps the rest (spec §4.2 -- '
    'the table never grows)',
    () async {
      await repo.upsertSnooze(
        occurrenceId: 'o1', // pending, future -> kept
        snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
      );
      await repo.upsertSnooze(
        occurrenceId: 'o2', // pending, PAST -> deleted
        snoozedUntilUtc: DateTime.utc(2026, 8, 29, 18),
      );
      await repo.upsertSnooze(
        occurrenceId: 'o3', // future, but NOT pending -> deleted
        snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
      );
      await repo.collectGarbage(
        pendingOccurrenceIds: {'o1', 'o2'},
        nowUtc: DateTime.utc(2026, 8, 30, 12),
      );
      final rows = await db.select(db.reminderSnoozes).get();
      expect(rows.map((row) => row.occurrenceId), ['o1']);
    },
  );

  test(
    'collectGarbage with an EMPTY pending set clears the table -- the '
    'ordinary state after every chore is done, and the one an `isIn` '
    'against an empty list can silently get wrong',
    () async {
      await repo.upsertSnooze(
        occurrenceId: 'o1',
        snoozedUntilUtc: DateTime.utc(2026, 9, 1, 18),
      );
      await repo.collectGarbage(
        pendingOccurrenceIds: const {},
        nowUtc: DateTime.utc(2026, 8, 30, 12),
      );
      expect(await db.select(db.reminderSnoozes).get(), isEmpty);
    },
  );
}
