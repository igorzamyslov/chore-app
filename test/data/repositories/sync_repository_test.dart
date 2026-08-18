/// Tests `SyncRepository.watchAnyDirty` (spec
/// `docs/specs/sync-freshness.md` §2.5): the D-5 indicator's "does this
/// device have unsent changes" signal. The rest of `SyncRepository`'s
/// dirty-select/clear methods are already covered indirectly through
/// `test/application/sync_engine_test.dart`; this method gets its own direct
/// test because nothing else exercises it.
///
/// Holds ONE subscription across the whole transition sequence rather than
/// awaiting `.first` three times. Two reasons, both learned the hard way:
/// drift caches a query stream by its SQL and replays the last fetched value
/// to a new listener, so a fresh `.first` can hand back a stale answer; and
/// `dirtySinceProvider` -- this method's only caller -- subscribes exactly
/// once for the app's lifetime, so a single subscription is also the shape
/// that actually gets shipped.
///
/// The clearing writes go through `customUpdate` with an explicit `updates:`
/// set, not `customStatement`: drift cannot infer which tables a raw
/// statement touched, so a `customStatement` write notifies nothing and this
/// method would (correctly) never re-emit.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/sync_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('watchAnyDirty', () {
    test(
      'true while ANY synced table has a dirty row, false once none do, '
      'true again on a fresh write',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final households = HouseholdRepository(db);
        final categories = CategoryRepository(db);
        final repo = SyncRepository(db);

        final household = await households.createLocalHousehold('Me');

        final seen = <bool>[];
        final subscription = repo.watchAnyDirty().listen(seen.add);
        await pumpEventQueue();
        // createLocalHousehold's own household+member rows start dirty (spec
        // docs/specs/sync-backend.md §8.1: every write marks dirty).
        expect(seen.last, isTrue);

        for (final table in <TableInfo<Table, dynamic>>[
          db.households,
          db.members,
          db.categories,
          db.chores,
          db.choreAssignees,
          db.choreOccurrences,
          db.shoppingItems,
        ]) {
          await db.customUpdate(
            'UPDATE ${table.actualTableName} SET sync_dirty = 0',
            updates: {table},
          );
        }
        await pumpEventQueue();
        expect(
          seen.last,
          isFalse,
          reason: 'nothing is dirty in any of the seven synced tables',
        );

        await categories.createCategory(
          household.id,
          kind: CategoryKind.chore,
          name: 'Produce',
          icon: 'a',
          color: 1,
        );
        await pumpEventQueue();
        expect(
          seen.last,
          isTrue,
          reason:
              'a write to ANY synced table must re-emit -- categories is '
              'neither the first nor the last branch of the union',
        );

        await subscription.cancel();
        await db.close();
      },
    );
  });
}
