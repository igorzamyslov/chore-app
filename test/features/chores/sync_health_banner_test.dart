/// Widget coverage for `SyncHealthBanner` on the chores tab (spec
/// `docs/specs/sync-freshness.md` §2.5): renders nothing while
/// `syncHealthStatusProvider` is healthy, one row with the banner copy while
/// unhealthy, and reflows rather than overflowing at textScale 2.0.
///
/// Overrides `syncHealthStatusProvider` directly rather than reconstructing a
/// real unhealthy condition -- a deliberate, narrow exception to this suite's
/// usual "override only db/clock/transport/auth" rule (see
/// `lib/app/providers.dart`'s file doc comment for why this override point
/// exists). Reconstructing it for real needs a linked, signed-in device with
/// a fake transport, which is a bare-`ProviderContainer` shape, not a pumped
/// app; the underlying computation is covered end to end, with real data, by
/// `test/domain/sync_health_test.dart` and
/// `test/app/sync_health_status_provider_test.dart`. This file's only job is
/// the widget's own render/hide wiring on this screen.
///
/// **E2E cannot cover this banner at all** (spec §2.5's verification note):
/// the Maestro suite builds with empty Supabase dart-defines, so every run is
/// unlinked and permanently healthy by construction. These widget tests are
/// the whole safety net.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/domain/sync_health.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// The English copy the ARB produces. Spelled out here rather than read back
/// from `AppLocalizations`, so a copy edit has to be made deliberately in
/// both places instead of a test happily asserting whatever the app now says
/// -- and in particular so the two things §2.5 requires of this sentence (it
/// never says "offline"; it names pull-to-refresh as the recourse) cannot be
/// dropped silently.
const _copy =
    "This device hasn't reached the rest of the household in a while. Your "
    'changes are saved — try pulling down to refresh.';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'absent on the chores tab while healthy',
    today: today,
    overrides: [
      syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.healthy),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('sync.health.banner'), findsNothing);
      expect(find.text(_copy), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'absent on the chores tab for an ordinary unlinked household, with no '
    'override at all',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      // Proves the real provider's gate, not just the widget's branch: an
      // unlinked household has no remote to be unhealthy about, so the
      // banner must never appear for the overwhelming majority of users.
      expect(find.bySemanticsIdentifier('sync.health.banner'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'present on the chores tab while unhealthy, with the expected copy',
    today: today,
    overrides: [
      syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.unhealthy),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('sync.health.banner'), findsOneWidget);
      expect(find.text(_copy), findsOneWidget);
      expect(
        _copy.toLowerCase(),
        isNot(contains('offline')),
        reason:
            'spec §2.5: the device may have a perfectly good connection '
            'while unable to reach the household, so the copy must never '
            'make a connectivity verdict',
      );
      expect(
        _copy,
        contains('pulling down to refresh'),
        reason:
            'spec §2.5 (DECIDED): the banner is not tappable, so the '
            'sentence itself has to name the recourse',
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the unhealthy banner reflows without overflowing at textScale 2.0',
    today: today,
    overrides: [
      syncHealthStatusProvider.overrideWithValue(SyncHealthStatus.unhealthy),
    ],
    (tester, database) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_copy), findsOneWidget);
    },
  );
}
