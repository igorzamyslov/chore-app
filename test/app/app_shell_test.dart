import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_utils/pump_app.dart';

void main() {
  testChoreApp(
    'three tabs render; switching swaps content and the shell keeps every '
    "visited tab's state alive",
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.shopping'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell.tab.settings'), findsOneWidget);

      // Chores is the default tab; the other two aren't shown yet.
      expect(find.bySemanticsIdentifier('settings.categories'), findsNothing);

      // The content is a PageView (backlog D-1: horizontal swipe between
      // tabs). Per-page keep-alive -- the property the old IndexedStack
      // provided -- is covered in test/app/shell_navigation_test.dart.
      expect(find.byType(PageView), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Shopping'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Settings'),
        ),
        findsOneWidget,
      );
      // The real settings screen (spec ux-round-2 B1), not a placeholder.
      expect(find.bySemanticsIdentifier('settings.categories'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.chores'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Chores'),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'the active tab shows a primaryContainer pill behind its filled icon; '
    'inactive tabs show no pill (spec docs/specs/theme-v2.md §4.5)',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      Color? pillColorFor(String tabId) {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.bySemanticsIdentifier(tabId),
            matching: find.byType(Container),
          ),
        );
        return (container.decoration! as BoxDecoration).color;
      }

      final primaryContainer = Theme.of(
        tester.element(find.bySemanticsIdentifier('shell.tab.chores')),
      ).colorScheme.primaryContainer;

      // Chores is the default tab: it carries the pill, the others don't.
      expect(pillColorFor('shell.tab.chores'), primaryContainer);
      expect(pillColorFor('shell.tab.shopping'), Colors.transparent);
      expect(pillColorFor('shell.tab.settings'), Colors.transparent);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      // The pill moved with the selection.
      expect(pillColorFor('shell.tab.shopping'), primaryContainer);
      expect(pillColorFor('shell.tab.chores'), Colors.transparent);

      handle.dispose();
    },
  );

  // Backlog B-5 / triage T2.6: an ambient "the digest will never arrive"
  // dot on the Settings tab, so the recovery path is visible from every
  // tab instead of only to someone who already decided to open Settings.
  //
  // NOTE ON WHAT THESE DO AND DON'T PROVE: `_BottomTabBar` is the
  // `Scaffold`'s `bottomNavigationBar`, i.e. a SIBLING of the tab
  // `PageView`, not one of its pages -- so none of this touches
  // `_KeepAlivePage`/`AutomaticKeepAliveClientMixin` and the
  // "still there after switching tabs" assertion below is not a
  // keep-alive assertion (the bar never unmounts). What it does test is
  // that the dot is a projection of provider state and not of which tab
  // happens to be selected -- it goes red if the badge is ever gated on
  // the Settings tab being the visible one.
  const badgeId = 'shell.tab.settings.attentionBadge';

  Finder badgeUnder(String tabId) => find.descendant(
    of: find.bySemanticsIdentifier(tabId),
    matching: find.bySemanticsIdentifier(badgeId),
  );

  testChoreApp(
    'no attention badge on a fresh install: the digest is enabled by '
    'default but the pre-prompt has never been shown, so a never-requested '
    'OS permission must not read as a denied one',
    today: DateTime(2026, 7, 24, 9),
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      // The digest really is on for this row -- otherwise the assertion
      // below would hold for a reason this test isn't about.
      final settings = await database.select(database.settings).getSingle();
      expect(settings.digestEnabled, isTrue);
      expect(settings.digestPrepromptShownAt, isNull);

      expect(find.bySemanticsIdentifier(badgeId), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'attention badge appears once the pre-prompt has been shown and the '
    'permission is still denied -- on the Settings tab only, and visible '
    'from every tab rather than just from Settings',
    today: DateTime(2026, 7, 24, 9),
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).markDigestPrepromptShown();
      await tester.pumpAndSettle();

      expect(badgeUnder('shell.tab.settings'), findsOneWidget);
      expect(badgeUnder('shell.tab.chores'), findsNothing);
      expect(badgeUnder('shell.tab.shopping'), findsNothing);

      // Chores is still the selected tab at this point, so the dot is
      // already doing its job from somewhere other than Settings; switch
      // anyway to pin that a tab change doesn't clear it.
      await tester.tap(find.bySemanticsIdentifier('shell.tab.shopping'));
      await tester.pumpAndSettle();

      expect(badgeUnder('shell.tab.settings'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      expect(badgeUnder('shell.tab.settings'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'attention badge stays hidden once the permission is granted',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await SettingsRepository(database).markDigestPrepromptShown();
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier(badgeId), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'attention badge clears itself when the digest is turned off, even '
    'with the pre-prompt shown and the permission denied',
    today: DateTime(2026, 7, 24, 9),
    overrides: [
      notificationPermissionGrantedProvider.overrideWith((ref) => false),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final settingsRepository = SettingsRepository(database);
      await settingsRepository.markDigestPrepromptShown();
      await tester.pumpAndSettle();

      // Same guard as the digest-toggle sub-line tests: prove the badge
      // was THERE before the digest went off, or `findsNothing` below is
      // satisfied by any number of unrelated reasons.
      expect(badgeUnder('shell.tab.settings'), findsOneWidget);

      await settingsRepository.setDigestEnabled(enabled: false);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier(badgeId), findsNothing);

      handle.dispose();
    },
  );
}
