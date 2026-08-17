/// `SyncEngine.refreshNow` (spec `docs/specs/sync-freshness.md` §2.3): a
/// USER-INITIATED sync must report whether it actually worked.
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

  test('refreshNow returns true when both halves succeed', () async {
    expect(await engineWith(FakeSyncTransport()).refreshNow(), isTrue);
  });

  test('refreshNow returns FALSE when the pull half fails', () async {
    expect(await engineWith(_OfflineTransport()).refreshNow(), isFalse);
  });

  test('refreshNow returns FALSE when the push half fails', () async {
    // Seed a dirty row through the repository (a direct companion insert
    // does not go through the dirty-marking write path), so the push
    // actually has something to send and therefore something to fail on.
    await ShoppingRepository(db).addItem(household.id, name: 'Milk');

    expect(await engineWith(_PushFailsTransport()).refreshNow(), isFalse);
  });

  test('pushDirty and pullSince still swallow failures (background contract, '
      'spec sync-backend.md §8.3) -- only refreshNow reports', () async {
    final engine = engineWith(_OfflineTransport());

    // Neither throws, which is exactly why neither can drive a
    // user-facing error.
    await engine.pushDirty();
    await engine.pullSince();
  });

  test('NoopSyncEngine.refreshNow reports success', () async {
    expect(await const NoopSyncEngine().refreshNow(), isTrue);
  });
}
