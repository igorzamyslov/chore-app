import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/due_tone.dart';
import 'package:flutter_test/flutter_test.dart';

/// The due-date -> status tone rule (spec `docs/specs/theme-v2.md` §4.1
/// item 4): today is success, overdue by 1-6 days is warning, overdue by 7
/// or more days is error, anything in the future is neutral.
void main() {
  final today = PlainDate(2026, 7, 22);

  DueTone toneFor(PlainDate dueDate) => dueTone(today: today, dueDate: dueDate);

  test('due today is success', () {
    expect(toneFor(today), DueTone.success);
  });

  test('due in the future is neutral', () {
    expect(toneFor(PlainDate(2026, 7, 23)), DueTone.neutral);
    expect(toneFor(PlainDate(2026, 9, 1)), DueTone.neutral);
  });

  test('overdue by 1 to 6 days is warning', () {
    expect(toneFor(PlainDate(2026, 7, 21)), DueTone.warning);
    expect(toneFor(PlainDate(2026, 7, 16)), DueTone.warning);
  });

  test('overdue by exactly 7 days or more is error', () {
    expect(toneFor(PlainDate(2026, 7, 15)), DueTone.error);
    expect(toneFor(PlainDate(2026, 6, 1)), DueTone.error);
  });

  test('the threshold counts calendar days across a month boundary', () {
    final firstOfMonth = PlainDate(2026, 8, 1);
    expect(
      dueTone(today: firstOfMonth, dueDate: PlainDate(2026, 7, 26)),
      DueTone.warning,
    );
    expect(
      dueTone(today: firstOfMonth, dueDate: PlainDate(2026, 7, 25)),
      DueTone.error,
    );
  });
}
