import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('foreign key enforcement', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test(
      'inserting an occurrence for a nonexistent chore throws',
      () async {
        await expectLater(
          db
              .into(db.choreOccurrences)
              .insert(
                ChoreOccurrencesCompanion.insert(
                  id: 'o1',
                  choreId: 'does-not-exist',
                  dueDate: PlainDate(2026, 1, 1),
                  createdAt: 't0',
                  updatedAt: 't0',
                ),
              ),
          throwsException,
        );
      },
    );

    test('inserting a member for a nonexistent household throws', () async {
      await expectLater(
        db
            .into(db.members)
            .insert(
              MembersCompanion.insert(
                id: 'm1',
                householdId: 'does-not-exist',
                name: 'Ghost',
                color: 0xFF000000,
                role: MemberRole.member,
                createdAt: 't0',
                updatedAt: 't0',
              ),
            ),
        throwsException,
      );
    });
  });
}
