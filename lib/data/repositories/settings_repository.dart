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
  /// `HouseholdRepository.createLocalHousehold`.
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
        membershipRevoked: false,
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

  /// Links this device to [householdId] as of [linkedAt] (spec
  /// `docs/specs/sync-backend.md` §7.1): sets `syncHouseholdId` and
  /// `syncLinkedAt` together -- "linked" ⇔ `syncHouseholdId != null`. This
  /// is the single funnel every re-link path goes through --
  /// `HouseholdLinkService.adopt` and both `HouseholdJoinService` entry
  /// points -- so it is also where `membershipRevoked` (spec §3.5) must be
  /// cleared: that flag is otherwise sticky (only the user tapping through
  /// the notice clears it), and a device that was removed, unlinked, and
  /// then joins a DIFFERENT household by invite code would keep showing
  /// the stale "you're no longer part of this household" banner while
  /// syncing correctly against the new one -- and a wipe-checked tap on
  /// that stale banner would reset local data against the household just
  /// joined. `clearSyncLink` deliberately does NOT clear this flag itself
  /// (a manual disconnect is not an acknowledgement of the notice); this
  /// write is what makes the flag symmetric overall -- set once by
  /// revocation, cleared once linking (re)succeeds.
  Future<void> setSyncLinked({
    required String householdId,
    required DateTime linkedAt,
  }) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        syncHouseholdId: Value(householdId),
        syncLinkedAt: Value(linkedAt.toUtc().toIso8601String()),
        membershipRevoked: const Value(false),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the user's manual theme override (spec
  /// `docs/feedback/2026-08-01-field-feedback.md` G2): `'light'` or
  /// `'dark'`, read by `themeModeProvider` (`lib/app/providers.dart`) to
  /// drive `MaterialApp.themeMode`. Passing `null` clears it back to
  /// following the OS theme -- this is an explicit `null` write, not "leave
  /// unchanged", so [Value] wraps it unconditionally.
  Future<void> setThemeMode(String? themeMode) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        themeMode: Value(themeMode),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Sets the pull cursor (spec `docs/specs/sync-backend.md` §8.1/8.3):
  /// [at] is the server-clock timestamp fetched via the `server_now()` RPC
  /// in the SAME round trip as the pull it's paired with -- never the
  /// device clock. Called by `SupabaseSyncEngine.pullSince` only AFTER its
  /// pull transaction has committed (spec §8.3: "set `syncLastPulledAt` to
  /// the fetched server now() only after the transaction commits").
  Future<void> setSyncLastPulledAt(DateTime at) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        syncLastPulledAt: Value(at.toUtc().toIso8601String()),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Records [code] as the invite code most recently submitted -- and
  /// accepted by the server -- on the welcome-join subpage's code-entry step
  /// (spec `docs/specs/onboarding-v2.md` §1), or clears it when [code] is
  /// `null`.
  ///
  /// `null` means "clear it", never "leave it unchanged", so [Value] wraps
  /// [code] unconditionally. The stored value is read only as a prefill for
  /// that code field (`WelcomeJoinPage._prefillPendingCode`) and never
  /// drives routing -- see [DeviceSettings.pendingJoinCode]'s own doc
  /// comment. Cleared by `HouseholdJoinService.joinFresh` on a successful
  /// join and by `HouseholdCreateService.create` when the user starts a new
  /// household instead of finishing a join.
  Future<void> setPendingJoinCode(String? code) async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        pendingJoinCode: Value(code),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Disconnects this device from its currently linked household (spec
  /// `docs/feedback/2026-08-07-field-feedback.md` A1.2 -- the exit this app
  /// never had): clears `syncHouseholdId` and `syncLinkedAt` TOGETHER (spec
  /// `docs/specs/sync-backend.md` §7.1's "always set/cleared together"
  /// invariant, honored in both directions), plus the pull cursor
  /// `syncLastPulledAt` (spec §8.1) so a future re-link starts pulling from
  /// scratch rather than resuming a stale cursor.
  ///
  /// Also nulls every local `members.userId` (spec
  /// `docs/specs/household-lifecycle.md` §3.1 G-A): claim state is
  /// meaningless in a local-only household, and a stale value left behind
  /// by an earlier pull would keep those profiles undeletable forever.
  /// Deliberately does NOT mark the members rows `syncDirty` -- `user_id`
  /// is server-owned and is not in the client's UPDATE grant.
  ///
  /// This is NOT a delete: every other local row (households, members,
  /// categories, chores, shopping items, ...) is left exactly as it is, and
  /// nothing on the server is touched -- the server's copy of `user_id`
  /// (only this device's local copy is cleared here) is untouched, so
  /// reconnecting later (spec §7.6) still works. Called by
  /// `HouseholdLinkService.disconnect`
  /// (`lib/application/household_link_service.dart`).
  Future<void> clearSyncLink() async {
    await ensureSettings();
    await db.transaction(() async {
      await (db.update(
        db.settings,
      )..where((tbl) => tbl.id.equals(deviceId))).write(
        SettingsCompanion(
          syncHouseholdId: const Value(null),
          syncLinkedAt: const Value(null),
          syncLastPulledAt: const Value(null),
          updatedAt: Value(_isoNow()),
        ),
      );
      // No WHERE clause: safe only because this app has exactly one
      // household per device, so every local member row belongs to the
      // household being unlinked. Add a household/household-membership
      // filter here before this app ever supports more than one household
      // per device.
      await db
          .update(db.members)
          .write(const MembersCompanion(userId: Value(null)));
    });
  }

  /// Records that this device's household membership was revoked
  /// server-side, so the UI can explain it once (spec
  /// `docs/specs/household-lifecycle.md` §3.5).
  Future<void> setMembershipRevoked() async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        membershipRevoked: const Value(true),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Clears the revocation flag once the user has acknowledged the notice.
  Future<void> clearMembershipRevoked() async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        membershipRevoked: const Value(false),
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
