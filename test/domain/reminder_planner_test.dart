import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reminder-enabled projected occurrence, unless a test says otherwise.
///
/// [choreId] defaults to [id] so most call sites get distinct, orderable
/// chore ids without naming them; the D4 tiebreak tests pass it explicitly.
ProjectedOccurrence _occ({
  required PlainDate dueDate,
  String id = 'occ',
  String? choreId,
  String choreTitle = 'Bins',
  int? reminderMinutes = 1080, // 18:00 unless a test says otherwise
  PlainDate? startDate,
  Recurrence? recurrence,
  String? assignedMemberId,
}) => ProjectedOccurrence(
  id: id,
  choreId: choreId ?? id,
  choreTitle: choreTitle,
  reminderMinutes: reminderMinutes,
  dueDate: dueDate,
  startDate: startDate ?? dueDate,
  recurrence: recurrence,
  assignedMemberId: assignedMemberId,
);

ReminderPlanResult _plan(
  List<ProjectedOccurrence> occurrences, {
  DateTime? now,
  String? recipientMemberId,
  Map<String, DateTime> snoozes = const {},
  bool quietHoursEnabled = false,
}) => planReminders(
  now: now ?? DateTime(2026, 8, 30, 9),
  occurrences: occurrences,
  recipientMemberId: recipientMemberId,
  snoozedUntilByOccurrenceId: snoozes,
  quietHoursEnabled: quietHoursEnabled,
  quietStartMinutes: 1320,
  quietEndMinutes: 420,
);

