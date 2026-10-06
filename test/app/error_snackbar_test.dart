import 'package:chore_app/app/snackbars.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Persona review B7: error snackbars carry an error icon in the error
/// colour, stay up for 8 s (long enough to read), and offer Retry when the
/// caller can retry.
void main() {
  Future<void> pump(WidgetTester tester, {VoidCallback? onRetry}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppErrorSnackbar(
                context,
                message: 'Boom',
                onRetry: onRetry,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows an error_outline icon in the error colour', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Boom'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    final scheme = Theme.of(tester.element(find.text('Boom'))).colorScheme;
    expect(icon.color, scheme.error);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    // No retry callback -> no action.
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('stays for 8 seconds, then auto-dismisses', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Boom'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Boom'), findsNothing);
  });

  testWidgets('onRetry adds a Retry action that fires the callback', (
    tester,
  ) async {
    var retried = 0;
    await pump(tester, onRetry: () => retried++);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
  });
}
