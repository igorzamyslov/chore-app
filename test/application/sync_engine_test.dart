/// Tests `SupabaseSyncEngine`/`NoopSyncEngine` (spec
/// `docs/specs/sync-backend.md` §8) against a real in-memory `AppDatabase`
/// and the [FakeSyncTransport] fake -- no live Supabase involved (spec
/// §8.4). Covers the full LWW matrix, the mid-push re-dirty guard, the
/// cursor's commit-only advance, the members/households push special cases,
/// FK ordering, and the start()/stop() triggers.
library;

import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/application/member_service.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/settings/fake_household_gateway.dart';
import 'fake_sync_transport.dart';

/// Collects the sources [AppLog] receives, in order.
class _RecordingSink implements ErrorLogSink {
  final List<String> sources = [];

  @override
  Future<void> record({
    required String source,
    required ScrubbedError error,
  }) async {
    sources.add(source);
  }
}

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
      'pulled timestamps are normalised to the local format: a Postgres '
      '"+00:00" stamp is stored as the same instant with a "Z" suffix '
      '(technical review 2026-10-06 #4, so local and pulled stamps compare '
      'lexically)',
      () async {
        transport.serverRows['categories']!.add({
          'id': 'server-category',
          'household_id': household.id,
          'kind': 'chore',
          'name': 'From server',
          'icon': 'b',
          'color': 2,
          'sort_order': 0,
          'created_at': '2026-05-01T10:00:00.123456+00:00',
          'updated_at': '2026-06-01T10:00:00.5+00:00',
          'deleted_at': '2026-06-02T10:00:00+02:00',
        });

        await engine.pullSince();

        final row = await (db.select(
          db.categories,
        )..where((tbl) => tbl.id.equals('server-category'))).getSingle();
        expect(row.createdAt, '2026-05-01T10:00:00.123456Z');
        expect(row.updatedAt, '2026-06-01T10:00:00.500Z');
        expect(row.deletedAt, '2026-06-02T08:00:00.000Z');
      },
    );

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
      'a failing push is recorded through AppLog as sync.pushDirty and a '
      'failing pull as sync.pullSince (spec '
      'docs/specs/client-error-reporting.md §3.4)',
      () async {
        final sink = _RecordingSink();
        AppLog.attach(sink);
        addTearDown(AppLog.detach);

        await ShoppingRepository(db).addItem(household.id, name: 'Milk');
        transport.beforeUpsert = () async {
          throw Exception('simulated push failure');
        };
        await engine.pushDirty();
        await pumpEventQueue();
        expect(sink.sources, contains('sync.pushDirty'));
        expect(sink.sources, isNot(contains('sync.pullSince')));

        final throwingEngine = SupabaseSyncEngine(
          db: db,
          transport: _ThrowingPullTransport('chores'),
          settings: SettingsRepository(db),
          householdId: household.id,
        );
        addTearDown(throwingEngine.stop);
        await throwingEngine.pullSince();
        await pumpEventQueue();
        expect(sink.sources, contains('sync.pullSince'));
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

    test(
      'refreshNow reports false when its own pull discovers revocation '
      '(smaller fix 4): a deliberate pull-to-refresh must not answer '
      '"yes, working" at the exact moment the device is cut off, right '
      'before the refresh affordance disappears because it is gated on '
      'linked state',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        transport.membershipPresent = false;

        final result = await engine.refreshNow();

        expect(result, isFalse);
        final row = await settings.ensureSettings();
        expect(row.syncHouseholdId, isNull);
        expect(row.membershipRevoked, isTrue);
      },
    );

    test(
      'refreshNow still reports true for an ordinary successful refresh '
      '(membership present)',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        transport.membershipPresent = true;

        final result = await engine.refreshNow();

        expect(result, isTrue);
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
          // Unclaimed target, so the claim-state routing (spec
          // `docs/specs/household-lifecycle.md` §3.2) never reaches the
          // gateway -- this test is about the local soft-delete's push.
          gateway: FakeHouseholdGateway(),
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

    test(
      'foreground poll retries a push that failed earlier, without '
      'waiting for another local write or app resume (B-6, '
      'docs/backlog.md)',
      () async {
        var upsertAttempts = 0;
        transport.beforeUpsert = () async {
          upsertAttempts++;
          if (upsertAttempts == 1) {
            // Simulates the exact B-6 scenario: connectivity drops during
            // the debounced push that follows a local write.
            throw Exception('simulated connectivity drop');
          }
        };

        // This test needs to observe the window BETWEEN the failed
        // debounced push and the first retry, so it drives its own engine
        // through the same constructor seam the group's setUp uses, with
        // the poll spaced far enough from the 20ms debounce that the
        // pre-retry state is genuinely observable. At the group's 30ms
        // interval the first tick lands before any such check could run,
        // which would leave the test asserting the absence of the very
        // retry it exists to prove.
        final retryEngine = SupabaseSyncEngine(
          db: db,
          transport: transport,
          settings: SettingsRepository(db),
          householdId: household.id,
          pushDebounce: const Duration(milliseconds: 20),
          pollInterval: const Duration(milliseconds: 200),
        );
        addTearDown(retryEngine.stop);

        retryEngine.start();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await ShoppingRepository(db).addItem(household.id, name: 'Milk');

        // Let the 20ms debounced push fire and fail against the simulated
        // drop -- the row must still be dirty afterward, and nothing must
        // have reached the fake server. This is B-6's premise: without the
        // retry, a write made as connectivity drops just sits here.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(
          transport.serverRows['shopping_items'],
          isEmpty,
          reason: 'the first push attempt was made to fail on purpose',
        );
        final stillDirty = await (db.select(
          db.shoppingItems,
        )..where((tbl) => tbl.name.equals('Milk'))).getSingle();
        expect(stillDirty.syncDirty, isTrue);

        // The 200ms foreground poll must now retry it on its own -- no
        // further local write, no resume.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          upsertAttempts,
          greaterThanOrEqualTo(2),
          reason:
              'the first attempt was failed on purpose, so a second one can '
              'only have come from the poll. It also proves the row was '
              'still dirty when that tick ran: FakeSyncTransport.upsertRows '
              'returns before calling beforeUpsert when there is nothing '
              'to push, so the hook is unreachable with a clean table',
        );
        expect(
          transport.serverRows['shopping_items']!.any(
            (row) => row['name'] == 'Milk',
          ),
          isTrue,
          reason:
              'the foreground safety-net poll must retry a dirty row left '
              'over from an earlier failed push (B-6) -- before this fix '
              'only pull was retried on a timer',
        );
      },
    );

    test(
      'foreground poll still pulls even when the push half keeps '
      'failing forever -- a permanently-stuck dirty row must not '
      'silence pull too (B-6, docs/backlog.md)',
      () async {
        transport.beforeUpsert = () async {
          throw Exception('simulated permanent rejection, e.g. a 42501');
        };

        engine.start();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await ShoppingRepository(db).addItem(household.id, name: 'Milk');

        // Let the debounced push fail (and keep failing -- beforeUpsert
        // always throws), then measure whether pulls keep happening on
        // the poll's own cadence regardless.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final before = transport.serverNowCalls;
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          transport.serverNowCalls,
          greaterThan(before),
          reason:
              'a poll tick must ALWAYS pull, whether or not the push '
              'half succeeded -- pointing the poll timer straight at '
              'pushDirty() would make the pull conditional on push '
              'success and turn one stuck row into a total pull '
              'blackout, exactly what sync-freshness.md §2.2 exists to '
              'prevent',
        );
      },
    );
  });

  group('SupabaseSyncEngine hard-delete tombstones (spec §8.6)', () {
    late AppDatabase db;
    late HouseholdRepository households;
    late ChoreRepository chores;
    late Household household;
    late FakeSyncTransport transport;
    late SupabaseSyncEngine engine;
    late String owner;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      households = HouseholdRepository(db);
      chores = ChoreRepository(db);
      household = await households.createLocalHousehold('Me');
      owner = (await db.select(db.members).getSingle()).id;
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

    Future<Chore> fixedChore() => chores.createChore(
      householdId: household.id,
      title: 'T',
      startDate: PlainDate(2026, 1, 1),
      assignmentMode: AssignmentMode.fixed,
      assigneeMemberIds: [owner],
    );

    Future<List<SyncTombstone>> outbox() => db.select(db.syncTombstones).get();

    /// Makes the fake server's `updated_at` newer than the pull cursor the
    /// push left behind, so the next pull sees a row changed on the server.
    void serverTouched(Map<String, Object?> row, {required String? deletedAt}) {
      transport.now = DateTime.utc(2026, 2);
      row['deleted_at'] = deletedAt;
      row['updated_at'] = transport.now.toIso8601String();
    }

    test(
      'pushed assignee and occurrence rows carry deleted_at: null',
      () async {
        final chore = await fixedChore();
        await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 5),
        );

        await engine.pushDirty();

        for (final table in const ['chore_assignees', 'chore_occurrences']) {
          final row = transport.serverRows[table]!.single;
          expect(row.containsKey('deleted_at'), isTrue, reason: table);
          expect(row['deleted_at'], isNull, reason: table);
        }
      },
    );

    test('push marks a deleted occurrence on the server and empties the '
        'outbox', () async {
      final chore = await fixedChore();
      final occurrence = await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 5),
      );
      await engine.pushDirty();

      await chores.softDeleteChore(chore.id);
      expect(await outbox(), hasLength(1));
      transport.now = DateTime.utc(2026, 3);
      await engine.pushDirty();

      expect(transport.markDeletedCalls, hasLength(1));
      final call = transport.markDeletedCalls.single;
      expect(call.table, 'chore_occurrences');
      // The status match is load-bearing (technical review 2026-10-06 #1):
      // an occurrence tombstone means "the PENDING row is gone", so it
      // must never land on a row another device has since completed.
      expect(call.match, {'id': occurrence.id, 'status': 'pending'});
      final serverRow = transport.serverRows['chore_occurrences']!.single;
      expect(serverRow['deleted_at'], call.deletedAt);
      expect(serverRow['updated_at'], DateTime.utc(2026, 3).toIso8601String());
      expect(await outbox(), isEmpty);
    });

    test('push marks a removed assignee by its composite key', () async {
      final other = await households.addMember(
        household.id,
        name: 'Jo',
        color: 1,
      );
      final third = await households.addMember(
        household.id,
        name: 'T3',
        color: 2,
      );
      final chore = await chores.createChore(
        householdId: household.id,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.rotation,
        assigneeMemberIds: [owner, other.id, third.id],
      );
      await engine.pushDirty();

      await chores.updateChore(chore.id, assigneeMemberIds: [owner, third.id]);
      await engine.pushDirty();

      expect(transport.markDeletedCalls, hasLength(1));
      expect(transport.markDeletedCalls.single.table, 'chore_assignees');
      expect(transport.markDeletedCalls.single.match, {
        'chore_id': chore.id,
        'member_id': other.id,
      });
      final removed = transport.serverRows['chore_assignees']!.singleWhere(
        (row) => row['member_id'] == other.id,
      );
      expect(removed['deleted_at'], isNotNull);
      expect(await outbox(), isEmpty);
    });

    test(
      'a tombstone for a never-pushed row is harmless (zero matches)',
      () async {
        final chore = await fixedChore();
        await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 5),
        );
        await chores.softDeleteChore(chore.id);

        await engine.pushDirty();

        expect(transport.markDeletedCalls, hasLength(1));
        expect(transport.serverRows['chore_occurrences'], isEmpty);
        expect(await outbox(), isEmpty);
      },
    );

    test(
      'a re-added assignee drops its tombstone with no network call',
      () async {
        final b = await households.addMember(household.id, name: 'B', color: 1);
        final c = await households.addMember(household.id, name: 'C', color: 2);
        final chore = await chores.createChore(
          householdId: household.id,
          title: 'T',
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.rotation,
          assigneeMemberIds: [owner, b.id],
        );
        await engine.pushDirty();

        await chores.updateChore(chore.id, assigneeMemberIds: [owner, c.id]);
        await chores.updateChore(chore.id, assigneeMemberIds: [owner, b.id]);
        // Tombstones: b (first edit), c (second edit). b is back locally.
        expect(await outbox(), hasLength(2));

        await engine.pushDirty();

        expect(transport.markDeletedCalls, hasLength(1));
        expect(transport.markDeletedCalls.single.match['member_id'], c.id);
        expect(await outbox(), isEmpty);
        final reAdded = transport.serverRows['chore_assignees']!.singleWhere(
          (row) => row['member_id'] == b.id,
        );
        expect(reAdded['deleted_at'], isNull);
      },
    );

    test(
      'pull of a tombstoned occurrence deletes the clean local row',
      () async {
        final chore = await fixedChore();
        final occurrence = await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 5),
        );
        await engine.pushDirty();
        serverTouched(
          transport.serverRows['chore_occurrences']!.single,
          deletedAt: '2026-02-01T00:00:00.000Z',
        );

        await engine.pullSince();

        expect(await chores.getOccurrence(occurrence.id), isNull);
        expect(await outbox(), isEmpty);
      },
    );

    test('pull of a tombstoned occurrence keeps a locally dirty row', () async {
      final chore = await fixedChore();
      final occurrence = await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 5),
      );
      await engine.pushDirty();
      await (db.update(db.choreOccurrences)
            ..where((tbl) => tbl.id.equals(occurrence.id)))
          .write(const ChoreOccurrencesCompanion(syncDirty: Value(true)));
      serverTouched(
        transport.serverRows['chore_occurrences']!.single,
        deletedAt: '2026-02-01T00:00:00.000Z',
      );

      await engine.pullSince();

      expect(await chores.getOccurrence(occurrence.id), isNotNull);
    });

    test(
      'pull of a tombstone for a locally DONE occurrence leaves it alone '
      '(technical review 2026-10-06 #1: a tombstone only kills the pending '
      'row)',
      () async {
        final chore = await fixedChore();
        final occurrence = await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 5),
        );
        await engine.pushDirty();
        await chores.closeOccurrence(
          occurrence.id,
          status: OccurrenceStatus.done,
          closedOn: PlainDate(2026, 1, 5),
          completedBy: owner,
        );
        await engine.pushDirty();
        // The row is clean (just pushed) AND done; a tombstone now arrives
        // for its id from a device that deleted it while it was pending.
        serverTouched(
          transport.serverRows['chore_occurrences']!.single,
          deletedAt: '2026-02-01T00:00:00.000Z',
        );

        await engine.pullSince();

        final kept = await chores.getOccurrence(occurrence.id);
        expect(kept, isNotNull);
        expect(kept!.status, OccurrenceStatus.done);
      },
    );

    test(
      'the completion race from the 2026-10-06 review (#1): A completes O '
      'and pushes, B tombstones O and pushes, A pulls -- A keeps O as done '
      'and B gets the completion back',
      () async {
        // Device A is the group's fixture; device B is a second database
        // sharing the same fake server.
        final dbB = AppDatabase(NativeDatabase.memory());
        addTearDown(dbB.close);
        final choresB = ChoreRepository(dbB);
        final engineB = SupabaseSyncEngine(
          db: dbB,
          transport: transport,
          settings: SettingsRepository(dbB),
          householdId: household.id,
        );
        addTearDown(engineB.stop);

        final chore = await fixedChore();
        final occurrence = await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 5),
        );
        await engine.pushDirty();
        await engineB.pullSince();
        expect(await choresB.getOccurrence(occurrence.id), isNotNull);

        // A completes O (and gets the next occurrence), pushes first.
        transport.now = DateTime.utc(2026, 1, 6);
        await chores.closeOccurrence(
          occurrence.id,
          status: OccurrenceStatus.done,
          closedOn: PlainDate(2026, 1, 5),
          completedBy: owner,
        );
        await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 12),
        );
        await engine.pushDirty();

        // B, not having pulled yet, deletes the chore: a local hard delete
        // of its (still pending, on B) occurrence O plus a tombstone.
        transport.now = DateTime.utc(2026, 1, 7);
        await choresB.softDeleteChore(chore.id);
        await engineB.pushDirty();

        final serverO = transport.serverRows['chore_occurrences']!.singleWhere(
          (row) => row['id'] == occurrence.id,
        );
        expect(
          serverO['deleted_at'],
          isNull,
          reason: 'the tombstone matched on status = pending; O is done',
        );

        transport.now = DateTime.utc(2026, 1, 8);
        await engine.pullSince();
        final onA = await chores.getOccurrence(occurrence.id);
        expect(onA, isNotNull);
        expect(onA!.status, OccurrenceStatus.done);

        await engineB.pullSince();
        final onB = await choresB.getOccurrence(occurrence.id);
        expect(onB, isNotNull, reason: 'B pulls the completion back');
        expect(onB!.status, OccurrenceStatus.done);
      },
    );

    test('pull of a tombstoned assignee deletes it locally', () async {
      final b = await households.addMember(household.id, name: 'B', color: 1);
      final chore = await chores.createChore(
        householdId: household.id,
        title: 'T',
        startDate: PlainDate(2026, 1, 1),
        assignmentMode: AssignmentMode.rotation,
        assigneeMemberIds: [owner, b.id],
      );
      await engine.pushDirty();
      serverTouched(
        transport.serverRows['chore_assignees']!.singleWhere(
          (row) => row['member_id'] == b.id,
        ),
        deletedAt: '2026-02-01T00:00:00.000Z',
      );

      await engine.pullSince();

      final left = await (db.select(
        db.choreAssignees,
      )..where((tbl) => tbl.choreId.equals(chore.id))).get();
      expect(left.map((row) => row.memberId), [owner]);
    });

    test(
      'ghost repair keeps the latest-DUE pending occurrence regardless of '
      'updatedAt (technical review 2026-10-06 #4: the survivor key uses '
      'only fields both devices see identically, spec §8.7)',
      () async {
        final chore = await fixedChore();
        final survivor = await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 3, 1),
        );
        final ghost = await chores.insertOccurrence(
          choreId: chore.id,
          dueDate: PlainDate(2026, 1, 1),
        );
        Future<void> stamp(String id, String updatedAt) =>
            (db.update(db.choreOccurrences)..where((tbl) => tbl.id.equals(id)))
                .write(ChoreOccurrencesCompanion(updatedAt: Value(updatedAt)));
        // The earlier-due row was written LATER: under the old
        // updatedAt-first key it would have won, and a second device whose
        // clock disagrees would have picked the other one -- two devices
        // tombstoning each other's survivor until no pending row is left.
        await stamp(survivor.id, '2026-01-01T00:00:00.000Z');
        await stamp(ghost.id, '2026-01-02T00:00:00.000Z');

        await engine.pullSince();

        final pending = await chores.pendingOccurrenceOf(chore.id);
        expect(pending!.id, survivor.id);
        final rows = await outbox();
        expect(rows, hasLength(1));
        expect(rows.single.entity, 'chore_occurrences');
        expect(rows.single.rowId, ghost.id);
      },
    );

    test('ghost repair breaks a dueDate tie by the greater id', () async {
      final chore = await fixedChore();
      final a = await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 1),
      );
      final b = await chores.insertOccurrence(
        choreId: chore.id,
        dueDate: PlainDate(2026, 1, 1),
      );
      final expectedSurvivor = a.id.compareTo(b.id) > 0 ? a : b;
      final expectedGhost = identical(expectedSurvivor, a) ? b : a;

      await engine.pullSince();

      expect(
        (await chores.pendingOccurrenceOf(chore.id))!.id,
        expectedSurvivor.id,
      );
      expect((await outbox()).single.rowId, expectedGhost.id);
    });
  });
}
