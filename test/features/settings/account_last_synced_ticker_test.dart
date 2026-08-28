/// Backlog A-2b: the relative "Last synced" line in Settings -> Account
/// (spec `docs/specs/sync-freshness.md` §2.4) must keep itself fresh while
/// the screen stays open, instead of freezing at whatever it said when the
/// tile was first built.
///
/// **What makes these tests non-vacuous, and why they are shaped this way.**
/// A test that pumps a new tree and finds fresh text proves nothing -- the
/// rebuild did the work, not the ticker. So between the two assertions here
/// NOTHING happens except fake time passing: no database write, no provider
/// invalidation, no new `pumpWidget`, no tap. `tester.pump(Duration)`
/// advances `FakeAsync`, and the ticker's own `Timer` is the only thing in
/// the tree that can react to that.
///
/// The clock has to be able to MOVE for the rendered string to be able to
/// change at all -- under `testChoreApp`'s default `Clock.fixed` the text is
/// a constant and any such test is vacuous by construction. Hence
/// `clock: Clock(() => currentTime)` over a mutable variable, the seam
/// `test/test_utils/pump_app.dart` documents for exactly this and which
/// `test/features/chores/day_rollover_widget_test.dart` already uses.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/features/settings/last_synced_line.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'settings_test_utils.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  final signedIn = [
    authGatewayProvider.overrideWithValue(
      FakeAuthGateway(
        currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
      ),
    ),
  ];

  /// Links [database]'s household and records a pull cursor at
  /// [lastPulledAt], the way the engine does on every successful pull.
  Future<void> seedLinkedWithCursor(
    AppDatabase database, {
    required DateTime lastPulledAt,
  }) async {
    final householdId = await currentHouseholdId(database);
    final settings = SettingsRepository(database);
    await settings.setSyncLinked(householdId: householdId, linkedAt: today);
    await settings.setSyncLastPulledAt(lastPulledAt);
  }

  // Moved by the test body, with nothing else changing. File-scope, so each
  // test needs its own (a `testChoreApp` body runs once).
  var minutesBandTime = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'the minutes count refreshes itself while the screen stays open',
    today: today,
    clock: Clock(() => minutesBandTime),
    overrides: signedIn,
    (tester, database) async {
      // 10 minutes before `today`, the same local convention `today` uses.
      await seedLinkedWithCursor(
        database,
        lastPulledAt: DateTime(2026, 7, 24, 8, 50),
      );

      await openSettingsTab(tester);
      expect(find.text('Last synced 10 minutes ago'), findsOneWidget);

      // The State OBJECT, deliberately: identity is what distinguishes "the
      // live element refreshed itself" from "something rebuilt or remounted
      // the subtree and it happened to render fresh text". Findability would
      // not distinguish them at all.
      final lineState = tester.state<State<LastSyncedLine>>(
        find.byType(LastSyncedLine),
      );

      // 15 more minutes pass. Nothing else at all happens: no row is
      // written, no provider is invalidated, no widget is pumped afresh.
      minutesBandTime = DateTime(2026, 7, 24, 9, 15);
      await tester.pump(const Duration(minutes: 1));

      expect(
        tester.state<State<LastSyncedLine>>(find.byType(LastSyncedLine)),
        same(lineState),
      );
      expect(find.text('Last synced 25 minutes ago'), findsOneWidget);
      expect(find.text('Last synced 10 minutes ago'), findsNothing);
    },
  );

  var hoursBandTime = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'crossing out of the minutes band into the hours band refreshes too',
    today: today,
    clock: Clock(() => hoursBandTime),
    overrides: signedIn,
    (tester, database) async {
      // 59 minutes before `today`: one minute short of the hours band.
      await seedLinkedWithCursor(
        database,
        lastPulledAt: DateTime(2026, 7, 24, 8, 1),
      );

      await openSettingsTab(tester);
      expect(find.text('Last synced 59 minutes ago'), findsOneWidget);

      hoursBandTime = DateTime(2026, 7, 24, 9, 2);
      await tester.pump(const Duration(minutes: 1));

      expect(find.text('Last synced 1 hour ago'), findsOneWidget);
      expect(find.text('Last synced 59 minutes ago'), findsNothing);
    },
  );
}
