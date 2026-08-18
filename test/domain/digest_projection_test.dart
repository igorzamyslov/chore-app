import 'package:chore_app/domain/digest_projection.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectedOccurrence _occurrence({
  required PlainDate dueDate,
  PlainDate? startDate,
  Recurrence? recurrence,
  String? assignedMemberId,
}) {
  return ProjectedOccurrence(
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
  });
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
