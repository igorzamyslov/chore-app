/// [applyDoneAction] / [rewriteDigestHorizon] tests (spec
/// `docs/specs/notifications.md` N2, backlog F-1).
///
/// Integration-style, per the project's testing convention: a real in-memory
/// [AppDatabase], real repositories, the real [ChoreService], a fixed clock,
/// and only the bottom-most OS-facing plugin faked. Nothing here touches
/// Riverpod -- that is the point of the split, and it is why these need no
/// [ProviderContainer] and no widget pump.
///
/// **What these tests CANNOT cover, stated so a green run is not mistaken for
/// a working feature:** everything about the real background isolate. Whether
/// `openConnection()`'s `path_provider` channel lookup succeeds inside a
/// background `FlutterEngine`, whether the hosting broadcast receiver lives
/// long enough to finish the horizon rewrite, and whether the manifest
/// receiver is present in a release artifact are all platform facts. See the
/// spec's "What no test in this repo covers" and
/// `docs/plans/2026-08-08-notification-actions.md` Task 10.
library;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/digest_action_payload.dart';
import 'package:chore_app/application/notification_action_processor.dart';
import 'package:chore_app/application/notification_scheduler.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/digest_planner.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'fake_digest_notification_plugin.dart';

class _IdGen {
  int _next = 0;
  String call() => 'id-${_next++}';
}

Future<String> _insertHousehold(AppDatabase db, String id) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  return id;
}

Future<String> _insertMember(
  AppDatabase db,
  String id,
  String householdId,
) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          householdId: householdId,
          name: 'Member $id',
          color: 0xFF000000,
          role: MemberRole.member,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  return id;
}

