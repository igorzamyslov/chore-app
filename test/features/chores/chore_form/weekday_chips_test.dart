import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/chores/chore_form/weekday_chips.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Persona review 2026-10-06 C8 (Maria P3-Q): seven fixed 48dp toggles plus
/// spacing needed 360dp, but a 360dp phone leaves 328dp inside the form's
/// gutters, so Sunday wrapped alone; and 'T'/'T', 'S'/'S' were ambiguous.
void main() {
  Future<void> pumpChips(WidgetTester tester, {required Locale locale}) async {
    // A 360dp-wide phone, inside the chore form's 16dp gutters.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: WeekdayChips(selected: const {2}, onToggle: (_) {}),
          ),
        ),
      ),
    );
  }

  testWidgets('all seven fit on one row at 360dp, labelled Mo..Su', (
    tester,
  ) async {
    await pumpChips(tester, locale: const Locale('en'));

    const labels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final rows = <double>{};
    for (final label in labels) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: label);
      rows.add(tester.getCenter(finder).dy);
    }
    expect(rows, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('German labels are two letters too, and the full name stays '
      'the accessibility label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpChips(tester, locale: const Locale('de'));

    for (final label in ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(
      tester.getSemantics(
        find.bySemanticsIdentifier('chore_form.repeat.weekday.2'),
      ),
      isSemantics(label: 'Dienstag', isButton: true, isSelected: true),
    );

    handle.dispose();
  });
}
