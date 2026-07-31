/// The B2 "reset app data" operation (spec `docs/specs/polish-round-1.md`
/// B2): wipes every row from every table in one transaction.
library;

import 'package:chore_app/data/db/app_database.dart';

/// Deletes every row from every table, in one transaction, in the FK-safe
/// order the spec spells out: occurrences, assignees, chores, shopping
/// items, categories, members, settings, households.
///
/// Leaves the database schema itself untouched -- only rows are removed.
/// Callers are responsible for re-running bootstrap afterwards (in
/// production, by invalidating `bootstrapProvider`) so the app lands back
/// in the fresh-install state, including the first-run banners: their
/// shown-once flags live on the now-deleted `settings` row.
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
