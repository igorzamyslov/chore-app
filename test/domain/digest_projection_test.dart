import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectedOccurrence _occurrence({
  required PlainDate dueDate,
  String id = 'occ',
  String? choreId,
  String choreTitle = 'Chore',
  int? reminderMinutes,
  PlainDate? startDate,
  Recurrence? recurrence,
  String? assignedMemberId,
}) {
  return ProjectedOccurrence(
    id: id,
    // Defaults to the occurrence id so existing call sites keep distinct
    // chore ids without naming them; tests about the D4 tiebreak pass it
    // explicitly.
    choreId: choreId ?? id,
    choreTitle: choreTitle,
    reminderMinutes: reminderMinutes,
    dueDate: dueDate,
    startDate: startDate ?? dueDate,
    recurrence: recurrence,
    assignedMemberId: assignedMemberId,
  );
}

void main() {
  group('projectedDueDateOn', () {
    test('a one-off never moves: it just goes further overdue', () {
      final occurrence = _occurrence(dueDate: PlainDate(2026, 1, 5));
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 9)),
        PlainDate(2026, 1, 5),
      );
    });

    test('a completion-anchored chore never moves either', () {
      final occurrence = _occurrence(
        dueDate: PlainDate(2026, 1, 5),
        recurrence: Recurrence.everyNDays(
          2,
          anchor: RecurrenceAnchor.completion,
        ),
      );
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 9)),
        PlainDate(2026, 1, 5),
      );
    });

    test('a schedule-anchored daily chore rolls forward to that very day', () {
      final occurrence = _occurrence(
        dueDate: PlainDate(2026, 1, 5),
        recurrence: Recurrence.everyNDays(1),
      );
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 9)),
        PlainDate(2026, 1, 9),
      );
    });

    test('a schedule-anchored weekly chore lands on its own slot, not the '
        'queried day', () {
      // 2026-01-05 is a Monday; the query date is the following Thursday.
      final occurrence = _occurrence(
        dueDate: PlainDate(2026, 1, 5),
        recurrence: Recurrence.weekly(weekdays: const {DateTime.monday}),
      );
      expect(
        projectedDueDateOn(occurrence, PlainDate(2026, 1, 15)),
        PlainDate(2026, 1, 12),
      );
    });
  });

  group('projectDigestCounts', () {
    test('splits due-on-the-day from overdue-before-it', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(dueDate: PlainDate(2026, 1, 6)),
          _occurrence(dueDate: PlainDate(2026, 1, 6)),
          _occurrence(dueDate: PlainDate(2026, 1, 2)),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 2);
      expect(counts.overdueCount, 1);
      expect(counts.isSilent, isFalse);
    });

    test('ignores occurrences due after the queried day', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(dueDate: PlainDate(2026, 1, 20))],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.isSilent, isTrue);
    });

    test("counts mine and unassigned, but not my partner's (OPD-1 A)", () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(dueDate: PlainDate(2026, 1, 6), assignedMemberId: 'me'),
          _occurrence(dueDate: PlainDate(2026, 1, 6)),
          _occurrence(
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: 'me',
      );
      expect(counts.dueCount, 2);
      expect(counts.overdueCount, 0);
    });

    test('a null recipient counts everything (identity unknown must not '
        'hide work)', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(dueDate: PlainDate(2026, 1, 6), assignedMemberId: 'me'),
          _occurrence(
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 2);
    });

    test('scoping is applied before projection, not after', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(
            dueDate: PlainDate(2026, 1, 5),
            recurrence: Recurrence.everyNDays(1),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 9),
        recipientMemberId: 'me',
      );
      expect(counts.isSilent, isTrue);
    });
  });

  group('soleOccurrenceId (spec docs/specs/notifications.md N2)', () {
    test('exactly one occurrence due on the queried date names that '
        'occurrence', () {
      final counts = projectDigestCounts(
        occurrences: [_occurrence(id: 'only', dueDate: PlainDate(2026, 1, 6))],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 1);
      expect(counts.soleOccurrenceId, 'only');
    });

    test('exactly one OVERDUE occurrence and nothing due still names it: an '
        'overdue-only slot is actionable too', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(id: 'rotten', dueDate: PlainDate(2026, 1, 2)),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 0);
      expect(counts.overdueCount, 1);
      expect(counts.soleOccurrenceId, 'rotten');
    });

    test('two occurrences name nothing: "the chore" is ambiguous', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(id: 'a', dueDate: PlainDate(2026, 1, 6)),
          _occurrence(id: 'b', dueDate: PlainDate(2026, 1, 2)),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount + counts.overdueCount, 2);
      expect(counts.soleOccurrenceId, isNull);
    });

    test('zero occurrences name nothing', () {
      final counts = projectDigestCounts(
        occurrences: const [],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.isSilent, isTrue);
      expect(counts.soleOccurrenceId, isNull);
    });

    test('an occurrence due AFTER the queried day is not the sole one -- it '
        'does not count at all', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(id: 'today', dueDate: PlainDate(2026, 1, 6)),
          _occurrence(id: 'later', dueDate: PlainDate(2026, 1, 20)),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: null,
      );
      expect(counts.dueCount, 1);
      expect(counts.soleOccurrenceId, 'today');
    });

    test('SCOPING is respected: two occurrences of which one is my '
        "partner's names MINE, not null", () {
      // The case that catches deciding the sole id BEFORE scoping instead
      // of after, which would silently make the Done action vanish in every
      // two-person household. Mirrors 'scoping is applied before
      // projection, not after' above.
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(
            id: 'mine',
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'me',
          ),
          _occurrence(
            id: 'theirs',
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: 'me',
      );
      expect(counts.dueCount, 1);
      expect(counts.soleOccurrenceId, 'mine');
    });

    test("a partner's occurrence is never named, even when it is the only "
        'one there is', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(
            id: 'theirs',
            dueDate: PlainDate(2026, 1, 6),
            assignedMemberId: 'partner',
          ),
        ],
        date: PlainDate(2026, 1, 6),
        recipientMemberId: 'me',
      );
      expect(counts.isSilent, isTrue);
      expect(counts.soleOccurrenceId, isNull);
    });

    test('PROJECTION is respected: a schedule-anchored occurrence that '
        'rolls forward is still the sole id at that date', () {
      final counts = projectDigestCounts(
        occurrences: [
          _occurrence(
            id: 'daily',
            dueDate: PlainDate(2026, 1, 5),
            recurrence: Recurrence.everyNDays(1),
          ),
        ],
        date: PlainDate(2026, 1, 9),
        recipientMemberId: null,
      );
      // It rolled forward onto the queried date, so it is DUE, not overdue.
      expect(counts.dueCount, 1);
      expect(counts.overdueCount, 0);
      expect(counts.soleOccurrenceId, 'daily');
    });
  });

  group('the silence decision is monotone', () {
    // WHY THIS GROUP EXISTS: the digest horizon's trailing segment samples
    // dates sparsely (every `digestHorizonTailStepDays` days rather than
    // every day). That is only safe because, while the app is closed,
    // nothing can complete or delete an occurrence -- so once a date has
    // something to say, every LATER date does too, and its counts already
    // include everything the skipped days would have reported. A sparse
    // tail therefore loses cadence, never coverage.
    //
    // These are characterization tests: they pass against unchanged code.
    // They exist so that a future change to `projectedDueDateOn` or to the
    // recipient scoping fails loudly HERE rather than silently turning the
    // tail into a coverage hole.
    //
    // SCOPE, since N2 (spec `docs/specs/notifications-n2.md` §2.5): this
    // property holds over the digest TAKEN ALONE only for occurrence sets
    // with NO armed reminders, and every set below is deliberately such a
    // set -- none of them passes `armedReminderDates`, so the parameter
    // defaults to `const {}`. That is not a weakening: for these sets the
    // sparse tail's original safety argument is untouched and still
    // load-bearing, which is why the group is kept VERBATIM rather than
    // relaxed into an `isNotEmpty`-shaped assertion.
    //
    // What replaces it in general is §0.1's partition, which holds over the
    // UNION of the two channels and is tested in
    // `test/application/digest_plan_builder_test.dart`. The last test in
    // this group proves the loss is real rather than theoretical.
    //
    // The walk spans 120 days, comfortably past the furthest slot the
    // shipped horizon can produce (day 83 = digestDailyHorizonDays - 1 +
    // digestHorizonTailStepDays * digestWeeklyHorizonSlots). IF THE HORIZON
    // IS EVER RAISED PAST DAY 120, EXTEND THIS WALK.
    const walkDays = 120;
    final start = PlainDate(2026, 1, 5); // a Monday

    /// Walks [walkDays] dates from [start] and asserts that `isSilent`
    /// never goes back to `true` once it has become `false`, and that
    /// `dueCount + overdueCount` never decreases.
    ///
    /// Also asserts the walk is not vacuous: at least one date must be
    /// non-silent, or an empty/always-silent occurrence set would satisfy
    /// the monotonicity assertions trivially.
    void expectMonotone(
      List<ProjectedOccurrence> occurrences, {
      required String? recipientMemberId,
    }) {
      var sawNonSilent = false;
      var previousTotal = 0;
      for (var offset = 0; offset < walkDays; offset++) {
        final date = start.addDays(offset);
        final counts = projectDigestCounts(
          occurrences: occurrences,
          date: date,
          recipientMemberId: recipientMemberId,
        );
        final total = counts.dueCount + counts.overdueCount;
        if (sawNonSilent) {
          expect(
            counts.isSilent,
            isFalse,
            reason:
                'a date that was non-silent earlier must never become '
                'silent again — at $date (offset $offset)',
          );
        }
        expect(
          total,
          greaterThanOrEqualTo(previousTotal),
          reason:
              'the reported work must never decrease while the app is '
              'closed — at $date (offset $offset)',
        );
        previousTotal = total;
        if (!counts.isSilent) {
          sawNonSilent = true;
        }
      }
      expect(
        sawNonSilent,
        isTrue,
        reason: 'a walk in which nothing is ever due proves nothing',
      );
    }

    test('a one-off', () {
      expectMonotone(
        [_occurrence(dueDate: PlainDate(2026, 1, 20))],
        recipientMemberId: null,
      );
    });

    test('a completion-anchored recurring chore', () {
      expectMonotone(
        [
          _occurrence(
            dueDate: PlainDate(2026, 1, 20),
            recurrence: Recurrence.everyNDays(
              3,
              anchor: RecurrenceAnchor.completion,
            ),
          ),
        ],
        recipientMemberId: null,
      );
    });

    test('a schedule-anchored daily chore', () {
      expectMonotone(
        [
          _occurrence(
            dueDate: PlainDate(2026, 1, 20),
            startDate: PlainDate(2026, 1, 20),
            recurrence: Recurrence.everyNDays(1),
          ),
        ],
        recipientMemberId: null,
      );
    });

    test('a schedule-anchored weekly chore', () {
      expectMonotone(
        [
          _occurrence(
            dueDate: PlainDate(2026, 1, 19), // a Monday
            startDate: PlainDate(2026, 1, 19),
            recurrence: Recurrence.weekly(weekdays: const {DateTime.monday}),
          ),
        ],
        recipientMemberId: null,
      );
    });

    test('a mixed set, unscoped', () {
      expectMonotone(_mixedSet(), recipientMemberId: null);
    });

    test('a mixed set scoped to a recipient — scoping is date-independent, '
        'so it cannot break the property', () {
      // The set deliberately mixes assigned-to-me, assigned-to-partner and
      // unassigned occurrences: if scoping ever became date-dependent, the
      // partner's entries would drop in or out mid-walk and break this.
      expectMonotone(_mixedSet(), recipientMemberId: 'me');
    });

    test(
      'the property is GENUINELY LOST once a reminder is armed -- §2.5 '
      'records this as the honest cost, and a comment nobody can fail is '
      'not a record',
      () {
        final occurrences = [
          _occurrence(id: 'bins', dueDate: PlainDate(2026, 1, 20)),
        ];
        final armed = {'bins': PlainDate(2026, 1, 20)};
        final onItsOwnDate = projectDigestCounts(
          occurrences: occurrences,
          date: PlainDate(2026, 1, 20),
          recipientMemberId: null,
          armedReminderDates: armed,
        );
        final theDayAfter = projectDigestCounts(
          occurrences: occurrences,
          date: PlainDate(2026, 1, 21),
          recipientMemberId: null,
          armedReminderDates: armed,
        );
        expect(
          onItsOwnDate.isSilent,
          isTrue,
          reason: 'the reminder speaks for this date, so the digest does not',
        );
        expect(
          theDayAfter.isSilent,
          isFalse,
          reason:
              'silent then non-silent: monotonicity over the digest alone is '
              'broken, exactly as §2.5 says. If this ever passes as monotone '
              'again, Rule D has stopped working.',
        );
      },
    );
  });

  group(
    'Rule D -- never announced twice (spec docs/specs/notifications-n2.md '
    '§2.4, D2)',
    () {
      test(
        'an occurrence with a reminder armed on THIS date is omitted from '
        'dueCount',
        () {
          final counts = projectDigestCounts(
            occurrences: [
              _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
            ],
            date: PlainDate(2026, 8, 30),
            recipientMemberId: null,
            armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
          );
          expect(counts.dueCount, 0);
          expect(counts.overdueCount, 0);
          expect(counts.isSilent, isTrue);
        },
      );

      test(
        '...and from overdueCount too, when a quiet-hours deferral moved the '
        'reminder onto a date the occurrence is already overdue on -- §2.4 '
        'states the GENERAL form for exactly this case',
        () {
          final counts = projectDigestCounts(
            occurrences: [
              _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
            ],
            date: PlainDate(2026, 8, 31),
            recipientMemberId: null,
            armedReminderDates: {'bins': PlainDate(2026, 8, 31)},
          );
          expect(counts.overdueCount, 0);
          expect(counts.isSilent, isTrue);
        },
      );

      test(
        'an occurrence armed on a DIFFERENT date is counted normally -- the '
        'rule is keyed on the ARMED date, not on the chore',
        () {
          final counts = projectDigestCounts(
            occurrences: [
              _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
            ],
            date: PlainDate(2026, 8, 31),
            recipientMemberId: null,
            armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
          );
          expect(
            counts.overdueCount,
            1,
            reason:
                'bins reminded Tuesday and ignored MUST reappear in '
                "Wednesday's digest -- that is escalation, not repetition, "
                'and the digest is the overdue channel (§2.4, D8)',
          );
        },
      );

      test(
        'the omission clears the soleOccurrenceId gate as well as the counts '
        '-- a slot that now counts nothing may not carry a Done button for '
        'the thing it stopped counting',
        () {
          final counts = projectDigestCounts(
            occurrences: [
              _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
            ],
            date: PlainDate(2026, 8, 30),
            recipientMemberId: null,
            armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
          );
          expect(counts.soleOccurrenceId, isNull);
        },
      );

      test(
        'omitting one of two occurrences promotes the OTHER to sole '
        'occurrence -- the gate is re-decided after the omission, not before '
        'it',
        () {
          final counts = projectDigestCounts(
            occurrences: [
              _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
              _occurrence(id: 'dishes', dueDate: PlainDate(2026, 8, 30)),
            ],
            date: PlainDate(2026, 8, 30),
            recipientMemberId: null,
            armedReminderDates: {'bins': PlainDate(2026, 8, 30)},
          );
          expect(counts.dueCount, 1);
          expect(counts.soleOccurrenceId, 'dishes');
        },
      );

      test(
        'an empty armed map changes nothing at all -- which is what lets '
        'every existing caller and the monotonicity group above stay '
        'verbatim',
        () {
          final withMap = projectDigestCounts(
            occurrences: [
              _occurrence(id: 'bins', dueDate: PlainDate(2026, 8, 30)),
            ],
            date: PlainDate(2026, 8, 30),
            recipientMemberId: null,
            armedReminderDates: const {},
          );
          expect(withMap.dueCount, 1);
          expect(withMap.soleOccurrenceId, 'bins');
        },
      );
    },
  );
}

/// A set covering every projection path at once, with a mix of assigned,
/// unassigned and partner-assigned occurrences and staggered due dates so
/// the walk crosses several silent → non-silent transitions.
List<ProjectedOccurrence> _mixedSet() => [
  _occurrence(dueDate: PlainDate(2026, 1, 20), assignedMemberId: 'me'),
  _occurrence(dueDate: PlainDate(2026, 2, 14)),
  _occurrence(
    dueDate: PlainDate(2026, 3, 2),
    assignedMemberId: 'partner',
  ),
  _occurrence(
    dueDate: PlainDate(2026, 1, 26),
    startDate: PlainDate(2026, 1, 26),
    recurrence: Recurrence.everyNDays(1),
    assignedMemberId: 'me',
  ),
  _occurrence(
    dueDate: PlainDate(2026, 2, 2), // a Monday
    startDate: PlainDate(2026, 2, 2),
    recurrence: Recurrence.weekly(weekdays: const {DateTime.monday}),
  ),
  _occurrence(
    dueDate: PlainDate(2026, 3, 9),
    recurrence: Recurrence.everyNDays(
      4,
      anchor: RecurrenceAnchor.completion,
    ),
    assignedMemberId: 'partner',
  ),
];
