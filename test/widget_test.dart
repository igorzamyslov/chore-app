import 'package:chore_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the app shell', (tester) async {
    await tester.pumpWidget(const ChoreApp());
    expect(find.text('Chores — coming soon'), findsOneWidget);
  });
}
