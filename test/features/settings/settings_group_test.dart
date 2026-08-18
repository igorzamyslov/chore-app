import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/settings/settings_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'settings_test_utils.dart';

/// Widget-level tests for the Settings tab's reusable group/row building
/// blocks (spec `docs/specs/theme-v2.md` §4.2): `SettingsGroup`'s hairline
/// placement and label uppercasing, `SettingsRow`'s "never two trailing
/// elements" rule, and -- via the fully pumped app -- the destructive reset
/// row rendering in `error` and sitting last in the Data group.
void main() {
  Future<void> pumpGroup(WidgetTester tester, Widget group) {
    return tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(body: group),
      ),
    );
  }

  group('SettingsGroup', () {
    testWidgets('uppercases its label without mutating the ARB source', (
      tester,
    ) async {
      await pumpGroup(
        tester,
        const SettingsGroup(label: 'Preferences', children: [SizedBox()]),
      );

      // `.toUpperCase()` is applied by the widget itself -- the ARB source
      // stays natural-case for the translator (spec §2: "never by an
      // already-uppercase ARB string").
      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('Preferences'), findsNothing);
    });

    testWidgets(
      'separates rows with a 1px hairline, but never after the last row',
      (tester) async {
        await pumpGroup(
          tester,
          const SettingsGroup(
            label: 'Group',
            children: [Text('Row A'), Text('Row B'), Text('Row C')],
          ),
        );

        // 3 rows -> exactly 2 hairlines, one between each adjacent pair,
        // none trailing the last row.
        expect(find.byType(Divider), findsNWidgets(2));
      },
    );

    testWidgets('a single-row group shows no hairline at all', (
      tester,
    ) async {
      await pumpGroup(
        tester,
        const SettingsGroup(label: 'Group', children: [Text('Only row')]),
      );

      expect(find.byType(Divider), findsNothing);
    });
  });

  group('SettingsRow', () {
    testWidgets('a value trailing shows the value text, no chevron, no '
        'switch', (tester) async {
      await pumpGroup(
        tester,
        const SettingsRow(
          icon: Icons.language_outlined,
          label: 'Language',
          value: 'English',
        ),
      );

      expect(find.text('English'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('a chevron trailing shows no value text and no switch', (
      tester,
    ) async {
      await pumpGroup(
        tester,
        const SettingsRow(
          icon: Icons.people_outline,
          label: 'Members',
          showChevron: true,
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets(
      'a switch trailing shows no chevron, and tapping anywhere in the row '
      'toggles it (mirroring SwitchListTile)',
      (tester) async {
        var value = false;
        await pumpGroup(
          tester,
          SettingsRow(
            icon: Icons.notifications_outlined,
            label: 'Daily summary',
            switchValue: value,
            onSwitchChanged: (newValue) => value = newValue,
          ),
        );

        expect(find.byType(Switch), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsNothing);

        // Tapping the label text (not the switch thumb itself) still
        // toggles it -- the whole row is one tap target.
        await tester.tap(find.text('Daily summary'));
        await tester.pump();

        expect(value, isTrue);
      },
    );

    testWidgets(
      'a row with none of value/switch/chevron shows no trailing element '
      'at all (an info-only row)',
      (tester) async {
        await pumpGroup(
          tester,
          const SettingsRow(icon: Icons.info_outline, label: 'Famdo'),
        );

        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.trailing, isNull);
      },
    );

    test(
      'never shows two trailing elements at once -- constructing one trips '
      'an assertion',
      () {
        expect(
          () => SettingsRow(
            icon: Icons.language_outlined,
            label: 'Language',
            value: 'English',
            showChevron: true,
          ),
          throwsAssertionError,
        );
        expect(
          () => SettingsRow(
            icon: Icons.language_outlined,
            label: 'Language',
            value: 'English',
            onSwitchChanged: (_) {},
          ),
          throwsAssertionError,
        );
        expect(
          () => SettingsRow(
            icon: Icons.language_outlined,
            label: 'Language',
            onSwitchChanged: (_) {},
            showChevron: true,
          ),
          throwsAssertionError,
        );
      },
    );

    testWidgets('destructive draws the leading icon and the label in '
        'error', (tester) async {
      await pumpGroup(
        tester,
        const SettingsRow(
          icon: Icons.delete_forever_outlined,
          label: 'Reset app data',
          destructive: true,
        ),
      );

      final errorColor = appLightTheme.colorScheme.error;
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.delete_forever_outlined),
      );
      expect(icon.color, errorColor);

      final title = tester.widget<Text>(find.text('Reset app data'));
      expect(title.style?.color, errorColor);
    });
  });

  group('the destructive reset row, in the fully pumped Settings screen', () {
    final today = DateTime(2026, 7, 24, 9);

    testChoreApp(
      'renders in error and sits last in the Data group, below the export '
      'row',
      today: today,
      (tester, database) async {
        final handle = tester.ensureSemantics();
        await openSettingsTab(tester);

        final exportRow = find.bySemanticsIdentifier('settings.export');
        final resetRow = find.bySemanticsIdentifier('settings.reset');
        expect(exportRow, findsOneWidget);
        expect(resetRow, findsOneWidget);

        // Reset is the last (bottommost) of the Data group's two rows.
        expect(
          tester.getTopLeft(exportRow).dy,
          lessThan(tester.getTopLeft(resetRow).dy),
        );

        final errorColor = Theme.of(tester.element(resetRow)).colorScheme.error;

        final icon = tester.widget<Icon>(
          find.descendant(
            of: resetRow,
            matching: find.byIcon(Icons.delete_forever_outlined),
          ),
        );
        expect(icon.color, errorColor);

        final title = tester.widget<Text>(
          find.descendant(of: resetRow, matching: find.text('Reset app data')),
        );
        expect(title.style?.color, errorColor);

        // ... and the export row right above it is NOT drawn in error.
        final exportIcon = tester.widget<Icon>(
          find.descendant(
            of: exportRow,
            matching: find.byIcon(Icons.ios_share_outlined),
          ),
        );
        expect(exportIcon.color, isNot(errorColor));

        handle.dispose();
      },
    );
  });
}
