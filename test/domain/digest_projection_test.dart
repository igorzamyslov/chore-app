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
}
