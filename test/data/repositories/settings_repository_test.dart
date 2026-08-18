import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock {
  _FixedClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration duration) => _now = _now.add(duration);
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;
  late _FixedClock clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = _FixedClock(DateTime.utc(2026));
    repo = SettingsRepository(db, nowUtc: clock.call);
  });

  tearDown(() => db.close());

  test(
    'ensureSettings creates the singleton row with schema defaults',
    () async {
      final settings = await repo.ensureSettings();
      expect(settings.id, SettingsRepository.deviceId);
      expect(settings.digestEnabled, isTrue);
      expect(settings.digestMinutes, 480);

      final rows = await db.select(db.settings).get();
      expect(rows, hasLength(1));
    },
  );

  test('ensureSettings is idempotent', () async {
    final first = await repo.ensureSettings();
    final second = await repo.ensureSettings();
    expect(first.id, second.id);
    expect(first.createdAt, second.createdAt);

    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
  });

  test('watchSettings emits the row, creating it if necessary', () async {
    final emissions = <DeviceSettings>[];
    final sub = repo.watchSettings().listen(emissions.add);
    addTearDown(sub.cancel);

    await pumpEventQueue();
    expect(emissions, hasLength(1));
    expect(emissions.single.digestEnabled, isTrue);
    expect(emissions.single.digestMinutes, 480);
  });

  test('setDigestEnabled updates the flag and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    clock.advance(const Duration(minutes: 5));

    await repo.setDigestEnabled(enabled: false);

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.digestEnabled, isFalse);
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setDigestEnabled implicitly creates the row if missing', () async {
    await repo.setDigestEnabled(enabled: false);
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.digestEnabled, isFalse);
  });

  test('setDigestTime updates the minutes and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    clock.advance(const Duration(minutes: 5));

    await repo.setDigestTime(90);

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.digestMinutes, 90);
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setDigestTime rejects out-of-range values', () async {
    await expectLater(() => repo.setDigestTime(-1), throwsArgumentError);
    await expectLater(() => repo.setDigestTime(1440), throwsArgumentError);

    // Neither rejected call created the row as a side effect.
    final rows = await db.select(db.settings).get();
    expect(rows, isEmpty);
  });

  test('setDigestTime accepts the boundary values 0 and 1439', () async {
    await repo.setDigestTime(0);
    var row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.digestMinutes, 0);

    await repo.setDigestTime(1439);
    row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.digestMinutes, 1439);
  });

  test('setActingMember sets the id and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    expect(created.actingMemberId, isNull);
    clock.advance(const Duration(minutes: 5));

    await repo.setActingMember('member-1');

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.actingMemberId, 'member-1');
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setActingMember(null) clears a previously-set id', () async {
    await repo.setActingMember('member-1');
    var row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.actingMemberId, 'member-1');

    await repo.setActingMember(null);
    row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.actingMemberId, isNull);
  });

  test('setActingMember implicitly creates the row if missing', () async {
    await repo.setActingMember('member-1');
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.actingMemberId, 'member-1');
  });

  test(
    'watchSettings emits an updated value after setActingMember',
    () async {
      final emissions = <String?>[];
      final sub = repo.watchSettings().listen(
        (settings) => emissions.add(settings.actingMemberId),
      );
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await repo.setActingMember('member-1');
      await pumpEventQueue();

      expect(emissions.last, 'member-1');
    },
  );

  test('setLocale sets the value and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    expect(created.locale, isNull);
    clock.advance(const Duration(minutes: 5));

    await repo.setLocale('de');

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.locale, 'de');
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setLocale(null) clears a previously-set value', () async {
    await repo.setLocale('en');
    var row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.locale, 'en');

    await repo.setLocale(null);
    row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.locale, isNull);
  });

  test('setLocale implicitly creates the row if missing', () async {
    await repo.setLocale('de');
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.locale, 'de');
  });

  test('watchSettings emits an updated value after setLocale', () async {
    final emissions = <String?>[];
    final sub = repo.watchSettings().listen(
      (settings) => emissions.add(settings.locale),
    );
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await repo.setLocale('de');
    await pumpEventQueue();

    expect(emissions.last, 'de');
  });

  test('setThemeMode sets the value and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    expect(created.themeMode, isNull);
    clock.advance(const Duration(minutes: 5));

    await repo.setThemeMode('dark');

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.themeMode, 'dark');
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setThemeMode(null) clears a previously-set value', () async {
    await repo.setThemeMode('light');
    var row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.themeMode, 'light');

    await repo.setThemeMode(null);
    row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.themeMode, isNull);
  });

  test('setThemeMode implicitly creates the row if missing', () async {
    await repo.setThemeMode('dark');
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.themeMode, 'dark');
  });

  test('watchSettings emits an updated value after setThemeMode', () async {
    final emissions = <String?>[];
    final sub = repo.watchSettings().listen(
      (settings) => emissions.add(settings.themeMode),
    );
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await repo.setThemeMode('dark');
    await pumpEventQueue();

    expect(emissions.last, 'dark');
  });

  test(
    'setSyncLinked sets both syncHouseholdId and syncLinkedAt together, and '
    'bumps updated_at',
    () async {
      final created = await repo.ensureSettings();
      expect(created.syncHouseholdId, isNull);
      expect(created.syncLinkedAt, isNull);
      clock.advance(const Duration(minutes: 5));
      final linkedAt = DateTime.utc(2026, 2);

      await repo.setSyncLinked(householdId: 'household-1', linkedAt: linkedAt);

      final updated =
          await (db.select(
                db.settings,
              )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId)))
              .getSingle();
      expect(updated.syncHouseholdId, 'household-1');
      expect(updated.syncLinkedAt, linkedAt.toIso8601String());
      expect(updated.updatedAt, isNot(created.updatedAt));
    },
  );

  test('setSyncLinked implicitly creates the row if missing', () async {
    await repo.setSyncLinked(
      householdId: 'household-1',
      linkedAt: DateTime.utc(2026),
    );
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.syncHouseholdId, 'household-1');
  });

  test(
    'setSyncLinked clears a sticky membershipRevoked flag (blocking fix 2, '
    'spec docs/specs/household-lifecycle.md §3.5): otherwise a device that '
    'was removed, unlinked, and then joins a DIFFERENT household by invite '
    'code would sync correctly while still showing the stale revocation '
    'banner, whose wipe-checked acknowledgement would reset local data '
    'against the household it just joined',
    () async {
      await repo.setMembershipRevoked();
      final revoked = await repo.ensureSettings();
      expect(revoked.membershipRevoked, isTrue);

      await repo.setSyncLinked(
        householdId: 'household-1',
        linkedAt: DateTime.utc(2026),
      );

      final relinked =
          await (db.select(
                db.settings,
              )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId)))
              .getSingle();
      expect(relinked.membershipRevoked, isFalse);
    },
  );

  test('watchSettings emits an updated value after setSyncLinked', () async {
    final emissions = <String?>[];
    final sub = repo.watchSettings().listen(
      (settings) => emissions.add(settings.syncHouseholdId),
    );
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await repo.setSyncLinked(
      householdId: 'household-1',
      linkedAt: DateTime.utc(2026),
    );
    await pumpEventQueue();

    expect(emissions.last, 'household-1');
  });

  test(
    'clearSyncLink clears syncHouseholdId, syncLinkedAt, AND '
    'syncLastPulledAt together, and bumps updated_at',
    () async {
      await repo.setSyncLinked(
        householdId: 'household-1',
        linkedAt: DateTime.utc(2026, 2),
      );
      await repo.setSyncLastPulledAt(DateTime.utc(2026, 3));
      final linked =
          await (db.select(
                db.settings,
              )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId)))
              .getSingle();
      expect(linked.syncHouseholdId, isNotNull);
      expect(linked.syncLinkedAt, isNotNull);
      expect(linked.syncLastPulledAt, isNotNull);
      clock.advance(const Duration(minutes: 5));

      await repo.clearSyncLink();

      final cleared =
          await (db.select(
                db.settings,
              )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId)))
              .getSingle();
      expect(cleared.syncHouseholdId, isNull);
      expect(cleared.syncLinkedAt, isNull);
      expect(cleared.syncLastPulledAt, isNull);
      expect(cleared.updatedAt, isNot(linked.updatedAt));
    },
  );

  test('clearSyncLink implicitly creates the row if missing', () async {
    await repo.clearSyncLink();
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.syncHouseholdId, isNull);
  });

  test('clearSyncLink is a no-op on an already-unlinked row', () async {
    final created = await repo.ensureSettings();
    expect(created.syncHouseholdId, isNull);

    await repo.clearSyncLink();

    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.syncHouseholdId, isNull);
  });

  test(
    'clearSyncLink also nulls every local members.userId, so claim state '
    'from a previous link cannot block deletion in a local-only household '
    '(spec docs/specs/household-lifecycle.md §3.1 G-A)',
    () async {
      final households = HouseholdRepository(db);
      final settings = SettingsRepository(db);
      final household = await households.createLocalHousehold('Me');
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();

      // Simulate a pulled, claimed row: a real pull full-row-replaces with
      // syncDirty: false (see lib/data/sync/row_mappers.dart), which a bare
      // local write (as createLocalHousehold performs) does not.
      await (db.update(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(
          userId: Value('auth-user-1'),
          syncDirty: Value(false),
        ),
      );
      await settings.setSyncLinked(
        householdId: household.id,
        linkedAt: DateTime.utc(2026),
      );

      await settings.clearSyncLink();

      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(after.userId, isNull);
      expect(
        after.syncDirty,
        isFalse,
        reason:
            'user_id is server-owned and not UPDATE-granted; marking the '
            'row dirty would push a column the client may not write',
      );
    },
  );

  test('setPendingJoinCode sets the value and bumps updated_at', () async {
    final created = await repo.ensureSettings();
    expect(created.pendingJoinCode, isNull);
    clock.advance(const Duration(minutes: 5));

    await repo.setPendingJoinCode('ABC12345');

    final updated = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(updated.pendingJoinCode, 'ABC12345');
    expect(updated.updatedAt, isNot(created.updatedAt));
  });

  test('setPendingJoinCode(null) clears a previously-set value', () async {
    await repo.setPendingJoinCode('ABC12345');
    var row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.pendingJoinCode, 'ABC12345');

    await repo.setPendingJoinCode(null);
    row = await (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(SettingsRepository.deviceId))).getSingle();
    expect(row.pendingJoinCode, isNull);
  });

  test('setPendingJoinCode implicitly creates the row if missing', () async {
    await repo.setPendingJoinCode('ABC12345');
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
    expect(rows.single.pendingJoinCode, 'ABC12345');
  });

  test(
    'watchSettings emits an updated value after setPendingJoinCode',
    () async {
      final emissions = <String?>[];
      final sub = repo.watchSettings().listen(
        (settings) => emissions.add(settings.pendingJoinCode),
      );
      addTearDown(sub.cancel);

      await pumpEventQueue();
      await repo.setPendingJoinCode('ABC12345');
      await pumpEventQueue();

      expect(emissions.last, 'ABC12345');
    },
  );
}
