/// Tests `SyncRepository.watchAnyDirty` (spec
/// `docs/specs/sync-freshness.md` §2.5): the D-5 indicator's "does this
/// device have unsent changes" signal. The rest of `SyncRepository`'s
/// dirty-select/clear methods are already covered indirectly through
/// `test/application/sync_engine_test.dart`; this method gets its own direct
/// test because nothing else exercises it.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/sync_repository.dart';
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
        // createLocalHousehold's own household+member rows start dirty
        // (spec docs/specs/sync-backend.md §8.1: every write marks dirty).
        expect(await repo.watchAnyDirty().first, isTrue);

        for (final table in [
          'households',
          'members',
          'categories',
          'chores',
          'chore_assignees',
          'chore_occurrences',
          'shopping_items',
        ]) {
          await db.customStatement('UPDATE $table SET sync_dirty = 0');
        }
        expect(await repo.watchAnyDirty().first, isFalse);

        // Subscribed BEFORE the write, so this proves reactivity (a fresh
        // `.first` would only prove the query re-reads on demand).
        final nextEmission = repo.watchAnyDirty().skip(1).first;
        await categories.createCategory(
          household.id,
          kind: CategoryKind.chore,
          name: 'Produce',
          icon: 'a',
          color: 1,
        );
        expect(await nextEmission, isTrue);

        await db.close();
      },
    );
  });
}
