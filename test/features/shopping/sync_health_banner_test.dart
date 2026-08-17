/// Widget coverage for `SyncHealthBanner` on the shopping tab (spec
/// `docs/specs/sync-freshness.md` §2.5) -- see
/// `test/features/chores/sync_health_banner_test.dart` for why this overrides
/// `syncHealthStatusProvider` directly, and for why E2E cannot cover this
/// banner at all.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/sync_health.dart';
import 'package:chore_app/features/shopping/shopping_quick_add_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'shopping_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'absent on the shopping tab while healthy',
    today: today,
    overrides: [
      syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.healthy),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      expect(find.bySemanticsIdentifier('sync.health.banner'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'present on the shopping tab while unhealthy, above the quick-add row',
    today: today,
    overrides: [
      syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.unhealthy),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openShoppingTab(tester);

      final banner = find.bySemanticsIdentifier('sync.health.banner');
      expect(banner, findsOneWidget);
      // Order matters (see the comment at the insertion site): the warning
      // is about whether what you are about to type will reach the person
      // you are shopping for, so it has to be readable before the field.
      expect(
        tester.getCenter(banner).dy,
        lessThan(tester.getCenter(find.byType(ShoppingQuickAddRow)).dy),
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the shopping list still has exactly one ListView with the banner shown',
    today: today,
    overrides: [
      syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.unhealthy),
    ],
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      await ShoppingRepository(database).addItem(householdId, name: 'Milk');
      await openShoppingTab(tester);

      // The banner must never introduce a scrollable of its own: several
      // tests in this suite (and on the chores tab) select the list by
      // `find.byType(ListView)` expecting exactly ONE match.
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
