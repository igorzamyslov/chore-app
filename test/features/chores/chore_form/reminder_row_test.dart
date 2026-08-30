/// Widget-level tests for `ChoreFormReminderRow`, the chore form's
/// per-chore reminder row (spec `docs/specs/notifications-n2.md` §2.1,
/// §12).
///
/// A leaf widget with no providers, so the bare-`MaterialApp` pump this
/// directory already uses (`repeat_section_test.dart`) applies — never a
/// hand-rolled `ProviderScope`, which hangs.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/domain/reminder_planner.dart';
import 'package:chore_app/features/chores/chore_form/reminder_row.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Matched by its literal English copy on purpose: this pump applies no
  // locale override, so the template ARB's text is what renders, and a
  // test reading the same `AppLocalizations` getter the widget reads would
  // pass no matter what that getter returned.
  const ruleDHint = "This chore won't be counted in the daily summary";

  Future<void> pumpRow(
    WidgetTester tester, {
    required int? minutes,
    required ValueChanged<int?> onChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChoreFormReminderRow(minutes: minutes, onChanged: onChanged),
        ),
      ),
    );
  }

  Switch toggleOf(WidgetTester tester) => tester.widget<Switch>(
    find
        .descendant(
          of: find.bySemanticsIdentifier('chore_form.reminder.toggle'),
          matching: find.byType(Switch),
        )
        .first,
  );

  testWidgets('off: switch is off, no time card, no Rule D hint', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, minutes: null, onChanged: (_) {});

    expect(
      find.bySemanticsIdentifier('chore_form.reminder.toggle'),
      findsOneWidget,
    );
    expect(toggleOf(tester).value, isFalse);
    expect(
      find.bySemanticsIdentifier('chore_form.reminder.time'),
      findsNothing,
    );
    expect(find.text(ruleDHint), findsNothing);

    handle.dispose();
  });

  testWidgets('on: switch is on, time card shows, Rule D hint shows', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, minutes: defaultReminderMinutes, onChanged: (_) {});

    expect(toggleOf(tester).value, isTrue);
    expect(
      find.bySemanticsIdentifier('chore_form.reminder.time'),
      findsOneWidget,
    );
    // Rule D (D2) explained where it applies -- the single place the user
    // is told their chore leaves the digest's counts.
    expect(find.text(ruleDHint), findsOneWidget);

    handle.dispose();
  });

  testWidgets('flipping the switch on reports the 18:00 default', (
    tester,
  ) async {
    final reported = <int?>[];
    await pumpRow(tester, minutes: null, onChanged: reported.add);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // The pre-fill is a CONSTANT, not a settings column (spec §2.1). Never
    // asserted as rendered digits: `flutter test` resolves a 12-hour
    // locale, so 1080 renders "6:00 PM", not "18:00".
    expect(reported, [defaultReminderMinutes]);
  });

  testWidgets('flipping the switch off reports null', (tester) async {
    final reported = <int?>[];
    await pumpRow(
      tester,
      minutes: defaultReminderMinutes,
      onChanged: reported.add,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // One nullable fact (D1): off IS null, there is no separate flag that
    // could disagree with a retained time.
    expect(reported, [null]);
  });
}
