import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _insertHousehold(AppDatabase db, String id) async {
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
}

Future<void> _insertChore(
  AppDatabase db, {
  required String id,
  required String householdId,
  required PlainDate startDate,
  Recurrence? recurrence,
}) async {
  await db
      .into(db.chores)
      .insert(
        ChoresCompanion.insert(
          id: id,
          householdId: householdId,
          title: 'Chore $id',
          recurrence: Value(recurrence),
          startDate: startDate,
          assignmentMode: AssignmentMode.anyone,
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
}

void main() {
  group('PlainDateConverter', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _insertHousehold(db, 'h1');
    });

    tearDown(() => db.close());

    test('round-trips a variety of calendar dates', () async {
      final dates = [
        PlainDate(2026, 1, 1),
        PlainDate(2024, 2, 29), // leap day
        PlainDate(2026, 12, 31),
        PlainDate(1999, 7, 4),
      ];
      for (var i = 0; i < dates.length; i++) {
        await _insertChore(
          db,
          id: 'c$i',
          householdId: 'h1',
          startDate: dates[i],
        );
      }
      for (var i = 0; i < dates.length; i++) {
        final chore = await (db.select(
          db.chores,
        )..where((tbl) => tbl.id.equals('c$i'))).getSingle();
        expect(chore.startDate, dates[i]);
      }
    });

    test('invalid persisted date text throws on read', () async {
      await _insertChore(
        db,
        id: 'c0',
        householdId: 'h1',
        startDate: PlainDate(2026, 1, 1),
      );
      await db.customStatement(
        "UPDATE chores SET start_date = 'not-a-date' WHERE id = 'c0'",
      );
      await expectLater(
        (db.select(db.chores)..where((tbl) => tbl.id.equals('c0'))).getSingle(),
        throwsFormatException,
      );
    });
  });

  group('RecurrenceConverter', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await _insertHousehold(db, 'h1');
    });

    tearDown(() => db.close());

    test('round-trips every recurrence combination, and null', () async {
      final combos = <Recurrence?>[
        null,
        Recurrence.everyNDays(3),
        Recurrence.everyNDays(5, anchor: RecurrenceAnchor.completion),
        Recurrence.weekly(interval: 2, weekdays: {1, 3, 5}),
        Recurrence.weekly(anchor: RecurrenceAnchor.completion),
        Recurrence.monthlyOnDay(),
        Recurrence.monthlyOnDay(anchor: RecurrenceAnchor.completion),
        Recurrence.monthlyOnNthWeekday(1, 2),
        Recurrence.monthlyOnNthWeekday(-1, 5, interval: 2),
      ];
      for (var i = 0; i < combos.length; i++) {
        await _insertChore(
          db,
          id: 'c$i',
          householdId: 'h1',
          startDate: PlainDate(2026, 1, 1),
          recurrence: combos[i],
        );
      }
      for (var i = 0; i < combos.length; i++) {
        final chore = await (db.select(
          db.chores,
        )..where((tbl) => tbl.id.equals('c$i'))).getSingle();
        // A direct value comparison, now that `Recurrence` has `==`
        // (backlog E-4). This used to go through a `toJson()` projection
        // helper, which could not tell a genuine round-trip from two rules
        // that merely serialize alike.
        expect(chore.recurrence, combos[i]);
      }
    });

    test('invalid persisted JSON throws on read', () async {
      await _insertChore(
        db,
        id: 'c0',
        householdId: 'h1',
        startDate: PlainDate(2026, 1, 1),
      );
      await db.customStatement(
        "UPDATE chores SET recurrence = 'not valid json' WHERE id = 'c0'",
      );
      await expectLater(
        (db.select(db.chores)..where((tbl) => tbl.id.equals('c0'))).getSingle(),
        throwsFormatException,
      );
    });

    test('malformed-but-valid JSON throws on read', () async {
      await _insertChore(
        db,
        id: 'c0',
        householdId: 'h1',
        startDate: PlainDate(2026, 1, 1),
      );
      await db.customStatement(
        'UPDATE chores SET recurrence = \'{"interval": "not a number"}\' '
        "WHERE id = 'c0'",
      );
      await expectLater(
        (db.select(db.chores)..where((tbl) => tbl.id.equals('c0'))).getSingle(),
        throwsFormatException,
      );
    });
  });
}
