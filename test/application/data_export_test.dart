import 'dart:convert';

import 'package:chore_app/application/data_export.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/domain/recurrence/recurrence.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds one row of every table (spec `docs/specs/polish-round-1.md` B1),
/// including a soft-deleted row wherever the table supports soft-delete, so
/// [buildExportDocument] has something interesting to serialize:
/// - a recurring chore (`ch1`, weekly, rotation-assigned to two members)
///   alongside a soft-deleted one-off chore (`ch2`)
/// - a soft-deleted category and a soft-deleted shopping item
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
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: 'm2',
          householdId: 'h1',
          name: 'Kid',
          color: 0xFF8C7BC9,
          role: MemberRole.member,
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
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: 'c2',
          householdId: 'h1',
          kind: CategoryKind.shopping,
          name: 'Produce (deleted)',
          icon: 'nutrition',
          color: 0xFFD98E73,
          createdAt: 't0',
          updatedAt: 't0',
          deletedAt: const Value('t1'),
        ),
      );

  final recurrence = Recurrence.weekly(weekdays: {DateTime.saturday});
  await db
      .into(db.chores)
      .insert(
        ChoresCompanion.insert(
          id: 'ch1',
          householdId: 'h1',
          title: 'Take out trash',
          categoryId: const Value('c1'),
          recurrence: Value(recurrence),
          startDate: PlainDate(2026, 7, 25),
          assignmentMode: AssignmentMode.rotation,
          createdBy: const Value('m1'),
          createdAt: 't0',
          updatedAt: 't0',
        ),
      );
  await db
      .into(db.chores)
      .insert(
        ChoresCompanion.insert(
          id: 'ch2',
          householdId: 'h1',
          title: 'One-off (deleted)',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: 't0',
          updatedAt: 't0',
          deletedAt: const Value('t1'),
        ),
      );

  await db
      .into(db.choreAssignees)
      .insert(
        ChoreAssigneesCompanion.insert(
          choreId: 'ch1',
          memberId: 'm2',
          position: 0,
        ),
      );
  await db
      .into(db.choreAssignees)
      .insert(
        ChoreAssigneesCompanion.insert(
          choreId: 'ch1',
          memberId: 'm1',
          position: 1,
        ),
      );

  await db
      .into(db.choreOccurrences)
      .insert(
        ChoreOccurrencesCompanion.insert(
          id: 'occ1',
          choreId: 'ch1',
          dueDate: PlainDate(2026, 7, 25),
          assignedMemberId: const Value('m2'),
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
      .into(db.shoppingItems)
      .insert(
        ShoppingItemsCompanion.insert(
          id: 's2',
          householdId: 'h1',
          name: 'Eggs (deleted)',
          createdAt: 't0',
          updatedAt: 't0',
          deletedAt: const Value('t1'),
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

  group('buildExportDocument', () {
    test('envelope: format, schema_version, exported_at', () async {
      final clock = Clock.fixed(DateTime.utc(2026, 7, 31, 12, 34, 56));
      final document = await buildExportDocument(database: db, clock: clock);

      expect(document['format'], 1);
      expect(document['schema_version'], db.schemaVersion);
      expect(document['exported_at'], '2026-07-31T12:34:56.000Z');
    });

    test('the document is actually JSON-encodable end to end', () async {
      final document = await buildExportDocument(
        database: db,
        clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
      );

      // Round-trips through jsonEncode/jsonDecode without throwing -- this
      // is the real-world contract (the export is shared as a .json file),
      // not just "the Dart Map has the right shape".
      final decoded = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
      expect(decoded['format'], 1);
    });

    test('tables key has exactly the spec-listed tables, in order', () async {
      final document = await buildExportDocument(
        database: db,
        clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
      );
      final tables = document['tables']! as Map<String, Object?>;

      expect(tables.keys.toList(), [
        'households',
        'members',
        'categories',
        'chores',
        'chore_assignees',
        'chore_occurrences',
        'shopping_items',
        'settings',
      ]);
    });

    test('households: raw snake_case columns, exact values', () async {
      final document = await buildExportDocument(
        database: db,
        clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
      );
      final tables = document['tables']! as Map<String, Object?>;
      final households = tables['households']! as List<dynamic>;

      expect(households, hasLength(1));
      final household = households.single as Map<String, dynamic>;
      expect(household['id'], 'h1');
      expect(household['name'], 'My household');
      expect(household['created_at'], 't0');
      expect(household['updated_at'], 't0');
    });

    test('members: role stored as its raw enum name', () async {
      final document = await buildExportDocument(
        database: db,
        clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
      );
      final tables = document['tables']! as Map<String, Object?>;
      final members = (tables['members']! as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(members, hasLength(2));
      final me = members.singleWhere((row) => row['id'] == 'm1');
      expect(me['role'], 'admin');
      expect(me['household_id'], 'h1');
      final kid = members.singleWhere((row) => row['id'] == 'm2');
      expect(kid['role'], 'member');
    });

    test(
      'categories: soft-deleted rows are included, deleted_at raw text',
      () async {
        final document = await buildExportDocument(
          database: db,
          clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
        );
        final tables = document['tables']! as Map<String, Object?>;
        final categories = (tables['categories']! as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(categories, hasLength(2));
        final active = categories.singleWhere((row) => row['id'] == 'c1');
        expect(active['deleted_at'], isNull);
        expect(active['kind'], 'chore');
        final deleted = categories.singleWhere((row) => row['id'] == 'c2');
        expect(deleted['deleted_at'], 't1');
        expect(deleted['kind'], 'shopping');
      },
    );

    test(
      'chores: recurrence stays the raw JSON string, never decoded; '
      'a one-off chore has a null recurrence; soft-deleted chores are '
      'included',
      () async {
        final document = await buildExportDocument(
          database: db,
          clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
        );
        final tables = document['tables']! as Map<String, Object?>;
        final chores = (tables['chores']! as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(chores, hasLength(2));

        final recurring = chores.singleWhere((row) => row['id'] == 'ch1');
        expect(recurring['recurrence'], isA<String>());
        final decodedRecurrence =
            jsonDecode(recurring['recurrence']! as String)
                as Map<String, dynamic>;
        expect(
          decodedRecurrence,
          Recurrence.weekly(weekdays: {DateTime.saturday}).toJson(),
        );
        expect(recurring['start_date'], '2026-07-25');
        expect(recurring['assignment_mode'], 'rotation');
        expect(recurring['deleted_at'], isNull);

        final oneOff = chores.singleWhere((row) => row['id'] == 'ch2');
        expect(oneOff['recurrence'], isNull);
        expect(oneOff['deleted_at'], 't1');
      },
    );

    test('chore_assignees: rotation positions, raw column names', () async {
      final document = await buildExportDocument(
        database: db,
        clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
      );
      final tables = document['tables']! as Map<String, Object?>;
      final assignees = (tables['chore_assignees']! as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(assignees, hasLength(2));
      final first = assignees.singleWhere((row) => row['position'] == 0);
      expect(first['chore_id'], 'ch1');
      expect(first['member_id'], 'm2');
      final second = assignees.singleWhere((row) => row['position'] == 1);
      expect(second['member_id'], 'm1');
    });

    test(
      'chore_occurrences: status as raw enum name, due_date as text',
      () async {
        final document = await buildExportDocument(
          database: db,
          clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
        );
        final tables = document['tables']! as Map<String, Object?>;
        final occurrences = (tables['chore_occurrences']! as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(occurrences, hasLength(1));
        final occurrence = occurrences.single;
        expect(occurrence['status'], 'pending');
        expect(occurrence['due_date'], '2026-07-25');
        expect(occurrence['assigned_member_id'], 'm2');
      },
    );

    test('shopping_items: soft-deleted rows are included', () async {
      final document = await buildExportDocument(
        database: db,
        clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
      );
      final tables = document['tables']! as Map<String, Object?>;
      final items = (tables['shopping_items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(items, hasLength(2));
      final deleted = items.singleWhere((row) => row['id'] == 's2');
      expect(deleted['deleted_at'], 't1');
    });

    test(
      'settings: booleans come back as the 0/1 SQLite actually stores, '
      'shown-once flags are raw null',
      () async {
        final document = await buildExportDocument(
          database: db,
          clock: Clock.fixed(DateTime.utc(2026, 7, 31)),
        );
        final tables = document['tables']! as Map<String, Object?>;
        final settingsRows = (tables['settings']! as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(settingsRows, hasLength(1));
        final settings = settingsRows.single;
        expect(settings['digest_enabled'], 1);
        expect(settings['digest_minutes'], 480);
        expect(settings['onboarding_name_prompt_shown_at'], isNull);
        expect(settings['digest_preprompt_shown_at'], isNull);
      },
    );
  });

  group('exportFileName', () {
    test('formats as famdo-export-<yyyy-mm-dd>.json from the clock', () {
      final name = exportFileName(Clock.fixed(DateTime(2026, 7, 31, 9)));
      expect(name, 'famdo-export-2026-07-31.json');
    });

    test('uses the clock, never DateTime.now()', () {
      final name = exportFileName(Clock.fixed(DateTime(2019, 1, 5)));
      expect(name, 'famdo-export-2019-01-05.json');
    });
  });
}