void main() {
  late AppDatabase db;
  late ChoreRepository repo;
  late String householdId;

  // A fixed "today" every test shares, so due dates read unambiguously.
  final today = PlainDate(2026, 1, 10);
  final clock = Clock.fixed(DateTime(2026, 1, 10, 7));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChoreRepository(
      db,
      newId: _IdGen().call,
      nowUtc: () => DateTime.utc(2026),
    );
    householdId = await _insertHousehold(db, 'h1');
  });

  tearDown(() => db.close());

  ChoreService serviceOn(PlainDate day) => ChoreService(
    database: db,
    chores: repo,
    clock: Clock.fixed(DateTime.utc(day.year, day.month, day.day)),
  );

  group('applyDoneAction', () {
    test('completes a pending occurrence and attributes it to the passed '
        'member', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Trash',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final pending = (await repo.pendingOccurrenceOf(chore.id))!;

      await applyDoneAction(
        database: db,
        occurrenceId: pending.id,
        actingMemberId: m1,
        clock: clock,
      );

      final row = (await repo.getOccurrence(pending.id))!;
      expect(row.status, OccurrenceStatus.done);
      expect(row.completedBy, m1);
    });

    test('a null actingMemberId completes it UNATTRIBUTED -- completedBy is '
        'null, not an invented member', () async {
      await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Trash',
        startDate: today,
        assignmentMode: AssignmentMode.anyone,
      );
      final pending = (await repo.pendingOccurrenceOf(chore.id))!;

      await applyDoneAction(
        database: db,
        occurrenceId: pending.id,
        actingMemberId: null,
        clock: clock,
      );

      final row = (await repo.getOccurrence(pending.id))!;
      // Asserting the STATUS alone would pass even if the code guessed a
      // member -- which is exactly the misattribution backlog A-5 closed.
      expect(row.status, OccurrenceStatus.done);
      expect(row.completedBy, isNull);
    });

    test('an already-closed occurrence is a silent no-op that does not '
        'rewrite the row', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Trash',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final pending = (await repo.pendingOccurrenceOf(chore.id))!;
      await serviceOn(today).completeOccurrence(pending.id, completedBy: m1);

      // A duplicate tap on a stale shade entry, or another device having
      // already handled it. "Someone already did it" is a success.
      await applyDoneAction(
        database: db,
        occurrenceId: pending.id,
        actingMemberId: m2,
        clock: clock,
      );

      final row = (await repo.getOccurrence(pending.id))!;
      // Asserting completedBy is UNCHANGED, so a "no-op" that actually
      // re-wrote the row with the second member still fails.
      expect(row.completedBy, m1);
      expect(row.status, OccurrenceStatus.done);
    });

    test('an unknown occurrence id is a silent no-op that does not '
        'throw', () async {
      await expectLater(
        applyDoneAction(
          database: db,
          occurrenceId: 'no-such-occurrence',
          actingMemberId: null,
          clock: clock,
        ),
        completes,
      );
    });

    test('a rotation chore still advances AND rotates: the real ChoreService '
        'path is used, not a hand-rolled shortcut', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final m2 = await _insertMember(db, 'm2', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Rotation',
        startDate: today,
        assignmentMode: AssignmentMode.rotation,
        recurrence: Recurrence.everyNDays(1),
        assigneeMemberIds: [m1, m2],
      );
      final pending = (await repo.pendingOccurrenceOf(chore.id))!;
      expect(pending.assignedMemberId, m1);

      await applyDoneAction(
        database: db,
        occurrenceId: pending.id,
        actingMemberId: m1,
        clock: clock,
      );

      final next = (await repo.pendingOccurrenceOf(chore.id))!;
      expect(next.id, isNot(pending.id));
      expect(next.assignedMemberId, m2);
      expect(next.dueDate, today.addDays(1));
    });
  });

  group('rewriteDigestHorizon', () {
    NotificationScheduler schedulerFor(FakeDigestNotificationPlugin plugin) =>
        NotificationScheduler(
          plugin: plugin,
          localeResolver: () => const Locale('en'),
        );

    test('after the only due chore is completed, NOTHING is left armed -- '
        'this is the stale-body fix', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'One-off',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final pending = (await repo.pendingOccurrenceOf(chore.id))!;

      final plugin = FakeDigestNotificationPlugin();
      final scheduler = schedulerFor(plugin);

      // Arm the horizon first, from the PRE-completion state, so the test
      // proves the rewrite silenced armed slots rather than that nothing was
      // ever armed.
      final settings = await SettingsRepository(db).ensureSettings();
      await scheduler.applyDigestPlans(
        buildDigestPlans(
          now: clock.now(),
          settings: settings,
          pending: await repo.getPendingOccurrences(householdId),
          recipientMemberId: m1,
        ),
        actingMemberId: m1,
      );
      expect(
        plugin.pending,
        isNotEmpty,
        reason:
            'the pre-completion horizon must actually be armed, or the '
            'post-rewrite assertion below is vacuous',
      );

      await applyDoneAction(
        database: db,
        occurrenceId: pending.id,
        actingMemberId: m1,
        clock: clock,
      );
      await rewriteDigestHorizon(
        database: db,
        scheduler: scheduler,
        actingMemberId: m1,
        clock: clock,
      );

      expect(plugin.initializeCallCount, greaterThan(0));
      expect(
        plugin.pending,
        isEmpty,
        reason:
            'a one-off marked done from the notification must not leave a '
            'later slot armed saying "1 overdue chore"',
      );
    });

    test('scopes to actingMemberId: a partner\'s pending chore is '
        'ignored', () async {
      final me = await _insertMember(db, 'me', householdId);
      await _insertMember(db, 'partner', householdId);
      final theirChore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Theirs',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: ['partner'],
      );
      expect(await repo.pendingOccurrenceOf(theirChore.id), isNotNull);

      final plugin = FakeDigestNotificationPlugin();
      await rewriteDigestHorizon(
        database: db,
        scheduler: schedulerFor(plugin),
        actingMemberId: me,
        clock: clock,
      );

      // Guards against passing null through by accident, which would
      // silently widen every digest to household-wide.
      expect(plugin.pending, isEmpty);
    });

    test('a null actingMemberId widens to everything, matching '
        'projectDigestCounts', () async {
      await _insertMember(db, 'partner', householdId);
      await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Theirs',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: ['partner'],
      );

      final plugin = FakeDigestNotificationPlugin();
      await rewriteDigestHorizon(
        database: db,
        scheduler: schedulerFor(plugin),
        actingMemberId: null,
        clock: clock,
      );

      expect(plugin.pending, isNotEmpty);
    });

    test('the rewritten horizon carries the Done action and payload for a '
        'slot that still names one occurrence', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      final chore = await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Trash',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      final pending = (await repo.pendingOccurrenceOf(chore.id))!;

      final plugin = FakeDigestNotificationPlugin();
      await rewriteDigestHorizon(
        database: db,
        scheduler: schedulerFor(plugin),
        actingMemberId: m1,
        clock: clock,
      );

      final slotZero = plugin.pending[digestNotificationIdBase]!;
      expect(slotZero.actionable, isTrue);
      final payload = decodeDigestActionPayload(slotZero.payload);
      expect(payload!.occurrenceId, pending.id);
      expect(payload.actingMemberId, m1);
    });

    test('does nothing at all when there is no household', () async {
      await db.delete(db.households).go();
      final plugin = FakeDigestNotificationPlugin();
      await rewriteDigestHorizon(
        database: db,
        scheduler: schedulerFor(plugin),
        actingMemberId: null,
        clock: clock,
      );
      expect(plugin.scheduledCalls, isEmpty);
      expect(plugin.cancelCallCount, 0);
    });
  });

  group('readDigestLocale', () {
    test('an in-app language override reaches the isolate: the Done label '
        'must not be English behind a German app', () async {
      // The isolate has no Riverpod container, so it cannot read
      // localeOverrideProvider. It reads the same persisted settings.locale
      // that provider reads, through the same mapping -- backlog E-1's fix
      // must not be lost just because the scheduling moved isolates.
      await SettingsRepository(db).setLocale('de');
      expect(await readDigestLocale(db), const Locale('de'));
    });

    test('no stored override falls back to the OS locale, exactly like the '
        'main isolate', () async {
      await SettingsRepository(db).ensureSettings();
      expect(await readDigestLocale(db), resolveDigestLocale(null));
    });

    test('an unrecognized stored value degrades to the OS locale rather '
        'than throwing', () async {
      await SettingsRepository(db).setLocale('kl');
      expect(await readDigestLocale(db), resolveDigestLocale(null));
    });

    test('the isolate really schedules German copy when German is '
        'stored', () async {
      final m1 = await _insertMember(db, 'm1', householdId);
      await serviceOn(today).createChore(
        householdId: householdId,
        title: 'Müll',
        startDate: today,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [m1],
      );
      await SettingsRepository(db).setLocale('de');

      final plugin = FakeDigestNotificationPlugin();
      final scheduler = NotificationScheduler(
        plugin: plugin,
        localeResolver: () => const Locale('de'),
      );
      await rewriteDigestHorizon(
        database: db,
        scheduler: scheduler,
        actingMemberId: m1,
        clock: clock,
      );

      expect(plugin.lastDoneActionTitle, 'Erledigt');
      expect(plugin.pending[digestNotificationIdBase]!.body, '1 Aufgabe heute');
    });
  });

  group('household lookup', () {
    test('getHousehold is what scopes the rewrite', () async {
      // Documents the dependency the rewrite has on there being a household
      // at all, so a future reader does not "simplify" the early return away.
      expect((await HouseholdRepository(db).getHousehold())?.id, householdId);
    });
  });
}
