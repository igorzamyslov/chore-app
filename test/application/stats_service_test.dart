import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _household(
  AppDatabase db,
  String id, {
  required String createdAt,
}) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}

Future<void> _member(
  AppDatabase db,
  String id,
  String householdId, {
  required String createdAt,
  String? deletedAt,
}) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          householdId: householdId,
          name: id,
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: createdAt,
          updatedAt: createdAt,
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<void> _chore(
  AppDatabase db,
  String id,
  String householdId, {
  required String title,
  String? deletedAt,
}) async {
  await db
      .into(db.chores)
      .insert(
        ChoresCompanion.insert(
          id: id,
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<void> _done(
  AppDatabase db,
  String id,
  String choreId, {
  required String closedOn,
  String? completedBy,
}) async {
  await db
      .into(db.choreOccurrences)
      .insert(
        ChoreOccurrencesCompanion.insert(
          id: id,
          choreId: choreId,
          dueDate: PlainDate.parse(closedOn),
          status: const Value(OccurrenceStatus.done),
          completedBy: Value(completedBy),
          closedOn: Value(PlainDate.parse(closedOn)),
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
}

void main() {
  late AppDatabase db;

  StatsService serviceAt(DateTime now) => StatsService(
    database: db,
    stats: StatsRepository(db),
    clock: Clock.fixed(now),
  );

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('an old household gets the full 30-day window, unclamped', () async {
    await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
    final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

    expect(overview.windowStart, PlainDate(2026, 7, 13));
    expect(overview.windowEnd, PlainDate(2026, 8, 11));
    expect(overview.windowClampedToHouseholdStart, isFalse);
  });

  test(
    'a household younger than the window is clamped to its own start date',
    () async {
      await _household(db, 'hh', createdAt: '2026-08-09T10:00:00.000Z');
      final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

      expect(overview.windowStart, PlainDate(2026, 8, 9));
      expect(overview.windowClampedToHouseholdStart, isTrue);
    },
  );

  test(
    'a household whose created_at is in the future never inverts the window',
    () async {
      // Reachable in the field: a restored backup, a corrected device
      // clock, or a synced row written by a device running ahead. Before
      // the floor in StatsService, windowStart landed after windowEnd and
      // the aggregate matched nothing.
      await _household(db, 'hh', createdAt: '2026-09-20T10:00:00.000Z');
      final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

      expect(overview.windowStart, PlainDate(2026, 8, 11));
      expect(overview.windowEnd, PlainDate(2026, 8, 11));
      expect(
        overview.windowStart.isAfter(overview.windowEnd),
        isFalse,
        reason: 'the window must never invert',
      );
    },
  );

  test(
    'shares are in roster order, keep zero-count members, append a departed '
    'contributor, and put the unattributed bucket last',
    () async {
      await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
      // Roster (creation) order is anna, ben, cara, dan. The counts below
      // are chosen so that roster order and count-descending order DISAGREE
      // on every position: by count the list would read ben(5), cara(2),
      // anna(1), <unattributed>(1), dan(0). If anyone ever "improves" this
      // into a leaderboard, the order assertion has to fail -- equal counts
      // would let a count sort masquerade as roster order (spec §0 rule 2).
      await _member(db, 'anna', 'hh', createdAt: '2026-01-01T10:00:00.000Z');
      await _member(db, 'ben', 'hh', createdAt: '2026-01-02T10:00:00.000Z');
      await _member(
        db,
        'cara',
        'hh',
        createdAt: '2026-01-03T10:00:00.000Z',
        deletedAt: '2026-08-01T10:00:00.000Z',
      );
      await _member(db, 'dan', 'hh', createdAt: '2026-01-04T10:00:00.000Z');
      await _chore(db, 'c1', 'hh', title: 'Bathroom');

      await _done(db, 'o1', 'c1', closedOn: '2026-08-01', completedBy: 'anna');
      for (var i = 0; i < 5; i++) {
        await _done(
          db,
          'ben-$i',
          'c1',
          closedOn: '2026-08-02',
          completedBy: 'ben',
        );
      }
      await _done(db, 'o2', 'c1', closedOn: '2026-08-02', completedBy: 'cara');
      await _done(db, 'o3', 'c1', closedOn: '2026-08-03', completedBy: 'cara');
      await _done(db, 'o4', 'c1', closedOn: '2026-08-03');

      final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

      expect(overview.shares.map((s) => s.member?.id).toList(), [
        'anna',
        'ben',
        'cara',
        'dan',
        null,
      ]);
      expect(overview.shares.map((s) => s.doneCount).toList(), [
        1,
        5,
        2,
        0,
        1,
      ]);
      expect(overview.totalDone, 9);
    },
  );

  test(
    'a departed member with no contributions in the window is dropped, '
    'while a current member with none is kept',
    () async {
      await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
      await _member(db, 'anna', 'hh', createdAt: '2026-01-01T10:00:00.000Z');
      await _member(
        db,
        'ghost',
        'hh',
        createdAt: '2026-01-02T10:00:00.000Z',
        deletedAt: '2026-08-01T10:00:00.000Z',
      );

      final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

      expect(overview.shares.map((s) => s.member?.id).toList(), ['anna']);
      expect(overview.totalDone, 0);
    },
  );

  test('chores split into active and deleted, each alphabetical', () async {
    await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
    await _chore(db, 'a', 'hh', title: 'Bathroom');
    await _chore(
      db,
      'b',
      'hh',
      title: 'Attic',
      deletedAt: '2026-08-05T00:00:00.000Z',
    );
    await _chore(db, 'c', 'hh', title: 'Garden');

    await _done(db, 'o1', 'a', closedOn: '2026-08-01');
    await _done(db, 'o2', 'b', closedOn: '2026-05-01');
    await _done(db, 'o3', 'c', closedOn: '2026-08-02');

    final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

    expect(overview.activeChores.map((r) => r.chore.title), [
      'Bathroom',
      'Garden',
    ]);
    expect(overview.deletedChores.map((r) => r.chore.title), ['Attic']);
  });
}
