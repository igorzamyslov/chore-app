/// Persona findings F1/F10 (the app-bar status line), the `addedBy` avatar
/// on rows a different member added, and E10 (the "waiting to send" glyph on
/// a dirty row) -- see `docs/specs/ui-shopping.md` amendment 2026-10-06.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

/// A linked, signed-in stand-in: anything that is not [NoopSyncEngine] makes
/// the screens treat the household as linked (`syncEngineProvider`'s own
/// contract), without any network or timer.
class _LinkedEngine implements SyncEngine {
  @override
  Future<void> pushDirty() async {}

  @override
  Future<void> pullSince() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<RefreshOutcome> refreshNow() async => RefreshOutcome.ok;

  @override
  void pauseBackgroundWork() {}

  @override
  void resumeBackgroundWork() {}
}

Override get _linked => syncEngineProvider.overrideWithValue(_LinkedEngine());

Override _pulledAt(DateTime at) =>
    syncLastPullCompletedAtProvider.overrideWith((ref) => at);

Override _pending(int count) =>
    syncPendingCountProvider.overrideWith((ref) => Stream.value(count));

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Finder status() => find.bySemanticsIdentifier('shopping.status');

  testChoreApp(
    'status line: unlinked shows only how many items are left (F1)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ShoppingRepository(database);
      await repo.addItem(householdId, name: 'Milk');
      await repo.addItem(householdId, name: 'Bread');
      final eggs = await repo.addItem(householdId, name: 'Eggs');
      await repo.setChecked(eggs.id, checked: true);

      await openShoppingTab(tester);

      expect(find.text('2 left'), findsOneWidget);
      expect(find.textContaining('synced'), findsNothing);
      expect(find.textContaining('waiting'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: an empty list says nothing is left',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      expect(find.text('Nothing left'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: linked with nothing waiting adds "synced <relative>" (F10)',
    today: today,
    overrides: [
      _linked,
      _pulledAt(DateTime(2026, 7, 24, 8, 55)),
      _pending(0),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      expect(find.text('1 left · synced 5 min ago'), findsOneWidget);
      expect(status(), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: linked with changes waiting shows the pending count '
    'instead of the synced time',
    today: today,
    overrides: [
      _linked,
      _pulledAt(DateTime(2026, 7, 24, 8, 55)),
      _pending(2),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      expect(find.text('1 left · 2 changes waiting to send'), findsOneWidget);
      expect(find.textContaining('synced'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'status line: linked but never pulled this session shows only the count',
    today: today,
    overrides: [_linked, _pending(0)],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');

      await openShoppingTab(tester);

      expect(find.text('1 left'), findsOneWidget);

      handle.dispose();
    },
  );

  group('addedBy avatar', () {
    Future<ShoppingItem> addAs(
      AppDatabase database,
      String householdId,
      String name,
      String? memberId,
    ) => ShoppingRepository(
      database,
    ).addItem(householdId, name: name, addedBy: memberId);

    Finder avatarsIn(String itemId) => find.descendant(
      of: find.bySemanticsIdentifier('shopping.item.$itemId'),
      matching: find.byType(MemberAvatar),
    );

    testChoreApp(
      "a row added by someone else shows that member's 16 dp avatar with "
      'their name as tooltip; own and unknown rows show none (F1)',
      today: today,
      (tester, database) async {
        final handle = tester.ensureSemantics();
        final householdId = await currentHouseholdId(database);
        final me = await (database.select(
          database.members,
        )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
        final anna = await HouseholdRepository(
          database,
        ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
        final byAnna = await addAs(database, householdId, 'Butter', anna.id);
        final byMe = await addAs(database, householdId, 'Bread', me.id);
        final byNobody = await addAs(database, householdId, 'Eggs', null);
        // A member who has since been removed (soft-deleted).
        final gone = await HouseholdRepository(
          database,
        ).addMember(householdId, name: 'Gone', color: 0xFF8C7BC9);
        final byGone = await addAs(database, householdId, 'Jam', gone.id);
        await (database.update(
          database.members,
        )..where((tbl) => tbl.id.equals(gone.id))).write(
          MembersCompanion(
            deletedAt: Value(DateTime.utc(2026).toIso8601String()),
          ),
        );

        await openShoppingTab(tester);

        expect(avatarsIn(byAnna.id), findsOneWidget);
        expect(avatarsIn(byMe.id), findsNothing);
        expect(avatarsIn(byNobody.id), findsNothing);
        expect(avatarsIn(byGone.id), findsNothing);

        final avatar = tester.widget<MemberAvatar>(avatarsIn(byAnna.id));
        expect(avatar.member.id, anna.id);
        expect(avatar.radius, 8);
        expect(
          find.descendant(
            of: find.bySemanticsIdentifier('shopping.item.${byAnna.id}'),
            matching: find.byTooltip('Anna'),
          ),
          findsOneWidget,
        );

        handle.dispose();
      },
    );
  });
}
