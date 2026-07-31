/// Manages the device-level settings singleton row (spec
/// `docs/specs/notifications.md`): digest notification preferences.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:drift/drift.dart';

/// Repository for the device settings singleton row.
///
/// Unlike every other repository in this layer, there is no household
/// scoping: settings are per-device, and there is exactly one row, keyed by
/// the constant [deviceId].
class SettingsRepository {
  /// Creates a repository backed by [db].
  ///
  /// [nowUtc] is injectable so tests can supply a controllable clock; it
  /// defaults to the real UTC clock. Unlike the other repositories, no
  /// `newId` is needed: the single row's id is always [deviceId].
  SettingsRepository(this.db, {this.nowUtc = _defaultNowUtc});

  /// The constant primary key of the single settings row.
  static const String deviceId = 'device';

  /// The database this repository reads from and writes to.
  final AppDatabase db;

  /// Returns the current UTC time, used for `created_at` / `updated_at`.
  final DateTime Function() nowUtc;

  /// Returns the settings row, inserting it with schema defaults
  /// (`digestEnabled: true`, `digestMinutes: 480`) if it doesn't exist yet.
  ///
  /// Idempotent and race-safe, mirroring
  /// `HouseholdRepository.ensureLocalHousehold`.
  Future<DeviceSettings> ensureSettings() async {
    final existing = await _find();
    if (existing != null) {
      return existing;
    }
    return db.transaction(() async {
      final raceWinner = await _find();
      if (raceWinner != null) {
        return raceWinner;
      }
      final now = _isoNow();
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              id: deviceId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return DeviceSettings(
        id: deviceId,
        digestEnabled: true,
        digestMinutes: 480,
        createdAt: now,
        updatedAt: now,
      );
    });
  }

  /// Watches the settings row, calling [ensureSettings] first so the stream
  /// never has to cope with a "doesn't exist yet" state.
  Stream<DeviceSettings> watchSettings() async* {
    await ensureSettings();
    yield* (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).watchSingle();
  }

  /// Enables or disables the daily digest notification.
  Future<void> setDigestEnabled({required bool enabled}) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        digestEnabled: Value(enabled),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the digest's fire time, as minutes since local midnight.
  ///
  /// Throws [ArgumentError] if [minutesSinceMidnight] is outside `0..1439`.
  Future<void> setDigestTime(int minutesSinceMidnight) async {
    if (minutesSinceMidnight < 0 || minutesSinceMidnight > 1439) {
      throw ArgumentError.value(
        minutesSinceMidnight,
        'minutesSinceMidnight',
        'Must be in 0..1439 (minutes since local midnight)',
      );
    }
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        digestMinutes: Value(minutesSinceMidnight),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the acting member (spec `docs/specs/members-management.md` §2):
  /// [memberId] is read by `actingMemberProvider` (`lib/app/providers.dart`)
  /// whenever it resolves to a current household member. Passing `null`
  /// clears it back to the automatic fallback (first admin, else first
  /// member) — this is an explicit `null` write, not "leave unchanged", so
  /// [Value] wraps it unconditionally.
  Future<void> setActingMember(String? memberId) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        actingMemberId: Value(memberId),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the user's language override (spec `docs/next-session-plan.md`
  /// #5): `'en'` or `'de'`, read by `localeOverrideProvider`
  /// (`lib/app/providers.dart`) to drive `MaterialApp.locale`. Passing
  /// `null` clears it back to following the OS locale — this is an
  /// explicit `null` write, not "leave unchanged", so [Value] wraps it
  /// unconditionally.
  Future<void> setLocale(String? locale) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(locale: Value(locale), updatedAt: Value(_isoNow())),
    );
  }

  /// Records that the first-run name prompt has been shown (spec
  /// `docs/specs/polish-round-1.md` G2) — it never shows again after this,
  /// whether it was completed or dismissed.
  Future<void> markOnboardingNamePromptShown() async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        onboardingNamePromptShownAt: Value(_isoNow()),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Records that the digest pre-permission explainer has been shown (spec
  /// `docs/specs/polish-round-1.md` G3) — shown at most once, right before
  /// the one-shot OS notification-permission dialog.
  Future<void> markDigestPrepromptShown() async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        digestPrepromptShownAt: Value(_isoNow()),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  Future<DeviceSettings?> _find() {
    return (db.select(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).getSingleOrNull();
  }

  String _isoNow() => nowUtc().toIso8601String();
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();
