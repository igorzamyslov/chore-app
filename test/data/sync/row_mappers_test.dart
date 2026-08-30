/// `row_mappers.dart` tests for the one N2 field that leaves the device
/// (spec `docs/specs/notifications-n2.md` §8.2).
///
/// `chores.reminder_minutes` is the whole of N2's sync surface: `settings`
/// is device-scoped and `reminder_snoozes` is device-scoped, so nothing
/// else in this feature needs a mapper at all. These tests cover the push
/// shape, the pull shape, and the two tolerances §8.2 point 3 requires of a
/// mixed-version fleet.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/sync/row_mappers.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pulled `chores` row with every key the server sends, minus whatever
/// [without] names and plus whatever [extra] adds.
///
/// Written as a helper rather than repeated inline so the two tolerance
/// tests below differ by exactly the one key each is about.
Map<String, Object?> _serverChoreRow({
  Set<String> without = const {},
  Map<String, Object?> extra = const {},
}) {
  final row = <String, Object?>{
    'id': 'ch1',
    'household_id': 'h1',
    'title': 'Bins',
    'notes': null,
    'category_id': null,
    'recurrence': null,
    'start_date': '2026-01-05',
    'assignment_mode': 'anyone',
    'paused_at': null,
    'reminder_minutes': null,
    'created_by': null,
    'created_at': 't0',
    'updated_at': 't0',
    'deleted_at': null,
    ...extra,
  };
  without.forEach(row.remove);
  return row;
}

void main() {
  test(
    'choreRow carries reminder_minutes, and choreFromRow round-trips it '
    '(spec docs/specs/notifications-n2.md §8.2)',
    () {
      final chore = Chore(
        id: 'ch1',
        householdId: 'h1',
        title: 'Bins',
        startDate: PlainDate(2026, 1, 5),
        assignmentMode: AssignmentMode.anyone,
        reminderMinutes: 1080,
        createdAt: 't0',
        updatedAt: 't0',
        syncDirty: true,
      );
      final row = choreRow(chore);
      expect(row['reminder_minutes'], 1080);
      expect(choreFromRow(row).reminderMinutes, 1080);
    },
  );

  test('a NULL reminder_minutes round-trips as null', () {
    final chore = Chore(
      id: 'ch1',
      householdId: 'h1',
      title: 'Bins',
      startDate: PlainDate(2026, 1, 5),
      assignmentMode: AssignmentMode.anyone,
      createdAt: 't0',
      updatedAt: 't0',
      syncDirty: true,
    );
    final row = choreRow(chore);
    expect(
      row.containsKey('reminder_minutes'),
      isTrue,
      reason:
          'the push must send an explicit NULL, not omit the key -- '
          'omitting it would leave a stale server value in place',
    );
    expect(row['reminder_minutes'], isNull);
    expect(choreFromRow(row).reminderMinutes, isNull);
  });

  test(
    'choreFromRow tolerates the key being ABSENT entirely -- an '
    'un-migrated server (spec docs/specs/notifications-n2.md §8.2 point 3, '
    'the mixed-version cost)',
    () {
      final row = _serverChoreRow(without: {'reminder_minutes'});
      expect(choreFromRow(row).reminderMinutes, isNull);
    },
  );

  test(
    'choreFromRow reads a PostgREST JSON number, not just an int -- the '
    'same `as num?` tolerance color/sort_order already have',
    () {
      final row = _serverChoreRow(extra: {'reminder_minutes': 1080.0});
      expect(choreFromRow(row).reminderMinutes, 1080);
    },
  );
}
