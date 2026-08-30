/// The B2 "reset app data" operation (spec `docs/specs/polish-round-1.md`
/// B2): wipes every row from every table in one transaction.
library;

import 'package:chore_app/data/db/app_database.dart';

/// Deletes every row from every table, in one transaction, in the FK-safe
/// order the spec spells out: reminder snoozes, occurrences, assignees,
/// chores, shopping items, categories, members, settings, households.
///
/// Leaves the database schema itself untouched -- only rows are removed.
/// Wiping the `households` table flips `householdGateProvider`'s stream to
/// `null` on its own (spec `docs/specs/onboarding-v2.md` §2), so the app
/// reactively lands back on the welcome screen -- the TRUE fresh-install
/// state, not a silently re-bootstrapped household. Callers are still
/// responsible for invalidating `settingsProvider` afterwards (in
/// production, `ResetDataTile` does this): its device-settings row (and the
/// first-run banner shown-once flags on it) was also just deleted out from
/// under its already-running watch stream.
///
/// Deliberately does not touch the Supabase session or the scheduled
/// digest notification -- both are the caller's responsibility
/// (`ResetDataTile._confirmAndReset` in production, spec
/// `docs/feedback/2026-08-08-prerelease-audit.md` P3), the same pattern
/// this function already follows for `settingsProvider` invalidation.
/// Keeping this function DB-only means its own tests
/// (`test/application/data_reset_test.dart`) never need an `AuthGateway`
/// or `NotificationScheduler` fake.
Future<void> resetAppData(AppDatabase database) {
  return database.transaction(() async {
    // Before `chore_occurrences`, whose cascade would take these rows out
    // anyway (spec `docs/specs/notifications-n2.md` §4.2) -- explicit
    // because "the wipe deletes every table" is the guarantee this
    // function's own test asserts, and a reader should not have to reason
    // about FK cascades to see that it holds.
    await database.delete(database.reminderSnoozes).go();
    await database.delete(database.choreOccurrences).go();
    await database.delete(database.choreAssignees).go();
    await database.delete(database.chores).go();
    await database.delete(database.shoppingItems).go();
    await database.delete(database.categories).go();
    await database.delete(database.members).go();
    await database.delete(database.settings).go();
    await database.delete(database.households).go();
  });
}
