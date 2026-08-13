/// [buildDigestPlans] tests. Integration-style per the project's testing
/// convention: real in-memory `AppDatabase` + real `ChoreService`, so the
/// `OccurrenceWithChore` rows fed in are the exact shape production
/// produces, rather than hand-built drift rows that could drift from it.
///
/// A drift stream is read here via `listen` + `pumpEventQueue()` (the same
/// technique `test/data/repositories/chore_repository_test.dart` uses),
/// never by bare-awaiting it.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/digest_plan_builder.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase database;
  late ChoreRepository chores;
  late ChoreService service;
  late String householdId;
  late DeviceSettings settings;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    chores = ChoreRepository(database);
    service = ChoreService(database: database, chores: chores);
    final household = await HouseholdRepository(
      database,
    ).createLocalHousehold('Me');
    householdId = household.id;
    settings = await SettingsRepository(database).ensureSettings();
  });

  tearDown(() => database.close());

  Future<List<OccurrenceWithChore>> pending() async {
    final rows = <List<OccurrenceWithChore>>[];
    final sub = chores.watchPendingOccurrences(householdId).listen(rows.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    return rows.last;
  }

  test('always returns exactly digestHorizonDays entries', () async {
    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, hasLength(digestHorizonDays));
  });

  test('an empty household is silent on every single day', () async {
    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, everyElement(isNull));
  });

  test('a daily chore fills the whole horizon with "1 due"', () async {
    await service.createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      recurrence: Recurrence.everyNDays(1),
    );

    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );

    expect(plans.every((plan) => plan != null), isTrue);
    expect(plans.first!.fireAt, DateTime(2026, 1, 5, 8));
    expect(plans.last!.fireAt, DateTime(2026, 1, 11, 8));
    for (final plan in plans) {
      expect(plan!.dueTodayCount, 1);
      expect(plan.overdueCount, 0);
    }
  });

  test('a one-off is due on its day and overdue on every day after', () async {
    await service.createChore(
      householdId: householdId,
      title: 'Call the plumber',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
    );

    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );

    expect(plans.first!.dueTodayCount, 1);
    expect(plans.first!.overdueCount, 0);
    expect(plans[1]!.dueTodayCount, 0);
    expect(plans[1]!.overdueCount, 1);
    expect(plans.last!.overdueCount, 1);
  });

  test('a disabled digest is null on every day', () async {
    await service.createChore(
      householdId: householdId,
      title: 'Water the plants',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      recurrence: Recurrence.everyNDays(1),
    );
    final settingsRepo = SettingsRepository(database);
    await settingsRepo.setDigestEnabled(enabled: false);
    final disabled = await settingsRepo.ensureSettings();

    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: disabled,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, everyElement(isNull));
  });

  test("a partner's fixed chore is invisible to my digest (T2.3)", () async {
    // `createLocalHousehold('Me')` in setUp already inserted an admin
    // member named 'Me' (see `HouseholdRepository.createLocalHousehold`), so
    // only the partner needs seeding here.
    final householdRepo = HouseholdRepository(database);
    final members = <Member>[];
    final sub = householdRepo.watchMembers(householdId).listen(members.addAll);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    final me = members.single;
    final partner = await householdRepo.addMember(
      householdId,
      name: 'Partner',
      color: 0xFF445566,
    );
    await service.createChore(
      householdId: householdId,
      title: "Partner's chore",
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.fixed,
      assigneeMemberIds: [partner.id],
    );
    await service.createChore(
      householdId: householdId,
      title: 'Shared chore',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
    );

    final rows = await pending();
    final mine = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: rows,
      recipientMemberId: me.id,
    );
    final theirs = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: rows,
      recipientMemberId: partner.id,
    );

    expect(mine.first!.dueTodayCount, 1, reason: 'the shared chore only');
    expect(theirs.first!.dueTodayCount, 2, reason: 'shared + their own');
  });
}
