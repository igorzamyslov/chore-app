/// `SyncEngine.refreshNow` (spec `docs/specs/sync-freshness.md` §2.3): a
/// USER-INITIATED sync must report whether it actually worked -- and, since
/// the 2026-10-06 amendment, HOW it failed (`RefreshOutcome`): `offline`
/// for a failure that will heal on its own, `rejected` for a row the server
/// refused with a 22/23/42-class error, which no retry will fix.
///
/// Regression cover for a gap found by the 2026-08-07 persona walkthrough:
/// pull-to-refresh was wired to `pushDirty()`, whose contract is to swallow
/// every error into a silent retry-later (spec `sync-backend.md` §8.3). The
/// `RefreshIndicator`'s future therefore ALWAYS completed successfully — the
/// spinner span and stopped identically whether the sync worked or the phone
/// was in airplane mode — while §2.3 promised a failure snackbar. `pushDirty`
/// and `pullSince` keep swallowing (right for background triggers);
/// `refreshNow` is the one path that reports.
library;

import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'fake_sync_transport.dart';

/// A transport that always throws — i.e. the pull half fails, as it would
/// with no connectivity. Overrides BOTH `hasMembership` (the revocation
/// probe, called first by `_pullSinceInner`) and `serverNow`: a real
/// no-connectivity device fails every network call, not just the one this
/// fake used to override — leaving `hasMembership` inherited (defaulting to
/// success) would have modeled a device that can reach the revocation
/// probe but nothing else, which is a different (and much stranger)
/// failure than "no connectivity".
class _OfflineTransport extends FakeSyncTransport {
  @override
  Future<bool> hasMembership(String householdId) async =>
      throw Exception('no connectivity');

  @override
  Future<DateTime> serverNow() async => throw Exception('no connectivity');
}

/// A transport whose pushes always throw — the push half fails.
class _PushFailsTransport extends FakeSyncTransport {
  @override
  Future<void> upsertRows(
    String table,
    List<Map<String, Object?>> rows, {
    String? onConflict,
  }) async => throw Exception('no connectivity');
}

/// A transport whose server REJECTS every `shopping_items` upsert with a
/// foreign-key violation (class 23) — the error class a retry never fixes.
class _RejectsShoppingTransport extends FakeSyncTransport {
  @override
  Future<void> upsertRows(
    String table,
    List<Map<String, Object?>> rows, {
    String? onConflict,
  }) async {
    if (table == 'shopping_items') {
      throw const PostgrestException(
        message: 'insert or update violates foreign key constraint',
        code: '23503',
      );
    }
    return super.upsertRows(table, rows, onConflict: onConflict);
  }
}

void main() {
  late AppDatabase db;
  late Household household;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    household = await HouseholdRepository(db).createLocalHousehold('Home');
  });

  tearDown(() async {
    await db.close();
  });

  SupabaseSyncEngine engineWith(SyncTransport transport) => SupabaseSyncEngine(
    db: db,
    transport: transport,
    settings: SettingsRepository(db),
    householdId: household.id,
  );

  test('refreshNow reports ok when both halves succeed', () async {
    expect(
      await engineWith(FakeSyncTransport()).refreshNow(),
      RefreshOutcome.ok,
    );
  });

  test('refreshNow reports offline when the pull half fails', () async {
    expect(
      await engineWith(_OfflineTransport()).refreshNow(),
      RefreshOutcome.offline,
    );
  });

  test('refreshNow reports offline when the push half fails', () async {
    // Seed a dirty row through the repository (a direct companion insert
    // does not go through the dirty-marking write path), so the push
    // actually has something to send and therefore something to fail on.
    await ShoppingRepository(db).addItem(household.id, name: 'Milk');

    expect(
      await engineWith(_PushFailsTransport()).refreshNow(),
      RefreshOutcome.offline,
    );
  });

  test(
    'refreshNow reports rejected when the server refuses a row with a '
    '22/23/42-class error (technical review 2026-10-06 #5) -- and that row '
    'stays dirty for the user to see',
    () async {
      await ShoppingRepository(db).addItem(household.id, name: 'Milk');

      expect(
        await engineWith(_RejectsShoppingTransport()).refreshNow(),
        RefreshOutcome.rejected,
      );
      final item = await db.select(db.shoppingItems).getSingle();
      expect(item.syncDirty, isTrue);
    },
  );

  test(
    'pushDirty and pullSince still swallow failures (background contract, '
    'spec sync-backend.md §8.3) -- only refreshNow reports',
    () async {
      final engine = engineWith(_OfflineTransport());

      // Neither throws, which is exactly why neither can drive a
      // user-facing error.
      await engine.pushDirty();
      await engine.pullSince();
    },
  );

  test('NoopSyncEngine.refreshNow reports ok', () async {
    expect(await const NoopSyncEngine().refreshNow(), RefreshOutcome.ok);
  });
}
