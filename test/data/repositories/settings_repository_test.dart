import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
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
}
