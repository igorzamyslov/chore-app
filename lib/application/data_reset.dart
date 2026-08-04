/// The B2 "reset app data" operation (spec `docs/specs/polish-round-1.md`
/// B2): wipes every row from every table in one transaction.
library;

import 'package:chore_app/data/db/app_database.dart';

/// Deletes every row from every table, in one transaction, in the FK-safe
/// order the spec spells out: occurrences, assignees, chores, shopping
/// items, categories, members, settings, households.
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
Future<void> resetAppData(AppDatabase database) {
  return database.transaction(() async {
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
