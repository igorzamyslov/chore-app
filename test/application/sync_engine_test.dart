/// Tests `SupabaseSyncEngine`/`NoopSyncEngine` (spec
/// `docs/specs/sync-backend.md` §8) against a real in-memory `AppDatabase`
/// and the [FakeSyncTransport] fake -- no live Supabase involved (spec
/// §8.4). Covers the full LWW matrix, the mid-push re-dirty guard, the
/// cursor's commit-only advance, the members/households push special cases,
/// FK ordering, and the start()/stop() triggers.
library;

import 'package:chore_app/application/member_service.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sync_transport.dart';

/// A [FakeSyncTransport] whose [pullTable] throws on [failOnTable] --
/// simulates a network failure partway through a pull's per-table fetch
/// loop, which happens BEFORE the local apply transaction ever opens.
class _ThrowingPullTransport extends FakeSyncTransport {
  _ThrowingPullTransport(this.failOnTable);

  final String failOnTable;

  @override
  Future<List<Map<String, Object?>>> pullTable(
    String table, {
    required String householdId,
    required DateTime? since,
  }) {
    if (table == failOnTable) {
      throw Exception('simulated network failure');
    }
    return super.pullTable(table, householdId: householdId, since: since);
  }
}

/// A [FakeSyncTransport] whose [hasMembership] THROWS -- simulates a
/// transient network failure IN the revocation probe itself (a dropped
/// connection, a timeout), as opposed to [FakeSyncTransport.membershipPresent]
/// `= false`, which models the probe SUCCEEDING with an empty result (the
/// actual revocation signal). These must be handled differently: a throw
/// here propagates past both of `_pullSinceInner`'s membership-revoked
/// writes into `pullSince`'s outer `on Object catch` and is swallowed as an
/// ordinary retry-later, leaving the device linked and unflagged. Pins that
/// distinction against a future refactor that wraps the probe in its own
/// try/catch and folds "probe threw" into "probe returned false" -- which
/// would silently convert every network blip into a permanent unlink.
class _RevocationProbeFailsTransport extends FakeSyncTransport {
  @override
  Future<bool> hasMembership(String householdId) async {
    throw Exception('simulated network failure in the revocation probe');
  }
}

