import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds a household row and returns its id.
Future<String> _household(AppDatabase db, String id) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  return id;
}

Future<String> _member(
  AppDatabase db,
  String id,
  String householdId, {
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
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deletedAt),
        ),
      );
  return id;
}

Future<String> _chore(
  AppDatabase db,
  String id,
  String householdId, {
  String title = 'Chore',
  String? deletedAt,
  String? pausedAt,
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
          pausedAt: Value(pausedAt),
        ),
      );
  return id;
}

Future<void> _occurrence(
  AppDatabase db,
  String id,
  String choreId, {
  required OccurrenceStatus status,
  String? closedOn,
  String? completedBy,
  String updatedAt = '2026-01-01T00:00:00.000Z',
}) async {
  await db
      .into(db.choreOccurrences)
      .insert(
        ChoreOccurrencesCompanion.insert(
          id: id,
          choreId: choreId,
          dueDate: PlainDate(2026, 1, 1),
          status: Value(status),
          completedBy: Value(completedBy),
          closedOn: Value(closedOn == null ? null : PlainDate.parse(closedOn)),
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: updatedAt,
        ),
      );
}

void main() {
  late AppDatabase db;
  late StatsRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = StatsRepository(db);
  });

  tearDown(() => db.close());

  test('doneCountsByMember counts only done rows, inclusive at both window '
      'edges, and ignores skipped/missed/pending', () async {
    final hh = await _household(db, 'hh');
    final anna = await _member(db, 'anna', hh);
    final chore = await _chore(db, 'c1', hh);

    await _occurrence(
      db,
      'o1',
      chore,
      status: OccurrenceStatus.done,
      closedOn: '2026-07-13',
      completedBy: anna,
    ); // window start
    await _occurrence(
      db,
      'o2',
      chore,
      status: OccurrenceStatus.done,
      closedOn: '2026-08-11',
      completedBy: anna,
    ); // window end
    await _occurrence(
      db,
      'o3',
      chore,
      status: OccurrenceStatus.done,
      closedOn: '2026-07-12',
      completedBy: anna,
    ); // before window
    await _occurrence(
      db,
      'o4',
      chore,
      status: OccurrenceStatus.skipped,
      closedOn: '2026-08-01',
      completedBy: anna,
    );
    // Both the skipped and the missed row are attributed to Anna and sit
    // INSIDE the window, so if either status ever leaked into the
    // aggregate it would land on her count rather than on some separate
    // bucket -- the assertion below then fails loudly at 3 or 4 instead
    // of quietly counting something else (spec §0 rule 1).
    await _occurrence(
      db,
      'o5',
      chore,
      status: OccurrenceStatus.missed,
      closedOn: '2026-08-02',
      completedBy: anna,
    );
    await _occurrence(db, 'o6', chore, status: OccurrenceStatus.pending);

    final counts = await repo.doneCountsByMember(
      hh,
      windowStart: PlainDate(2026, 7, 13),
      windowEnd: PlainDate(2026, 8, 11),
    );

    expect(counts, hasLength(1));
    expect(counts.single.memberId, 'anna');
    expect(counts.single.doneCount, 2);
  });

  test('doneCountsByMember buckets a NULL completed_by separately and never '
      'leaks another household', () async {
    final hh = await _household(db, 'hh');
    final other = await _household(db, 'other');
    final anna = await _member(db, 'anna', hh);
    final chore = await _chore(db, 'c1', hh);
    final otherChore = await _chore(db, 'c2', other);

    await _occurrence(
      db,
      'o1',
      chore,
      status: OccurrenceStatus.done,
      closedOn: '2026-08-01',
      completedBy: anna,
    );
    await _occurrence(
      db,
      'o2',
      chore,
      status: OccurrenceStatus.done,
      closedOn: '2026-08-02',
    );
    await _occurrence(
      db,
      'o3',
      otherChore,
      status: OccurrenceStatus.done,
      closedOn: '2026-08-03',
    );

    final counts = await repo.doneCountsByMember(
      hh,
      windowStart: PlainDate(2026, 7, 13),
      windowEnd: PlainDate(2026, 8, 11),
    );

    expect(counts.map((c) => c.memberId), containsAll(<String?>[null, 'anna']));
    expect(counts.length, 2);
    expect(counts.firstWhere((c) => c.memberId == null).doneCount, 1);
  });

  test(
    'choreRollups includes deleted and paused chores, excludes chores with '
    'no done history, and reports all-time count plus last done date',
    () async {
      final hh = await _household(db, 'hh');
      await _chore(db, 'live', hh, title: 'Bathroom');
      await _chore(
        db,
        'gone',
        hh,
        title: 'Attic',
        deletedAt: '2026-08-05T00:00:00.000Z',
      );
      await _chore(
        db,
        'rest',
        hh,
        title: 'Garden',
        pausedAt: '2026-08-05T00:00:00.000Z',
      );
      await _chore(db, 'never', hh, title: 'Zebra');

      await _occurrence(
        db,
        'o1',
        'live',
        status: OccurrenceStatus.done,
        closedOn: '2026-06-01',
      );
      await _occurrence(
        db,
        'o2',
        'live',
        status: OccurrenceStatus.done,
        closedOn: '2026-08-01',
      );
      await _occurrence(
        db,
        'o3',
        'gone',
        status: OccurrenceStatus.done,
        closedOn: '2026-05-01',
      );
      await _occurrence(
        db,
        'o4',
        'rest',
        status: OccurrenceStatus.done,
        closedOn: '2026-07-01',
      );
      await _occurrence(db, 'o5', 'never', status: OccurrenceStatus.pending);

      final rollups = await repo.choreRollups(hh);

      expect(rollups.map((r) => r.chore.title), [
        'Attic',
        'Bathroom',
        'Garden',
      ]);
      final bathroom = rollups.firstWhere((r) => r.chore.id == 'live');
      expect(bathroom.doneAllTime, 2);
      expect(bathroom.lastDoneOn, PlainDate(2026, 8, 1));
    },
  );

  test(
    'recentCompletions returns newest first, resolves a soft-deleted member, '
    'and honours the limit; doneCountForChore reports the untruncated total',
    () async {
      final hh = await _household(db, 'hh');
      final ghost = await _member(
        db,
        'ghost',
        hh,
        deletedAt: '2026-08-06T00:00:00.000Z',
      );
      await _chore(db, 'c1', hh);

      await _occurrence(
        db,
        'o1',
        'c1',
        status: OccurrenceStatus.done,
        closedOn: '2026-08-01',
        completedBy: ghost,
      );
      await _occurrence(
        db,
        'o2',
        'c1',
        status: OccurrenceStatus.done,
        closedOn: '2026-08-03',
        completedBy: ghost,
      );
      await _occurrence(
        db,
        'o3',
        'c1',
        status: OccurrenceStatus.skipped,
        closedOn: '2026-08-04',
      );

      expect(await repo.doneCountForChore('c1'), 2);

      final recent = await repo.recentCompletions('c1', limit: 1);
      expect(recent, hasLength(1));
      expect(recent.single.occurrence.id, 'o2');
      expect(recent.single.completedByMember?.name, 'ghost');
    },
  );
}
