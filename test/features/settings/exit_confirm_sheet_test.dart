import 'package:chore_app/features/settings/exit_confirm_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the shared exit-confirmation sheet (spec
/// `docs/specs/household-lifecycle.md` §3.3, D-L3): every exit keeps this
/// phone's data unless the user opts in.
void main() {
  Future<ExitConfirmResult?> showAndTap(
    WidgetTester tester, {
    required bool checkTheBox,
    required String tapLabel,
  }) async {
    ExitConfirmResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showExitConfirmSheet(
                  context,
                  title: 'Leave the household?',
                  body: 'Your profile stays with the household.',
                  actionLabel: 'Leave',
                  semanticPrefix: 'settings.account.leave',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (checkTheBox) {
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets("defaults to keeping this phone's copy", (tester) async {
    final result = await showAndTap(
      tester,
      checkTheBox: false,
      tapLabel: 'Leave',
    );
    expect(result!.confirmed, isTrue);
    expect(result.alsoDeleteLocalData, isFalse);
  });

  testWidgets('carries the opt-in when the box is checked', (tester) async {
    final result = await showAndTap(
      tester,
      checkTheBox: true,
      tapLabel: 'Leave',
    );
    expect(result!.confirmed, isTrue);
    expect(result.alsoDeleteLocalData, isTrue);
  });

  testWidgets('cancel confirms nothing and deletes nothing', (tester) async {
    final result = await showAndTap(
      tester,
      checkTheBox: true,
      tapLabel: 'Cancel',
    );
    expect(result!.confirmed, isFalse);
    expect(result.alsoDeleteLocalData, isFalse);
  });

  testWidgets(
    'a long body at a large text scale on a small phone does not overflow '
    '(regression: the sheet had no scroll view, and D-L5/D-L6 add copy '
    'longer than either of the two strings live before slice 4)',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // The longest real string this cluster adds -- the German of
      // accountDeleteFinalBodyDeletePhone, German running longer again than
      // the English. Literal text rather than the l10n getter on purpose:
      // that key does not exist until slice 6, and this regression guard
      // must not depend on task order.
      const longBody =
          'Dein Konto und deine E-Mail-Adresse werden vom Server gelöscht, '
          'und die Kopie auf diesem Gerät — Mitglieder, Aufgaben und '
          'Einkaufsliste — wird ebenfalls gelöscht, die App startet neu. '
          'Beides lässt sich nicht rückgängig machen. Wenn du vorher eine '
          'Kopie deiner Daten willst, nutze „Exportieren“ unter '
          'Einstellungen → Daten.';

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showExitConfirmSheet(
                  context,
                  title: 'Delete your account?',
                  body: longBody,
                  actionLabel: 'Delete account',
                  semanticPrefix: 'settings.account.deleteAccount',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The action must be reachable, not merely un-crashed: scrolling to it
      // is what makes the overflow fix a fix rather than a clip.
      await tester.scrollUntilVisible(find.text('Delete account'), 100);
      expect(find.text('Delete account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