void main() {
  group('NoopSyncEngine', () {
    test('every method is a true no-op and never throws', () async {
      const engine = NoopSyncEngine();
      await engine.pushDirty();
      await engine.pullSince();
      engine
        ..start()
        ..stop();
    });
  });

  group('SupabaseSyncEngine LWW matrix (spec §8.4)', () {
    late AppDatabase db;
    late HouseholdRepository households;
    late CategoryRepository categories;
    late Household household;
    late FakeSyncTransport transport;
    late SettingsRepository settings;
    late SupabaseSyncEngine engine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      households = HouseholdRepository(db);
      categories = CategoryRepository(db);
      household = await households.createLocalHousehold('Me');
      transport = FakeSyncTransport();
      settings = SettingsRepository(db);
      engine = SupabaseSyncEngine(
        db: db,
        transport: transport,
        settings: settings,
        householdId: household.id,
      );
    });

    tearDown(() async {
      engine.stop();
      await db.close();
    });

    Future<void> clearCategoryDirty(String id) =>
        (db.update(db.categories)..where((tbl) => tbl.id.equals(id))).write(
          const CategoriesCompanion(syncDirty: Value(false)),
        );

    test('pulled-newer vs local-clean: pull replaces the local row', () async {
      final category = await categories.createCategory(
        household.id,
        kind: CategoryKind.chore,
        name: 'Old name',
        icon: 'a',
        color: 1,
      );
      await clearCategoryDirty(category.id);

      transport.serverRows['categories']!.add({
        'id': category.id,
        'household_id': household.id,
        'kind': 'chore',
        'name': 'New name from server',
        'icon': 'b',
        'color': 2,
        'sort_order': 0,
        'created_at': category.createdAt,
        'updated_at': DateTime.utc(2026, 6).toIso8601String(),
        'deleted_at': null,
      });

      await engine.pullSince();

      final row = await (db.select(
        db.categories,
      )..where((tbl) => tbl.id.equals(category.id))).getSingle();
      expect(row.name, 'New name from server');
      expect(row.color, 2);
      expect(row.syncDirty, isFalse);
    });

    test(
      'pulled vs local-dirty: pull keeps the local row untouched',
      () async {
        final category = await categories.createCategory(
          household.id,
          kind: CategoryKind.chore,
          name: 'Old name',
          icon: 'a',
          color: 1,
        );
        // Deliberately left dirty (not cleared) -- simulates an unsynced
        // local edit racing the pull.

        transport.serverRows['categories']!.add({
          'id': category.id,
          'household_id': household.id,
          'kind': 'chore',
          'name': 'New name from server',
          'icon': 'b',
          'color': 2,
          'sort_order': 0,
          'created_at': category.createdAt,
          'updated_at': DateTime.utc(2026, 6).toIso8601String(),
          'deleted_at': null,
        });

        await engine.pullSince();

        final row = await (db.select(
          db.categories,
        )..where((tbl) => tbl.id.equals(category.id))).getSingle();
        expect(row.name, 'Old name');
        expect(row.syncDirty, isTrue);
      },
    );

    test(
      'tombstone pull: a soft-deleted server row replicates deletedAt '
      'locally',
      () async {
        final category = await categories.createCategory(
          household.id,
          kind: CategoryKind.chore,
          name: 'Old name',
          icon: 'a',
          color: 1,
        );
        await clearCategoryDirty(category.id);

        transport.serverRows['categories']!.add({
          'id': category.id,
          'household_id': household.id,
          'kind': 'chore',
          'name': 'Old name',
          'icon': 'a',
          'color': 1,
          'sort_order': 0,
          'created_at': category.createdAt,
          'updated_at': DateTime.utc(2026, 6).toIso8601String(),
          'deleted_at': DateTime.utc(2026, 6).toIso8601String(),
        });

        await engine.pullSince();

        final row = await (db.select(
          db.categories,
        )..where((tbl) => tbl.id.equals(category.id))).getSingle();
        expect(row.deletedAt, isNotNull);
        expect(row.syncDirty, isFalse);
      },
    );

    test(
      'dirty tombstone push: a locally soft-deleted row pushes its '
      'deletedAt to the server and clears the flag',
      () async {
        final category = await categories.createCategory(
          household.id,
          kind: CategoryKind.chore,
          name: 'Old name',
          icon: 'a',
          color: 1,
        );
        await categories.softDeleteCategory(category.id);

        await engine.pushDirty();

        final serverRow = transport.serverRows['categories']!.singleWhere(
          (row) => row['id'] == category.id,
        );
        expect(serverRow['deleted_at'], isNotNull);
        final localRow = await (db.select(
          db.categories,
        )..where((tbl) => tbl.id.equals(category.id))).getSingle();
        expect(localRow.syncDirty, isFalse);
      },
    );

    test(
      'mid-push re-dirty stays dirty: a local edit arriving during the '
      'network round trip keeps its dirty flag set',
      () async {
        final category = await categories.createCategory(
          household.id,
          kind: CategoryKind.chore,
          name: 'Milk aisle',
          icon: 'a',
          color: 1,
        );
        transport.beforeUpsert = () async {
          await categories.updateCategory(
            category.id,
            name: 'Renamed mid-flight',
          );
        };

        await engine.pushDirty();

        final row = await (db.select(
          db.categories,
        )..where((tbl) => tbl.id.equals(category.id))).getSingle();
        expect(row.syncDirty, isTrue);
        expect(row.name, 'Renamed mid-flight');
      },
    );

    test(
      'cursor advances to the fetched server now() after a successful pull',
      () async {
        transport.now = DateTime.utc(2026, 5, 1, 12);

        await engine.pullSince();

        final settingsRow = await SettingsRepository(db).ensureSettings();
        expect(
          settingsRow.syncLastPulledAt,
          DateTime.utc(2026, 5, 1, 12).toIso8601String(),
        );
      },
    );

    test(
      'cursor stays unchanged if the pull fails partway through (only '
      'advances on a committed pull)',
      () async {
        final throwingEngine = SupabaseSyncEngine(
          db: db,
          transport: _ThrowingPullTransport('chores'),
          settings: SettingsRepository(db),
          householdId: household.id,
        );
        addTearDown(throwingEngine.stop);

        await throwingEngine.pullSince();

        final settingsRow = await SettingsRepository(db).ensureSettings();
        expect(settingsRow.syncLastPulledAt, isNull);
      },
    );

    test(
      'a pull whose membership probe comes back false clears the sync link '
      'and records the revocation for the notice (spec '
      'docs/specs/household-lifecycle.md §3.5)',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        transport.membershipPresent = false;

        await engine.pullSince();

        final row = await settings.ensureSettings();
        expect(row.syncHouseholdId, isNull);
        expect(row.membershipRevoked, isTrue);
        // The probe short-circuits BEFORE any table fetch or cursor
        // advance -- not merely "ends up in the right state" via some
        // later step undoing a fetch that already happened.
        expect(transport.serverNowCalls, 0);
      },
    );

    test(
      'a pull whose membership probe THROWS (transient network failure) '
      'leaves the device linked and unflagged -- retryable, not silently '
      'unlinked (spec docs/specs/household-lifecycle.md §3.5: only an '
      'empty result is a revocation signal, an error is not)',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        final throwingEngine = SupabaseSyncEngine(
          db: db,
          transport: _RevocationProbeFailsTransport(),
          settings: settings,
          householdId: household.id,
        );
        addTearDown(throwingEngine.stop);

        await throwingEngine.pullSince();

        final row = await settings.ensureSettings();
        expect(row.syncHouseholdId, household.id);
        expect(row.membershipRevoked, isFalse);
      },
    );

    test(
      'a pull whose membership probe succeeds leaves the link alone',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        transport.membershipPresent = true;

        await engine.pullSince();

        final row = await settings.ensureSettings();
        expect(row.syncHouseholdId, household.id);
        expect(row.membershipRevoked, isFalse);
      },
    );
  });

  group('SupabaseSyncEngine push mechanics', () {
    late AppDatabase db;
    late HouseholdRepository households;
    late Household household;
    late FakeSyncTransport transport;
    late SupabaseSyncEngine engine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      households = HouseholdRepository(db);
      household = await households.createLocalHousehold('Me');
      transport = FakeSyncTransport();
      engine = SupabaseSyncEngine(
        db: db,
        transport: transport,
        settings: SettingsRepository(db),
        householdId: household.id,
      );
    });

    tearDown(() async {
      engine.stop();
      await db.close();
    });

    test(
      'members push: insert-with-ignore for a new row, then a '
      'granted-columns update propagates a later name change',
      () async {
        await engine.pushDirty();
        final memberId = (await db.select(db.members).getSingle()).id;
        expect(transport.serverRows['members']!.single['name'], 'Me');

        await households.renameMember(memberId, 'Renamed');
        await engine.pushDirty();

        expect(transport.serverRows['members']!.single['name'], 'Renamed');
      },
    );

    test(
      'members push: a soft-deleted member (MemberService.deleteMember, '
      'spec docs/feedback/2026-08-01-ux-audit.md A1) propagates '
      'deleted_at via the granted-columns update',
      () async {
        final second = await households.addMember(
          household.id,
          name: 'Jo',
          color: 1,
        );
        await engine.pushDirty();
        expect(transport.serverRows['members'], hasLength(2));

        await MemberService(
          database: db,
          chores: ChoreRepository(db),
        ).deleteMember(second.id);
        await engine.pushDirty();

        final serverRow = transport.serverRows['members']!.singleWhere(
          (row) => row['id'] == second.id,
        );
        expect(serverRow['deleted_at'], isNotNull);
      },
    );

    test(
      'households push: a plain UPDATE per dirty row (never an upsert)',
      () async {
        await engine.pushDirty();
        expect(
          transport.serverRows['households']!.single['name'],
          household.name,
        );

        // No local rename feature exists yet (spec: households are never
        // locally soft-deleted/renamed in this slice); simulate a
        // hypothetical future one by marking the row dirty directly,
        // exactly like a real write site would (spec §8.1).
        await (db.update(
          db.households,
        )..where((tbl) => tbl.id.equals(household.id))).write(
          const HouseholdsCompanion(
            name: Value('Renamed household'),
            syncDirty: Value(true),
          ),
        );

        await engine.pushDirty();

        expect(
          transport.serverRows['households']!.single['name'],
          'Renamed household',
        );
        final localRow = await (db.select(
          db.households,
        )..where((tbl) => tbl.id.equals(household.id))).getSingle();
        expect(localRow.syncDirty, isFalse);
      },
    );

    test(
      "chore_assignees push denormalizes household_id off the assignee's "
      'chore',
      () async {
        final member = await households.addMember(
          household.id,
          name: 'Jo',
          color: 1,
        );
        final chores = ChoreRepository(db);
        final chore = await chores.createChore(
          householdId: household.id,
          title: 'Dishes',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.fixed,
          assigneeMemberIds: [member.id],
        );

        await engine.pushDirty();

        final assigneeRow = transport.serverRows['chore_assignees']!.single;
        expect(assigneeRow['household_id'], household.id);
        expect(assigneeRow['chore_id'], chore.id);
        expect(assigneeRow['member_id'], member.id);
      },
    );

    test('pushDirty pushes every dirty table in FK order', () async {
      final member = await households.addMember(
        household.id,
        name: 'Jo',
        color: 1,
      );
      final categories = CategoryRepository(db);
      final category = await categories.createCategory(
        household.id,
        kind: CategoryKind.chore,
        name: 'Cleaning',
        icon: 'a',
        color: 1,
      );
      final chores = ChoreRepository(db);
      final chore = await chores.createChore(
        householdId: household.id,
        title: 'Dishes',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [member.id],
        categoryId: category.id,
      );
      await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 8),
      );
      final shopping = ShoppingRepository(db);
      await shopping.addItem(household.id, name: 'Milk');

      await engine.pushDirty();

      expect(transport.pushedTables, [
        'households',
        'members',
        'categories',
        'chores',
        'chore_assignees',
        'chore_occurrences',
        'shopping_items',
      ]);
    });
  });

  group('SupabaseSyncEngine start()/stop() triggers', () {
    late AppDatabase db;
    late HouseholdRepository households;
    late Household household;
    late FakeSyncTransport transport;
    late SupabaseSyncEngine engine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      households = HouseholdRepository(db);
      household = await households.createLocalHousehold('Me');
      transport = FakeSyncTransport();
      engine = SupabaseSyncEngine(
        db: db,
        transport: transport,
        settings: SettingsRepository(db),
        householdId: household.id,
        pushDebounce: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      engine.stop();
      await db.close();
    });

    test('stop() is idempotent, including when never started', () {
      engine
        ..stop()
        ..stop();
    });

    test(
      'start() schedules a debounced push after a local write to a synced '
      'table',
      () async {
        engine.start();
        // Let the initial start()-triggered pull settle before clearing
        // what it touched, so only the write below is under test.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        transport.pushedTables.clear();

        final shopping = ShoppingRepository(db);
        await shopping.addItem(household.id, name: 'Milk');

        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(transport.pushedTables, contains('shopping_items'));
      },
    );

    test(
      'start() schedules a pull when the transport reports a household '
      'change (payload ignored; data comes from the pull path)',
      () async {
        engine.start();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // The initial start()-triggered pull already advanced the cursor
        // to `transport.now`; the server clock must move on so this new
        // row's `updated_at` is strictly after that cursor (spec §8.3:
        // "rows with updated_at > syncLastPulledAt").
        transport.now = transport.now.add(const Duration(minutes: 1));
        transport.serverRows['categories']!.add({
          'id': 'server-category',
          'household_id': household.id,
          'kind': 'chore',
          'name': 'From realtime',
          'icon': 'a',
          'color': 1,
          'sort_order': 0,
          'created_at': transport.now.toIso8601String(),
          'updated_at': transport.now.toIso8601String(),
          'deleted_at': null,
        });
        transport.emitChange();

        await Future<void>.delayed(const Duration(milliseconds: 50));

        final row = await (db.select(
          db.categories,
        )..where((tbl) => tbl.id.equals('server-category'))).getSingleOrNull();
        expect(row, isNotNull);
      },
    );
  });

  // Spec `docs/specs/sync-freshness.md` §2.2: the foreground safety-net
  // poll. §2.1's re-subscribe pull needs no test of its own here -- the
  // transport emits a re-subscribe on the SAME stream as a live change
  // (that is the whole design), so the realtime test above already covers
  // the engine half; the Supabase-side `subscribe` callback is the part
  // this suite has no seam for.
  group('SupabaseSyncEngine foreground poll', () {
    late AppDatabase db;
    late FakeSyncTransport transport;
    late Household household;
    late SupabaseSyncEngine engine;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      household = await HouseholdRepository(db).createLocalHousehold('Home');
      transport = FakeSyncTransport();
      engine = SupabaseSyncEngine(
        db: db,
        transport: transport,
        settings: SettingsRepository(db),
        householdId: household.id,
        pushDebounce: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 30),
      );
    });

    tearDown(() async {
      engine.stop();
      await db.close();
    });

    /// Pulls STARTED during [duration] -- every `pullSince` reads the
    /// server clock first. Measured as a delta, not an absolute: `start()`'s
    /// own push-then-pull and the debounced write-listener push (fired by
    /// the household rows `setUp` seeds) pull too.
    Future<int> pullsDuring(Duration duration) async {
      final before = transport.serverNowCalls;
      await Future<void>.delayed(duration);
      return transport.serverNowCalls - before;
    }

    /// Waits out `start()`'s initial push/pull AND the debounced push the
    /// seeded rows trigger, so afterwards only the poll is still moving.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 150));

    test('polls pullSince repeatedly while started and foregrounded', () async {
      engine.start();
      await settle();

      // 100ms at a 30ms interval is 3 ticks nominally; assert the floor so
      // scheduler jitter on a loaded CI machine cannot flake this.
      expect(
        await pullsDuring(const Duration(milliseconds: 100)),
        greaterThanOrEqualTo(2),
      );
    });

    test('pauseBackgroundWork stops the poll; resume re-arms it', () async {
      engine.start();
      await settle();

      engine.pauseBackgroundWork();
      // Let a tick already in flight when pause landed finish first.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        await pullsDuring(const Duration(milliseconds: 100)),
        0,
        reason: 'a backgrounded app must not keep waking the network',
      );

      engine.resumeBackgroundWork();
      expect(
        await pullsDuring(const Duration(milliseconds: 100)),
        greaterThanOrEqualTo(2),
      );
    });

    test('stop() cancels the poll', () async {
      engine.start();
      await settle();
      engine.stop();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(await pullsDuring(const Duration(milliseconds: 100)), 0);
    });

    test('resumeBackgroundWork before start() leaves no stray timer', () async {
      engine.resumeBackgroundWork();

      expect(await pullsDuring(const Duration(milliseconds: 100)), 0);
    });
  });
}
