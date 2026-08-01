import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

/// Field feedback B1 (`docs/feedback/2026-08-01-field-feedback.md`): a "Done"
/// snackbar was observed to stay on screen indefinitely. Two mechanisms were
/// suspected going in: (a) the app shell's nested `ScaffoldMessenger` sitting
/// above an `IndexedStack` — a tab switch might mute the hidden tab's tickers
/// mid-dismiss-animation — and (b) app suspension pausing timers.
///
/// REPRO FINDING: neither suspected mechanism reproduces. This Flutter SDK's
/// `IndexedStack` wraps each child in `Visibility(maintainAnimation: true,
/// ...)`, which explicitly skips wrapping hidden children in
/// `TickerMode(enabled: false)` — hidden tabs keep ticking, confirmed by the
/// "no-switch control" case below dismissing identically to the
/// "switch-away-and-back" case. Backgrounding (paused/resumed) doesn't
/// reproduce it either.
///
/// The bar DOES get stuck, though — reproduced by the second test below,
/// with NO tab switching at all: it's `SnackBar.persist`, which defaults to
/// `true` whenever `SnackBar.action` is non-null ("If not provided, but the
/// snackbar action is not null, the snackbar will persist" — see
/// `package:flutter/src/material/snack_bar.dart`). Every close/skip toast in
/// this app carries an UNDO action, so every single one of them was
/// persisting forever, regardless of tabs — the auto-dismiss `Timer`
/// silently no-ops when `persist` is true. Fixed by passing `persist: false`
/// explicitly in `lib/app/snackbars.dart`'s `showAppSnackbar`.
///
/// Regardless of mechanism, the independently-correct UX fix — switching
/// tabs clears any snackbar shown on the tab being left, since a completion
/// toast is contextual to where it happened — is implemented in
/// `lib/app/app_shell.dart` and covered by
/// `test/app/snackbar_tab_switch_test.dart`.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'switching tabs mid-display and pumping well past the 4s duration does '
    'not, by itself, freeze or otherwise change dismissal versus staying on '
    'the same tab (rules out the IndexedStack/TickerMode theory)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Switch away mid-display (well before the 4s auto-dismiss), pump
      // well past the duration on the OTHER tab, then switch back.
      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();

      // With `persist: false` (the actual fix below) it has dismissed, same
      // as it would on a single unswitched tab -- switching tabs changed
      // nothing either way.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Done'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'an UNDO-bearing snackbar auto-dismisses after its duration on its OWN '
    'tab, with no tab switch at all -- this is what actually reproduced the '
    'field report (SnackBar.persist defaults true whenever an action is '
    'set; nothing to do with tabs)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // No tab switch, no backgrounding -- just letting time pass.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Done'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'backgrounding the app mid-snackbar (paused then resumed) does not '
    'leave it stuck either',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'One-off chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Simulate the OS backgrounding then foregrounding the app while the
      // snackbar is showing. Valid transitions require the `hidden`
      // intermediate step in both directions.
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Done'), findsNothing);

      handle.dispose();
    },
  );
}
