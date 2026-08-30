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
import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/reminder_planner.dart';
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

  /// A hand-built pending row.
  ///
  /// Every test ABOVE the `buildNotificationPlans` group builds its rows
  /// through the real `ChoreService`, and should keep doing so -- see this
  /// file's own doc comment. The groups below cannot: the partition fixture
  /// needs ~45 rows with DETERMINISTIC chore ids (D4's ceiling tiebreak is
  /// "lowest chore id", and the ceiling test has to name a specific loser),
  /// and `ChoreRepository.newId` hands out UUIDs. Constructing the two
  /// drift data classes directly is the smallest departure that buys that.
  OccurrenceWithChore row({
    required String id,
    required PlainDate dueDate,
    String? choreId,
    String choreTitle = 'Chore',
    int? reminderMinutes,
    PlainDate? startDate,
    Recurrence? recurrence,
    String? assignedMemberId,
  }) => OccurrenceWithChore(
    occurrence: ChoreOccurrence(
      id: id,
      choreId: choreId ?? 'chore-$id',
      dueDate: dueDate,
      status: OccurrenceStatus.pending,
      assignedMemberId: assignedMemberId,
      createdAt: 't0',
      updatedAt: 't0',
      syncDirty: false,
    ),
    chore: Chore(
      id: choreId ?? 'chore-$id',
      householdId: householdId,
      title: choreTitle,
      startDate: startDate ?? dueDate,
      assignmentMode: AssignmentMode.anyone,
      recurrence: recurrence,
      reminderMinutes: reminderMinutes,
      createdAt: 't0',
      updatedAt: 't0',
      syncDirty: false,
    ),
  );

  /// [row] with a different `chore.reminderMinutes`.
  OccurrenceWithChore reminderAt(OccurrenceWithChore source, int minutes) =>
      OccurrenceWithChore(
        occurrence: source.occurrence,
        chore: source.chore.copyWith(reminderMinutes: Value(minutes)),
      );

  /// The real settings row from `setUp`, with the N2 columns overridden.
  ///
  /// A `copyWith` over what `ensureSettings` actually wrote, never a
  /// hand-built `DeviceSettings` literal: a literal would need editing
  /// every time any column is added, and would silently disagree with the
  /// schema's own defaults in between.
  DeviceSettings withSettings({
    bool quietHoursEnabled = false,
    bool eveningReminderEnabled = false,
    int? digestMinutes,
  }) => settings.copyWith(
    quietHoursEnabled: quietHoursEnabled,
    eveningReminderEnabled: eveningReminderEnabled,
    digestMinutes: digestMinutes ?? settings.digestMinutes,
  );

  Future<List<OccurrenceWithChore>> pending() async {
    final rows = <List<OccurrenceWithChore>>[];
    final sub = chores.watchPendingOccurrences(householdId).listen(rows.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    return rows.last;
  }

  test('always returns exactly digestHorizonSlots entries', () async {
    final plans = buildDigestPlans(
      now: DateTime(2026, 1, 5, 7),
      settings: settings,
      pending: await pending(),
      recipientMemberId: null,
    );
    expect(plans, hasLength(digestHorizonSlots));
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
    // Offset 83 from the first slot: the far end of the segmented horizon,
    // not the old flat seven days.
    expect(plans.last!.fireAt, DateTime(2026, 3, 29, 8));
    for (final plan in plans) {
      expect(plan!.dueTodayCount, 1);
      expect(plan.overdueCount, 0);
    }
  });

  test(
    'pausing a chore silences the digest across the whole horizon '
    '(end-to-end behaviour lock: pausing both filters the chore out of '
    "watchPendingOccurrences's WHERE clause AND hard-deletes its pending "
    'occurrence via ChoreService.pauseChore, either of which alone would '
    'already make this pass)',
    () async {
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Water the plants',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
        recurrence: Recurrence.everyNDays(1),
      );

      final filled = buildDigestPlans(
        now: DateTime(2026, 1, 5, 7),
        settings: settings,
        pending: await pending(),
        recipientMemberId: null,
      );
      expect(filled.every((plan) => plan != null), isTrue);

      await service.pauseChore(chore.id);

      final paused = buildDigestPlans(
        now: DateTime(2026, 1, 5, 7),
        settings: settings,
        pending: await pending(),
        recipientMemberId: null,
      );
      expect(paused, everyElement(isNull));
    },
  );

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

  group(
    'buildNotificationPlans (spec docs/specs/notifications-n2.md §9.1)',
    () {
      test(
        'returns exactly digestHorizonSlots / reminderCeiling / '
        'eveningHorizonSlots entries, always',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(),
            pending: const [],
            recipientMemberId: null,
          );
          expect(plans.digest, hasLength(digestHorizonSlots));
          expect(plans.reminders, hasLength(reminderCeiling));
          expect(plans.evening, hasLength(eveningHorizonSlots));
          expect(plans.reminderOverflowCount, 0);
        },
      );

      test(
        'with no chore carrying reminder_minutes, every reminder and every '
        'evening entry is null -- which is production today, and is why '
        'slices 1-3 change nothing a user can see',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(),
            pending: [row(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
            recipientMemberId: null,
          );
          expect(plans.reminders, everyElement(isNull));
          expect(plans.evening, everyElement(isNull));
          expect(plans.digest.first, isNotNull);
        },
      );

      test(
        'an armed reminder is packed at the FRONT of the reminder list, so '
        'its position is its id offset',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(),
            pending: [
              row(
                id: 'o1',
                dueDate: PlainDate(2026, 8, 30),
                reminderMinutes: 1080,
              ),
            ],
            recipientMemberId: null,
          );
          expect(plans.reminders.first!.occurrenceId, 'o1');
          expect(plans.reminders.skip(1), everyElement(isNull));
        },
      );

      test(
        'buildDigestPlans still returns the digest half and still compiles '
        'for its existing callers',
        () async {
          final plans = buildDigestPlans(
            now: DateTime(2026, 1, 5, 7),
            settings: settings,
            pending: await pending(),
            recipientMemberId: null,
          );
          expect(plans, hasLength(digestHorizonSlots));
        },
      );

      test(
        'buildDigestPlans does NOT apply Rule D, even for a reminder-enabled '
        'chore -- the isolate and the pre-prompt banner write a digest-only '
        'horizon, and §10.1 accepts staleness that errs toward REPORTING',
        () {
          final pendingRows = [
            row(
              id: 'o1',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: 1080,
            ),
          ];
          final digestOnly = buildDigestPlans(
            now: DateTime(2026, 8, 30, 7),
            settings: withSettings(),
            pending: pendingRows,
            recipientMemberId: null,
          );
          final full = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 7),
            settings: withSettings(),
            pending: pendingRows,
            recipientMemberId: null,
          );
          expect(digestOnly.first!.dueTodayCount, 1);
          expect(
            full.digest.first,
            isNull,
            reason: 'the full pass omits it because a reminder speaks for it',
          );
        },
      );

      test(
        "the overflow count reaches the caller, and it is the PLANNER's "
        'number -- slice 4 reads this rather than re-deriving §2.3',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(),
            pending: [
              for (var i = 0; i < reminderCeiling + 4; i++)
                row(
                  id: 'o${i.toString().padLeft(3, '0')}',
                  choreId: 'c${i.toString().padLeft(3, '0')}',
                  dueDate: PlainDate(2026, 8, 31),
                  reminderMinutes: 1080,
                ),
            ],
            recipientMemberId: null,
          );
          expect(plans.reminderOverflowCount, 4);
          expect(
            plans.reminders.whereType<ReminderPlan>(),
            hasLength(reminderCeiling),
          );
          expect(
            plans.reminders.whereType<ReminderPlan>().length +
                plans.reminderOverflowCount,
            reminderCeiling + 4,
            reason:
                'the two halves cannot disagree: they come out of one '
                'truncation',
          );
        },
      );

      test(
        'a ceiling LOSER is still counted by the digest -- no chore is ever '
        'silent because of the ceiling (§3.2, D4)',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(),
            pending: [
              for (var i = 0; i < reminderCeiling + 1; i++)
                row(
                  id: 'o${i.toString().padLeft(3, '0')}',
                  choreId: 'c${i.toString().padLeft(3, '0')}',
                  dueDate: PlainDate(2026, 8, 31),
                  reminderMinutes: 1080,
                ),
            ],
            recipientMemberId: null,
          );
          final armedIds = plans.reminders
              .whereType<ReminderPlan>()
              .map((plan) => plan.occurrenceId)
              .toSet();
          // Every candidate is due on the same date at the same time, so the
          // chore-id tiebreak decides, and the highest id is the loser.
          final loser = 'o${reminderCeiling.toString().padLeft(3, '0')}';
          expect(armedIds, isNot(contains(loser)));

          // The 31st's slot must count exactly the one loser: the 33 armed
          // ones are omitted by Rule D, the loser is not.
          final slotForTheDay = plans.digest.firstWhere(
            (plan) =>
                plan != null &&
                PlainDate.fromDateTime(plan.fireAt) == PlainDate(2026, 8, 31),
          )!;
          expect(slotForTheDay.dueTodayCount, 1);
          expect(slotForTheDay.soleOccurrenceId, loser);
        },
      );

      test('the snooze map reaches the arming rule', () {
        final plans = buildNotificationPlans(
          now: DateTime(2026, 8, 30, 9),
          settings: withSettings(),
          pending: [
            row(
              id: 'o1',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: 1080,
            ),
          ],
          recipientMemberId: null,
          snoozedUntilByOccurrenceId: {'o1': DateTime(2026, 8, 31, 18).toUtc()},
        );
        expect(plans.reminders.first!.fireAt, DateTime(2026, 8, 31, 18));
      });

      test(
        'the evening horizon is GATED on the setting, which ships OFF (D12) '
        '-- so no existing install gains a second daily notification',
        () {
          final pendingRows = [
            row(id: 'o1', dueDate: PlainDate(2026, 8, 30)),
          ];
          final off = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(),
            pending: pendingRows,
            recipientMemberId: null,
          );
          expect(off.evening, everyElement(isNull));

          final on = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(eveningReminderEnabled: true),
            pending: pendingRows,
            recipientMemberId: null,
          );
          expect(on.evening.first, isNotNull);
          expect(on.evening.first!.fireAt, DateTime(2026, 8, 30, 20));
        },
      );

      test(
        'quiet hours DEFER a digest slot rather than dropping it (§6, D7) -- '
        'and the counts follow it onto the shifted date',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            // 23:30 digest, inside the default 22:00-07:00 window.
            settings: withSettings(
              quietHoursEnabled: true,
              digestMinutes: 1410,
            ),
            pending: [row(id: 'o1', dueDate: PlainDate(2026, 8, 31))],
            recipientMemberId: null,
          );
          expect(plans.digest.first!.fireAt, DateTime(2026, 8, 31, 7));
          expect(
            plans.digest.first!.dueTodayCount,
            1,
            reason:
                'the slot deferred onto the 31st, so it must count the 31st '
                "work, not the 30th's",
          );
        },
      );

      test(
        '...and a digest slot OUTSIDE the window is untouched, which is every '
        'shipped install: 08:00 is outside 22:00-07:00',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(quietHoursEnabled: true),
            pending: [row(id: 'o1', dueDate: PlainDate(2026, 8, 31))],
            recipientMemberId: null,
          );
          expect(plans.digest.first!.fireAt, DateTime(2026, 8, 31, 8));
        },
      );

      test(
        'quiet hours OFF leave a late digest exactly where it was -- the '
        'shift is opt-in, so v0.8.0 behaviour is byte-identical',
        () {
          final plans = buildNotificationPlans(
            now: DateTime(2026, 8, 30, 9),
            settings: withSettings(digestMinutes: 1410),
            pending: [row(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
            recipientMemberId: null,
          );
          expect(plans.digest.first!.fireAt, DateTime(2026, 8, 30, 23, 30));
        },
      );
    },
  );

  group(
    'THE PARTITION (spec docs/specs/notifications-n2.md §0.1) -- the one '
    'invariant every rule in §2-§6 exists to keep true',
    () {
      /// Test-local, deliberately independent re-derivation of "which
      /// in-scope occurrences would this date's digest slot count with N2
      /// switched off".
      ///
      /// Written as its own loop rather than by calling
      /// `projectDigestCounts` with an empty armed map: an oracle that
      /// calls the function under test can only ever agree with it, and the
      /// whole point here is to catch Rule D omitting the wrong set. It
      /// DOES use `projectedDueDateOn`, which this slice does not touch --
      /// duplicating the recurrence roll-forward here would test the wrong
      /// thing and would rot.
      Set<String> oracleCountedOn(
        List<ProjectedOccurrence> occurrences,
        PlainDate date,
        String? recipientMemberId,
      ) {
        final counted = <String>{};
        for (final occurrence in occurrences) {
          final assignee = occurrence.assignedMemberId;
          if (recipientMemberId != null &&
              assignee != null &&
              assignee != recipientMemberId) {
            continue;
          }
          // Due on, or overdue as of, this date.
          if (!projectedDueDateOn(occurrence, date).isAfter(date)) {
            counted.add(occurrence.id);
          }
        }
        return counted;
      }

      void expectPartition({
        required List<OccurrenceWithChore> pending,
        required String? recipientMemberId,
        required bool quietHoursEnabled,
        required DateTime now,
        bool requireSilentSlot = false,
      }) {
        final planSettings = withSettings(
          quietHoursEnabled: quietHoursEnabled,
        );
        final plans = buildNotificationPlans(
          now: now,
          settings: planSettings,
          pending: pending,
          recipientMemberId: recipientMemberId,
        );
        final projected = [
          for (final source in pending)
            ProjectedOccurrence(
              id: source.occurrence.id,
              choreId: source.chore.id,
              choreTitle: source.chore.title,
              reminderMinutes: source.chore.reminderMinutes,
              dueDate: source.occurrence.dueDate,
              startDate: source.chore.startDate,
              recurrence: source.chore.recurrence,
              assignedMemberId: source.occurrence.assignedMemberId,
            ),
        ];
        final armed = plans.reminders.whereType<ReminderPlan>().toList();

        // The slot moments are derived here rather than read off the plans,
        // so a SILENT slot is walked too. A null plan is a slot that
        // counted ZERO -- an answer, not the absence of one -- and skipping
        // those would let an over-omitting Rule D drive a slot to zero and
        // go unnoticed by the one test written to catch that.
        //
        // `applyQuietHours` is not the function under test here (it has its
        // own unit tests), so re-using it is not an oracle agreeing with
        // itself.
        final moments = [
          for (final moment in digestSlots(
            now: now,
            digestMinutes: planSettings.digestMinutes,
          ))
            applyQuietHours(
              candidate: moment,
              enabled: quietHoursEnabled,
              startMinutes: planSettings.quietStartMinutes,
              endMinutes: planSettings.quietEndMinutes,
            ),
        ];
        expect(moments, hasLength(plans.digest.length));

        var sawAnArmedDate = false;
        var sawANonSilentSlot = false;
        var sawASilentSlot = false;
        for (var k = 0; k < moments.length; k++) {
          final digestPlan = plans.digest[k];
          final fireAt = moments[k];
          if (digestPlan != null) {
            expect(
              digestPlan.fireAt,
              fireAt,
              reason: 'slot $k fired at a moment the caller cannot predict',
            );
          } else {
            sawASilentSlot = true;
          }
          final date = PlainDate.fromDateTime(fireAt);
          final oracle = oracleCountedOn(projected, date, recipientMemberId);
          final armedOnThisDate = armed
              .where((plan) => PlainDate.fromDateTime(plan.fireAt) == date)
              .map((plan) => plan.occurrenceId)
              .toSet();
          final digestTotal = digestPlan == null
              ? 0
              : digestPlan.dueTodayCount + digestPlan.overdueCount;

          // (a) NEVER NEITHER, half one: an armed reminder is always for
          //     something this date's digest would otherwise have reported.
          //     A reminder armed for an occurrence outside the oracle set
          //     would be a notification about nothing.
          expect(
            armedOnThisDate.difference(oracle),
            isEmpty,
            reason:
                'on $date, a reminder is armed for an occurrence the digest '
                'would not have counted at all',
          );

          // (b) NEVER BOTH and NEVER NEITHER, together: two disjoint
          //     subsets of a finite set whose sizes sum to the whole ARE a
          //     partition. Double-counting makes this sum too big; a hole
          //     makes it too small.
          expect(
            digestTotal + armedOnThisDate.length,
            oracle.length,
            reason:
                'on $date the digest counted $digestTotal and '
                '${armedOnThisDate.length} reminders are armed, but '
                '${oracle.length} occurrences are open -- either something '
                'is announced twice or something is announced by nobody',
          );

          if (armedOnThisDate.isNotEmpty) {
            sawAnArmedDate = true;
          }
          if (digestTotal > 0) {
            sawANonSilentSlot = true;
          }
        }

        // Vacuity guards. A fixture that never arms anything, or never has
        // anything to say, satisfies the identity trivially and proves
        // nothing.
        expect(
          sawAnArmedDate,
          isTrue,
          reason: 'a walk in which no reminder is ever armed proves nothing',
        );
        expect(
          sawANonSilentSlot,
          isTrue,
          reason: 'a walk in which the digest never speaks proves nothing',
        );
        // Coverage rather than vacuity. `mixedPending` cannot produce a
        // silent slot -- a one-off stays overdue forever, so once anything
        // is due every later slot has something to say -- which is why the
        // silent-slot branch needs a fixture of its own.
        if (requireSilentSlot) {
          expect(
            sawASilentSlot,
            isTrue,
            reason: 'this fixture must reach at least one silent slot',
          );
        }
      }

      // A mixed set covering every projection path AND every §2-§6 rule at
      // once: one-off, completion-anchored, schedule-anchored daily and
      // weekly; some reminder-enabled and some not; enough reminder-enabled
      // chores on one date to cross the ceiling; assigned, unassigned and
      // partner-assigned.
      List<OccurrenceWithChore> mixedPending() => [
        row(id: 'oneoff', choreId: 'c-oneoff', dueDate: PlainDate(2026, 9, 2)),
        row(
          id: 'oneoff-rem',
          choreId: 'c-oneoff-rem',
          dueDate: PlainDate(2026, 9, 3),
          reminderMinutes: 1080,
        ),
        row(
          id: 'comp',
          choreId: 'c-comp',
          dueDate: PlainDate(2026, 9, 4),
          recurrence: Recurrence.everyNDays(
            3,
            anchor: RecurrenceAnchor.completion,
          ),
        ),
        row(
          id: 'comp-rem',
          choreId: 'c-comp-rem',
          dueDate: PlainDate(2026, 9, 5),
          reminderMinutes: 1200,
          recurrence: Recurrence.everyNDays(
            3,
            anchor: RecurrenceAnchor.completion,
          ),
        ),
        row(
          id: 'daily',
          choreId: 'c-daily',
          dueDate: PlainDate(2026, 8, 31),
          startDate: PlainDate(2026, 8, 31),
          recurrence: Recurrence.everyNDays(1),
        ),
        row(
          id: 'daily-rem',
          choreId: 'c-daily-rem',
          dueDate: PlainDate(2026, 8, 31),
          startDate: PlainDate(2026, 8, 31),
          reminderMinutes: 1080,
          recurrence: Recurrence.everyNDays(1),
        ),
        row(
          id: 'weekly',
          choreId: 'c-weekly',
          dueDate: PlainDate(2026, 8, 31),
          startDate: PlainDate(2026, 8, 31),
          recurrence: Recurrence.weekly(weekdays: const {DateTime.monday}),
        ),
        row(
          id: 'mine',
          choreId: 'c-mine',
          dueDate: PlainDate(2026, 9, 1),
          reminderMinutes: 1080,
          assignedMemberId: 'me',
        ),
        row(
          id: 'theirs',
          choreId: 'c-theirs',
          dueDate: PlainDate(2026, 9, 1),
          reminderMinutes: 1080,
          assignedMemberId: 'partner',
        ),
        // Enough reminder-enabled chores on ONE date to push past the
        // ceiling, so the losers must land back in that date's digest
        // count.
        for (var i = 0; i < reminderCeiling + 3; i++)
          row(
            id: 'bulk${i.toString().padLeft(3, '0')}',
            choreId: 'c-bulk${i.toString().padLeft(3, '0')}',
            dueDate: PlainDate(2026, 9, 8),
            reminderMinutes: 1080,
          ),
      ];

      test('holds over a mixed set, unscoped, quiet hours OFF', () {
        expectPartition(
          pending: mixedPending(),
          recipientMemberId: null,
          quietHoursEnabled: false,
          now: DateTime(2026, 8, 30, 9),
        );
      });

      test('holds over the same set scoped to a recipient', () {
        expectPartition(
          pending: mixedPending(),
          recipientMemberId: 'me',
          quietHoursEnabled: false,
          now: DateTime(2026, 8, 30, 9),
        );
      });

      test(
        'holds with quiet hours ON -- a deferral moves a reminder onto the '
        'FOLLOWING calendar date, and Rule D must follow the reminder '
        'rather than the due date (§2.4)',
        () {
          // Reminder times of 1080/1200 are outside 22:00-07:00, so this
          // fixture is re-pointed at a late reminder time to force
          // deferrals.
          final pending = [
            for (final source in mixedPending())
              source.chore.reminderMinutes == null
                  ? source
                  // 23:00 -> deferred to 07:00 the next day.
                  : reminderAt(source, 1380),
          ];
          expectPartition(
            pending: pending,
            recipientMemberId: null,
            quietHoursEnabled: true,
            now: DateTime(2026, 8, 30, 9),
          );
        },
      );

      test(
        'holds when the digest time has ALREADY PASSED today, so slot 0 is '
        'tomorrow and today has no slot at all',
        () {
          expectPartition(
            pending: mixedPending(),
            recipientMemberId: null,
            quietHoursEnabled: false,
            now: DateTime(2026, 8, 30, 20),
          );
        },
      );

      test(
        'holds across SILENT slots too -- a slot that counts zero has an '
        'answer, and §2.5 says the digest goes silent on exactly the date a '
        'reminder speaks for it',
        () {
          // Everything is far enough out that the horizon opens with
          // genuinely empty slots. `mixedPending` cannot do this: a one-off
          // stays overdue forever, so once anything is due every later slot
          // speaks.
          expectPartition(
            pending: [
              row(
                id: 'later',
                choreId: 'c-later',
                dueDate: PlainDate(2026, 9, 5),
              ),
              row(
                id: 'later-rem',
                choreId: 'c-later-rem',
                dueDate: PlainDate(2026, 9, 8),
                reminderMinutes: 1080,
              ),
            ],
            recipientMemberId: null,
            quietHoursEnabled: false,
            now: DateTime(2026, 8, 30, 9),
            requireSilentSlot: true,
          );
        },
      );
    },
  );
}
