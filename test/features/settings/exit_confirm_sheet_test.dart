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
}
