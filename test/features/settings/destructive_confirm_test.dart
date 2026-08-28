/// Widget tests for the shared two-step destructive confirmation
/// (`lib/features/settings/destructive_confirm.dart`, spec
/// `docs/specs/polish-round-1.md` B2).
///
/// The behavioural coverage of the reset flow that uses it lives in
/// `reset_flow_test.dart`, driven through the real app. This file exists for
/// the one thing that file cannot reach: the dialog's own layout at a large
/// text scale on a small surface. The Settings screen does not itself lay
/// out at 320x640 with a 2x scale, so this needs a bare harness.
library;

import 'package:chore_app/features/settings/destructive_confirm.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a long body at a large text scale on a small phone stays READABLE: the '
    'dialog scrolls (regression -- the AlertDialog never set scrollable, '
    'the third instance of the bug class fixed in exit_confirm_sheet and '
    'member_delete_dialog)',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final handle = tester.ensureSemantics();
      late String longBody;
      await tester.pumpWidget(
        MaterialApp(
          // The generated bundle the real `ChoreApp` uses, not a hand-rolled
          // list: a list missing `GlobalCupertinoLocalizations` makes
          // MaterialApp warn "locale de is not supported by all of its
          // localization delegates", and that warning trips
          // `takeException()` below before this test's own subject does.
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // German, because German runs longer than the English of the same
          // string and is the locale that reaches this layout first.
          locale: const Locale('de'),
          home: Builder(
            builder: (context) {
              // The live caller's real copy, read through the l10n getters
              // rather than pasted in: this guard is about the strings the
              // reset flow actually shows, and a pasted copy would drift
              // away from them silently.
              final l10n = AppLocalizations.of(context);
              longBody = l10n.settingsResetConfirm1BodyLinked;
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => confirmTwoStepDestructiveAction(
                    context,
                    first: DestructiveConfirmStep(
                      title: l10n.settingsResetConfirm1Title,
                      body: longBody,
                      confirmLabel: l10n.settingsResetConfirm1Action,
                      cancelLabel: l10n.commonCancel,
                      confirmSemanticId: 'settings.reset.confirm1',
                      cancelSemanticId: 'settings.reset.cancel1',
                    ),
                    second: DestructiveConfirmStep(
                      title: l10n.settingsResetConfirm2Title,
                      body: l10n.settingsResetConfirm2Body,
                      confirmLabel: l10n.settingsResetConfirm2Action,
                      cancelLabel: l10n.commonCancel,
                      confirmSemanticId: 'settings.reset.confirm2',
                      cancelSemanticId: 'settings.reset.cancel',
                    ),
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // An `AlertDialog` puts its content in a bare `Flexible` unless asked
      // to be scrollable, so a body taller than the dialog is silently
      // CLIPPED -- no exception, no scrollbar, and the rest of the sentence
      // simply unreadable. Asserting the scroll view exists is therefore
      // the assertion that actually fails without the fix; the drag below
      // is what proves it is a working scroll view rather than a nested
      // widget that happens to be named one.
      final scrollable = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      );
      expect(
        scrollable,
        findsOneWidget,
        reason: 'the dialog body must be reachable, not clipped',
      );

      final bodyFinder = find.text(longBody);
      final before = tester.getTopLeft(bodyFinder).dy;
      await tester.drag(scrollable, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(bodyFinder).dy,
        lessThan(before),
        reason: 'dragging must actually move the body, not just not crash',
      );

      // The confirm must still be reachable and hit-testable after all
      // that: the actions row sits outside the scroll view, so a botched
      // fix that scrolls the buttons out of the dialog fails here.
      final firstConfirm = find.bySemanticsIdentifier(
        'settings.reset.confirm1',
      );
      await tester.tap(firstConfirm);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.reset.confirm2'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      handle.dispose();
    },
  );
}