void main() {
  group(
    'the id-budget constants (spec docs/specs/notifications-n2.md §3.1)',
    () {
      test(
        'reminderCeiling is DERIVED from the budget and the evening horizon, '
        'never written as 33 -- the split must move as one number when it '
        'moves at all',
        () {
          expect(reminderCeiling, n2NotificationIdBudget - eveningHorizonSlots);
          // The shipped values, pinned so a silent edit is visible in a diff.
          expect(n2NotificationIdBudget, 40);
          expect(eveningHorizonSlots, 7);
          expect(reminderCeiling, 33);
        },
      );

      test(
        'the bases are far apart, so an off-by-one inside one range cannot '
        'land inside another',
        () {
          expect(reminderNotificationIdBase, 2001);
          expect(eveningNotificationIdBase, 3001);
        },
      );

      test('the arm window and the default reminder time', () {
        expect(reminderArmWindowDays, 14);
        expect(defaultReminderMinutes, 1080); // 18:00
      });
    },
  );

  group('applyQuietHours (spec docs/specs/notifications-n2.md §6)', () {
    // 22:00 -> 07:00, the shipped default: a WRAPPING window.
    DateTime shift(
      DateTime candidate, {
      bool enabled = true,
      int start = 1320,
      int end = 420,
    }) => applyQuietHours(
      candidate: candidate,
      enabled: enabled,
      startMinutes: start,
      endMinutes: end,
    );

    test(
      'disabled: returns the candidate untouched, even inside the window',
      () {
        final candidate = DateTime(2026, 8, 30, 23, 30);
        expect(shift(candidate, enabled: false), candidate);
      },
    );

    test('outside a wrapping window: untouched', () {
      final candidate = DateTime(2026, 8, 30, 18);
      expect(shift(candidate), candidate);
    });

    test(
      'inside a wrapping window, LATE side: deferred to the window end on '
      'the FOLLOWING calendar day',
      () {
        expect(shift(DateTime(2026, 8, 30, 23, 30)), DateTime(2026, 8, 31, 7));
      },
    );

    test(
      'inside a wrapping window, EARLY side: deferred to the window end on '
      'the SAME calendar day',
      () {
        expect(shift(DateTime(2026, 8, 30, 3, 15)), DateTime(2026, 8, 30, 7));
      },
    );

    test(
      'inside a NON-wrapping window (a daytime quiet window): deferred to '
      'its end the same day',
      () {
        expect(
          shift(DateTime(2026, 8, 30, 11), start: 600, end: 840),
          DateTime(2026, 8, 30, 14),
        );
      },
    );

    test('outside a NON-wrapping window: untouched', () {
      final candidate = DateTime(2026, 8, 30, 15);
      expect(shift(candidate, start: 600, end: 840), candidate);
    });

    test('a candidate exactly AT start is INSIDE (deferred)', () {
      expect(shift(DateTime(2026, 8, 30, 22)), DateTime(2026, 8, 31, 7));
    });

    test('a candidate exactly AT end is OUTSIDE (untouched)', () {
      final candidate = DateTime(2026, 8, 30, 7);
      expect(shift(candidate), candidate);
    });

    test(
      'start == end is OFF, not a 24-hour window -- "never notify" is what '
      'the toggle is for',
      () {
        final candidate = DateTime(2026, 8, 30, 23, 30);
        expect(shift(candidate, start: 600, end: 600), candidate);
      },
    );

    test(
      'the deferral target is a WALL-CLOCK time and must not shift an hour '
      'across the spring-forward transition (Europe/Berlin, 2026-03-29 '
      '02:00 -> 03:00)',
      () {
        // Candidate at 23:30 on the night BEFORE the clocks go forward. The
        // answer must be 07:00 local on the 29th, not 06:00 or 08:00.
        final result = shift(DateTime(2026, 3, 28, 23, 30));
        expect(result.year, 2026);
        expect(result.month, 3);
        expect(result.day, 29);
        expect(result.hour, 7);
        expect(result.minute, 0);
      },
    );

    test(
      '...and not across the autumn fall-back transition either '
      '(2026-10-25 03:00 -> 02:00)',
      () {
        final result = shift(DateTime(2026, 10, 24, 23, 30));
        expect(result.year, 2026);
        expect(result.month, 10);
        expect(result.day, 25);
        expect(result.hour, 7);
        expect(result.minute, 0);
      },
    );

    test(
      'the answer is always at or after the candidate -- the property the '
      'arming rule relies on (§2.3 step 5 drops a PAST moment, so a shift '
      'that went backwards would silently delete reminders)',
      () {
        for (var minute = 0; minute < 1440; minute += 7) {
          final candidate = DateTime(2026, 8, 30, minute ~/ 60, minute % 60);
          expect(
            shift(candidate).isBefore(candidate),
            isFalse,
            reason: 'shift went backwards for $candidate',
          );
        }
      },
    );

    test('rejects a minute-of-day outside 0..1439 on either end', () {
      expect(
        () => shift(DateTime(2026, 8, 30, 12), start: -1),
        throwsArgumentError,
      );
      expect(
        () => shift(DateTime(2026, 8, 30, 12), end: 1440),
        throwsArgumentError,
      );
    });
  });

  group('planReminders (spec docs/specs/notifications-n2.md §2.3)', () {
    test('a chore with NO reminder_minutes is not eligible at all', () {
      final result = _plan([
        _occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
      ]);
      expect(result.armed, isEmpty);
      expect(result.overflowCount, 0);
    });

    test(
      'arms at the due date at reminder_minutes, and carries the chore '
      'title verbatim',
      () {
        final result = _plan([
          _occ(
            id: 'o1',
            dueDate: PlainDate(2026, 8, 30),
            // Deliberately not the helper's default: the notification's
            // title is the chore title VERBATIM (§11), so the assertion has
            // to be able to tell the two apart.
            choreTitle: 'Take the bins out',
          ),
        ]);
        expect(result.armed, hasLength(1));
        expect(result.armed.single.fireAt, DateTime(2026, 8, 30, 18));
        expect(result.armed.single.occurrenceId, 'o1');
        expect(result.armed.single.choreTitle, 'Take the bins out');
        expect(result.armed.single.dueDate, PlainDate(2026, 8, 30));
      },
    );

    test(
      'a SCHEDULE-anchored chore rolls forward to its next series slot, and '
      'that is a genuine new due date, not a repeat (spec §7)',
      () {
        // Daily chore, occurrence 3 days stale. On 2026-08-30 catch-up
        // would roll it to today, so today at 18:00 is when it is armed.
        final result = _plan([
          _occ(
            id: 'daily',
            dueDate: PlainDate(2026, 8, 27),
            startDate: PlainDate(2026, 8, 27),
            recurrence: Recurrence.everyNDays(1),
          ),
        ]);
        expect(result.armed.single.fireAt, DateTime(2026, 8, 30, 18));
        expect(result.armed.single.dueDate, PlainDate(2026, 8, 30));
      },
    );

    test(
      'a ONE-OFF does NOT roll forward, so an overdue one is silent (D8: an '
      'individual reminder says "this is due today", never "you failed")',
      () {
        final result = _plan([
          _occ(id: 'oneoff', dueDate: PlainDate(2026, 8, 27)),
        ]);
        expect(result.armed, isEmpty);
        expect(result.overflowCount, 0);
      },
    );

    test('a COMPLETION-anchored chore does not roll forward either', () {
      final result = _plan([
        _occ(
          id: 'comp',
          dueDate: PlainDate(2026, 8, 27),
          recurrence: Recurrence.everyNDays(
            3,
            anchor: RecurrenceAnchor.completion,
          ),
        ),
      ]);
      expect(result.armed, isEmpty);
    });

    test(
      'a moment already PAST today is dropped -- 18:00 when it is already '
      '20:00 (D8)',
      () {
        final result = _plan([
          _occ(dueDate: PlainDate(2026, 8, 30)),
        ], now: DateTime(2026, 8, 30, 20));
        expect(result.armed, isEmpty);
      },
    );

    test(
      'a moment more than reminderArmWindowDays out is dropped (D3), and '
      'one exactly ON the boundary is kept',
      () {
        final justInside = _plan([
          _occ(
            id: 'in',
            dueDate: PlainDate(2026, 8, 30).addDays(reminderArmWindowDays),
          ),
        ]);
        expect(justInside.armed, hasLength(1));

        final justOutside = _plan([
          _occ(
            id: 'out',
            dueDate: PlainDate(2026, 8, 30).addDays(reminderArmWindowDays + 1),
          ),
        ]);
        expect(justOutside.armed, isEmpty);
        expect(
          justOutside.overflowCount,
          0,
          reason:
              'the window is not the ceiling -- a chore too far out did not '
              'LOSE a slot, it never competed for one',
        );
      },
    );

    test(
      'an occurrence assigned to someone else is out of scope (§2.2) -- a '
      'shared reminder_minutes column does not mean a shared alarm',
      () {
        final result = _plan(
          [
            _occ(
              id: 'mine',
              dueDate: PlainDate(2026, 8, 30),
              assignedMemberId: 'me',
            ),
            _occ(
              id: 'theirs',
              dueDate: PlainDate(2026, 8, 30),
              assignedMemberId: 'partner',
            ),
            _occ(id: 'anyone', dueDate: PlainDate(2026, 8, 30)),
          ],
          recipientMemberId: 'me',
        );
        expect(
          result.armed.map((plan) => plan.occurrenceId),
          ['anyone', 'mine'], // tie on fireAt -> chore-id ascending
        );
      },
    );

    test('an unresolvable acting member puts EVERYTHING in scope', () {
      final result = _plan([
        _occ(
          id: 'theirs',
          dueDate: PlainDate(2026, 8, 30),
          assignedMemberId: 'partner',
        ),
      ]);
      expect(result.armed, hasLength(1));
    });

    test('a FUTURE snooze overrides the arm moment (§2.3 step 3)', () {
      final result = _plan(
        [_occ(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
        snoozes: {'o1': DateTime(2026, 8, 31, 18).toUtc()},
      );
      expect(result.armed.single.fireAt, DateTime(2026, 8, 31, 18));
      expect(
        result.armed.single.dueDate,
        PlainDate(2026, 8, 30),
        reason:
            'snooze moves the NOTIFICATION, never the occurrence (D5) -- the '
            'due date it reports is still the real one',
      );
    });

    test(
      'a PAST snooze does not override, and the ordinary arm moment still '
      'applies',
      () {
        final result = _plan(
          [_occ(id: 'o1', dueDate: PlainDate(2026, 8, 30))],
          snoozes: {'o1': DateTime(2026, 8, 29, 18).toUtc()},
        );
        expect(result.armed.single.fireAt, DateTime(2026, 8, 30, 18));
      },
    );

    test(
      'the quiet-hours shift is applied to a SNOOZED moment too -- §2.3 '
      'step 4 is the only place the shift happens, including for a snooze',
      () {
        final result = _plan(
          [
            _occ(
              id: 'o1',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: 1380, // 23:00, inside 22:00-07:00
            ),
          ],
          snoozes: {'o1': DateTime(2026, 8, 31, 23).toUtc()},
          quietHoursEnabled: true,
        );
        expect(result.armed.single.fireAt, DateTime(2026, 9, 1, 7));
      },
    );

    test(
      'quiet hours DEFER an ordinary reminder rather than dropping it (D7)',
      () {
        final result = _plan([
          _occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: 1380),
        ], quietHoursEnabled: true);
        expect(result.armed.single.fireAt, DateTime(2026, 8, 31, 7));
      },
    );

    test(
      'the armed list is sorted by fire moment ascending, tie-broken by '
      'CHORE id ascending -- stable across recomputes and across devices '
      '(D4)',
      () {
        // The occurrence ids and the chore ids are deliberately
        // ANTI-CORRELATED on the tied pair: occurrence `o1` carries chore
        // `c-zulu` and `o2` carries `c-bravo`, so sorting by occurrence id
        // and sorting by chore id give DIFFERENT answers. With correlated
        // ids (the obvious way to write this) both orderings agree and the
        // test cannot fail for the very property it names -- verified by
        // running the occurrence-id tiebreak against it.
        //
        // Why chore id and not occurrence id: an occurrence id changes
        // every time the chore regenerates, so it is not stable across
        // recomputes; the chore id is (D4).
        final result = _plan([
          _occ(id: 'o1', choreId: 'c-zulu', dueDate: PlainDate(2026, 8, 30)),
          _occ(id: 'o2', choreId: 'c-bravo', dueDate: PlainDate(2026, 8, 30)),
          _occ(id: 'o3', choreId: 'c-alpha', dueDate: PlainDate(2026, 8, 31)),
        ]);
        expect(result.armed.map((plan) => plan.choreId), [
          'c-bravo',
          'c-zulu',
          'c-alpha',
        ]);
        expect(
          result.armed.map((plan) => plan.occurrenceId),
          ['o2', 'o1', 'o3'],
          reason:
              'the tied pair is ordered by CHORE id, which puts o2 '
              'first even though o1 sorts first by occurrence id',
        );
      },
    );

    group('the ceiling (§3.2, D4)', () {
      List<ProjectedOccurrence> candidates(int count, {int dayOffset = 0}) => [
        for (var i = 0; i < count; i++)
          _occ(
            id: 'o${i.toString().padLeft(3, '0')}',
            choreId: 'c${i.toString().padLeft(3, '0')}',
            dueDate: PlainDate(2026, 8, 30).addDays(dayOffset),
          ),
      ];

      test('34 candidates: the 33 soonest win and exactly one overflows', () {
        final result = _plan(candidates(reminderCeiling + 1));
        expect(result.armed, hasLength(reminderCeiling));
        expect(result.overflowCount, 1);
      });

      test('exactly reminderCeiling candidates: none overflows', () {
        final result = _plan(candidates(reminderCeiling));
        expect(result.armed, hasLength(reminderCeiling));
        expect(result.overflowCount, 0);
      });

      test(
        'NEAREST-FIRST is what wins: a chore due tomorrow beats a chore due '
        'in a week, whatever their ids',
        () {
          final result = _plan([
            // reminderCeiling chores due in a week, ids sorting FIRST.
            for (var i = 0; i < reminderCeiling; i++)
              _occ(
                id: 'a${i.toString().padLeft(3, '0')}',
                choreId: 'a${i.toString().padLeft(3, '0')}',
                dueDate: PlainDate(2026, 9, 6),
              ),
            // One chore due tomorrow, id sorting LAST.
            _occ(id: 'zzz', choreId: 'zzz', dueDate: PlainDate(2026, 8, 31)),
          ]);
          expect(
            result.armed.first.choreId,
            'zzz',
            reason:
                'nearest-first never delays a reminder in favour of a later '
                'one',
          );
          expect(result.armed, hasLength(reminderCeiling));
          expect(result.overflowCount, 1);
        },
      );

      test(
        'overflowCount counts ONLY the chores the CEILING turned away -- not '
        'the ones the 14-day window or the past-moment rule excluded, which '
        'never competed for a slot at all',
        () {
          final result = _plan([
            // 33 genuine competitors -> all armed.
            for (var i = 0; i < reminderCeiling; i++)
              _occ(
                id: 'in${i.toString().padLeft(3, '0')}',
                choreId: 'in${i.toString().padLeft(3, '0')}',
                dueDate: PlainDate(2026, 8, 31),
              ),
            // 5 reminder-enabled chores beyond the arm window.
            for (var i = 0; i < 5; i++)
              _occ(
                id: 'far$i',
                choreId: 'far$i',
                dueDate: PlainDate(
                  2026,
                  8,
                  30,
                ).addDays(reminderArmWindowDays + 1 + i),
              ),
            // 3 reminder-enabled one-offs already overdue.
            for (var i = 0; i < 3; i++)
              _occ(
                id: 'old$i',
                choreId: 'old$i',
                dueDate: PlainDate(2026, 8, 20).addDays(i),
              ),
          ]);
          expect(result.armed, hasLength(reminderCeiling));
          expect(
            result.overflowCount,
            0,
            reason:
                'the naive "every reminder-enabled chore minus the armed '
                'ones" would say 8 here, and it would be wrong: the Settings '
                'sub-line promises "N chores stayed in the summary BECAUSE '
                'of the limit"',
          );
        },
      );

      test(
        '...and it does count them when the ceiling really is what bit: 40 '
        'competitors inside the window plus 5 outside it overflows by '
        'SEVEN, not twelve',
        () {
          final result = _plan([
            for (var i = 0; i < 40; i++)
              _occ(
                id: 'in${i.toString().padLeft(3, '0')}',
                choreId: 'in${i.toString().padLeft(3, '0')}',
                dueDate: PlainDate(2026, 8, 31),
              ),
            for (var i = 0; i < 5; i++)
              _occ(
                id: 'far$i',
                choreId: 'far$i',
                dueDate: PlainDate(
                  2026,
                  8,
                  30,
                ).addDays(reminderArmWindowDays + 1 + i),
              ),
          ]);
          expect(result.armed, hasLength(reminderCeiling));
          expect(result.overflowCount, 40 - reminderCeiling);
        },
      );

      test(
        'armed.length + overflowCount is the eligible set, always -- the '
        'invariant that makes the two impossible to disagree',
        () {
          for (final count in [
            0,
            1,
            reminderCeiling - 1,
            reminderCeiling,
            reminderCeiling + 1,
            100,
          ]) {
            final result = _plan(candidates(count));
            expect(
              result.armed.length + result.overflowCount,
              count,
              reason: 'for $count eligible candidates',
            );
          }
        },
      );
    });
  });

  group('planEveningSlots (spec docs/specs/notifications-n2.md §5)', () {
    List<EveningPlan?> plan(
      List<ProjectedOccurrence> occurrences, {
      DateTime? now,
      bool enabled = true,
      int eveningMinutes = 1200, // 20:00
      List<ReminderPlan> armed = const [],
      bool quietHoursEnabled = false,
      int quietStart = 1320,
      int quietEnd = 420,
      String? recipientMemberId,
    }) => planEveningSlots(
      now: now ?? DateTime(2026, 8, 30, 9),
      enabled: enabled,
      eveningMinutes: eveningMinutes,
      occurrences: occurrences,
      recipientMemberId: recipientMemberId,
      armedReminders: armed,
      quietHoursEnabled: quietHoursEnabled,
      quietStartMinutes: quietStart,
      quietEndMinutes: quietEnd,
    );

    ReminderPlan reminderAt(DateTime fireAt, {String occurrenceId = 'a'}) =>
        ReminderPlan(
          fireAt: fireAt,
          occurrenceId: occurrenceId,
          choreId: 'c-$occurrenceId',
          choreTitle: 'Bins',
          dueDate: PlainDate(2026, 8, 30),
        );

    test(
      'always returns exactly eveningHorizonSlots entries, one per '
      'consecutive day, starting with today when the time is still ahead',
      () {
        final slots = plan([
          _occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
        ]);
        expect(slots, hasLength(eveningHorizonSlots));
        expect(slots.first!.fireAt, DateTime(2026, 8, 30, 20));
        expect(slots[1]?.fireAt, isNull);
        expect(slots.last?.fireAt, isNull);
      },
    );

    test(
      'the slot moments are consecutive days at the evening time, whether '
      'or not each one fires -- proved on a daily chore, which is open on '
      'every one of them',
      () {
        final slots = plan([
          _occ(
            dueDate: PlainDate(2026, 8, 30),
            startDate: PlainDate(2026, 8, 30),
            reminderMinutes: null,
            recurrence: Recurrence.everyNDays(1),
          ),
        ]);
        expect(slots, hasLength(eveningHorizonSlots));
        expect(slots.first!.fireAt, DateTime(2026, 8, 30, 20));
        expect(slots[1]!.fireAt, DateTime(2026, 8, 31, 20));
        expect(slots.last!.fireAt, DateTime(2026, 9, 5, 20));
      },
    );

    test(
      'when the evening time has already passed today, the first slot is '
      'tomorrow -- the same rule nextDigestSlot uses',
      () {
        final slots = plan([
          _occ(dueDate: PlainDate(2026, 8, 31), reminderMinutes: null),
        ], now: DateTime(2026, 8, 30, 21));
        expect(slots.first!.fireAt, DateTime(2026, 8, 31, 20));
      },
    );

    test('disabled: every slot is null', () {
      final slots = plan([
        _occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
      ], enabled: false);
      expect(slots, everyElement(isNull));
      expect(slots, hasLength(eveningHorizonSlots));
    });

    test('fires on a due-today count, and says how many are open', () {
      final slots = plan([
        _occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
        _occ(id: 'b', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
      ]);
      expect(slots.first!.openCount, 2);
      expect(slots.first!.soleOccurrenceId, isNull);
    });

    test(
      'names a sole occurrence when exactly one counts -- the same gate the '
      'digest uses',
      () {
        final slots = plan([
          _occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
        ]);
        expect(slots.first!.soleOccurrenceId, 'a');
      },
    );

    test(
      'an OVERDUE-only day does NOT fire (D6) -- this is the whole anti-nag '
      'design',
      () {
        final slots = plan([
          _occ(dueDate: PlainDate(2026, 8, 29), reminderMinutes: null),
        ]);
        expect(slots.first, isNull);
      },
    );

    test(
      'THE PROPERTY: the same occurrence cannot produce the evening '
      're-reminder two evenings running, because by the second evening it '
      'is overdue rather than due-today (D6). There is no state in which '
      'this feature settles into a nightly drumbeat.',
      () {
        final slots = plan([
          _occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
        ]);
        expect(slots.first!.openCount, 1);
        expect(
          slots.skip(1),
          everyElement(isNull),
          reason:
              'every later evening sees it as overdue, and overdue never '
              'counts',
        );
      },
    );

    test(
      'a still-to-come reminder at armAt >= M SUPPRESSES the summary -- it '
      'would arrive minutes later and say the same thing better',
      () {
        final slots = plan(
          [
            _occ(
              id: 'a',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: null,
            ),
          ],
          armed: [reminderAt(DateTime(2026, 8, 30, 21))], // after the slot
        );
        expect(slots.first, isNull);
      },
    );

    test(
      'a reminder landing exactly ON the slot moment still suppresses it -- '
      '§5 says `armAt >= M`, and two notifications in the same minute is '
      'the collision the rule exists to prevent',
      () {
        final slots = plan(
          [
            _occ(
              id: 'a',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: null,
            ),
          ],
          armed: [reminderAt(DateTime(2026, 8, 30, 20))],
        );
        expect(slots.first, isNull);
      },
    );

    test(
      'a reminder that ALREADY FIRED earlier that evening does NOT suppress '
      'the summary',
      () {
        final slots = plan(
          [
            _occ(
              id: 'a',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: null,
            ),
          ],
          armed: [reminderAt(DateTime(2026, 8, 30, 18))], // before the slot
        );
        expect(slots.first!.openCount, 1);
      },
    );

    test('a reminder armed on ANOTHER date does not suppress this slot', () {
      final slots = plan(
        [_occ(id: 'a', dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
        armed: [reminderAt(DateTime(2026, 8, 31, 21))],
      );
      expect(slots.first!.openCount, 1);
    });

    test(
      "a reminder for a DIFFERENT occurrence does not suppress this one's "
      'slot',
      () {
        final slots = plan(
          [
            _occ(
              id: 'a',
              dueDate: PlainDate(2026, 8, 30),
              reminderMinutes: null,
            ),
          ],
          armed: [
            reminderAt(
              DateTime(2026, 8, 30, 21),
              occurrenceId: 'somethingElse',
            ),
          ],
        );
        expect(slots.first!.openCount, 1);
      },
    );

    test(
      'an evening time inside quiet hours is DROPPED, not deferred (D7) -- '
      'an "evening" re-reminder delivered at 07:00 has a false premise and '
      'would collide with the 08:00 digest',
      () {
        final slots = plan(
          [_occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null)],
          eveningMinutes: 1350, // 22:30, inside 22:00-07:00
          quietHoursEnabled: true,
        );
        expect(slots, everyElement(isNull));
      },
    );

    test(
      'the shipped defaults do not collide: 20:00 evening sits an hour '
      'clear of the 22:00 quiet-hours start',
      () {
        final slots = plan([
          _occ(dueDate: PlainDate(2026, 8, 30), reminderMinutes: null),
        ], quietHoursEnabled: true);
        expect(slots.first, isNotNull);
      },
    );

    test('recipient scoping applies, exactly as it does to the digest', () {
      final slots = plan(
        [
          _occ(
            id: 'theirs',
            dueDate: PlainDate(2026, 8, 30),
            reminderMinutes: null,
            assignedMemberId: 'partner',
          ),
        ],
        recipientMemberId: 'me',
      );
      expect(slots.first, isNull);
    });
  });
}
