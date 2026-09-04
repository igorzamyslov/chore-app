import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds one row of every table, mirroring
/// `test/application/data_export_test.dart`'s seed but simpler (no
/// soft-deleted rows needed here -- [resetAppData] must wipe everything
/// regardless of `deleted_at`).
Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: 'h1',
          name: 'My household',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: 'm1',
          householdId: 'h1',
          name: 'Me',
          color: 0xFF26A69A,
          role: MemberRole.admin,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: 'c1',
          householdId: 'h1',
          kind: CategoryKind.chore,
          name: 'Cleaning',
          icon: 'cleaning_services',
          color: 0xFF6D9F71,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.chores)
      .insert(
        ChoresCompanion.insert(
          id: 'ch1',
          householdId: 'h1',
          title: 'Take out trash',
          startDate: PlainDate(2026, 7, 25),
          assignmentMode: AssignmentMode.fixed,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.choreAssignees)
      .insert(
        ChoreAssigneesCompanion.insert(
          choreId: 'ch1',
          memberId: 'm1',
          position: 0,
        ),
      );
  await db
      .into(db.choreOccurrences)
      .insert(
        ChoreOccurrencesCompanion.insert(
          id: 'occ1',
          choreId: 'ch1',
          dueDate: PlainDate(2026, 7, 25),
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.reminderSnoozes)
      .insert(
        ReminderSnoozesCompanion.insert(
          occurrenceId: 'occ1',
          snoozedUntil: '2026-07-26T18:00:00.000Z',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.shoppingItems)
      .insert(
        ShoppingItemsCompanion.insert(
          id: 's1',
          householdId: 'h1',
          name: 'Milk',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.settings)
      .insert(
        SettingsCompanion.insert(
          id: 'device',
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _seed(db);
  });

  tearDown(() => db.close());

  test('resetAppData deletes every row from every table', () async {
    // Sanity check: every table actually has a row before the reset, so
    // the assertions below are meaningful.
    expect(await db.select(db.households).get(), hasLength(1));
    expect(await db.select(db.members).get(), hasLength(1));
    expect(await db.select(db.categories).get(), hasLength(1));
    expect(await db.select(db.chores).get(), hasLength(1));
    expect(await db.select(db.choreAssignees).get(), hasLength(1));
    expect(await db.select(db.choreOccurrences).get(), hasLength(1));
    expect(await db.select(db.shoppingItems).get(), hasLength(1));
    expect(await db.select(db.settings).get(), hasLength(1));
    expect(await db.select(db.reminderSnoozes).get(), hasLength(1));

    await resetAppData(db);

    expect(await db.select(db.households).get(), isEmpty);
    expect(await db.select(db.members).get(), isEmpty);
    expect(await db.select(db.categories).get(), isEmpty);
    expect(await db.select(db.chores).get(), isEmpty);
    expect(await db.select(db.choreAssignees).get(), isEmpty);
    expect(await db.select(db.choreOccurrences).get(), isEmpty);
    expect(await db.select(db.shoppingItems).get(), isEmpty);
    expect(await db.select(db.settings).get(), isEmpty);
    // Deleted explicitly rather than left to `chore_occurrences`' cascade
    // (spec `docs/specs/notifications-n2.md` §4.2): "the wipe deletes every
    // table" is the guarantee this test asserts, and a reader should not
    // have to reason about FK cascades to see that it holds.
    expect(await db.select(db.reminderSnoozes).get(), isEmpty);
  });

  test('resetAppData is safe to call on an already-empty database', () async {
    await resetAppData(db);

    await resetAppData(db);

    expect(await db.select(db.households).get(), isEmpty);
  });
}
