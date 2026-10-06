import 'package:chore_app/app/snackbars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHost(WidgetTester tester, {Duration? duration}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => duration == null
                ? showAppSnackbar(
                    context,
                    message: 'Hello',
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
                  )
                : showAppSnackbar(
                    context,
                    message: 'Hello',
                    duration: duration,
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
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

void main() {
  testWidgets('default duration is 4 s', (tester) async {
    await _pumpHost(tester);
    expect(find.text('Hello'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Hello'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsNothing);
  });

  testWidgets('a longer duration keeps the snackbar up past 4 s', (
    tester,
  ) async {
    await _pumpHost(tester, duration: const Duration(seconds: 8));

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Hello'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsNothing);
  });
}
