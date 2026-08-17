import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/features/chores/chore_form/labelled_field_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget-level tests for the chore form's labelled field card (spec
/// `docs/specs/theme-v2.md` §4.4 item 1): the permanently-visible uppercase
/// label (never a floating label that vanishes once typing starts) and its
/// focused/unfocused border + label color split.
void main() {
  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: Column(
            children: [
              LabelledFieldCard(label: 'Title', controller: controller),
              // A second focusable field so focus can be moved elsewhere,
              // exercising the unfocused state too.
              const TextField(),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration cardDecoration(WidgetTester tester) {
    return tester
            .widget<Container>(
              find.descendant(
                of: find.byType(LabelledFieldCard),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;
  }

  testWidgets(
    'the label stays visible (never floating) both unfocused and focused, '
    'uppercased for display only',
    (tester) async {
      final controller = TextEditingController();
      await pumpField(tester, controller);

      // Uppercase is display-only: the natural-case string is the
      // accessibility label (matching `_SectionHeader`'s established
      // pattern), never an already-uppercase ARB string.
      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('Title'), findsNothing);

      await tester.enterText(
        find.descendant(
          of: find.byType(LabelledFieldCard),
          matching: find.byType(TextField),
        ),
        'Wash dishes',
      );
      await tester.pump();

      // The label is still there after typing -- unlike a floating
      // Material label, it never disappears.
      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('Wash dishes'), findsOneWidget);
    },
  );

  testWidgets('the border is outlineVariant unfocused and primaryOutline (2px) '
      'once focused', (tester) async {
    final controller = TextEditingController();
    await pumpField(tester, controller);

    final context = tester.element(find.byType(LabelledFieldCard));
    final colorScheme = Theme.of(context).colorScheme;
    final famdo = famdoColors(context);

    // Unfocused: outlineVariant, 1px.
    var border = cardDecoration(tester).border! as Border;
    expect(border.top.color, colorScheme.outlineVariant);
    expect(border.top.width, 1);

    await tester.tap(
      find.descendant(
        of: find.byType(LabelledFieldCard),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();

    // Focused: primaryOutline, 2px.
    border = cardDecoration(tester).border! as Border;
    expect(border.top.color, famdo.primaryOutline);
    expect(border.top.width, 2);

    // Moving focus away reverts to the unfocused styling.
    await tester.tap(find.byType(TextField).last);
    await tester.pump();

    border = cardDecoration(tester).border! as Border;
    expect(border.top.color, colorScheme.outlineVariant);
    expect(border.top.width, 1);
  });

  testWidgets(
    'an inline error renders below the card without clearing the entered '
    'text',
    (tester) async {
      final controller = TextEditingController(text: 'Wash dishes');
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: LabelledFieldCard(
              label: 'Title',
              controller: controller,
              errorText: 'Title is required',
            ),
          ),
        ),
      );

      expect(find.text('Title is required'), findsOneWidget);
      expect(find.text('Wash dishes'), findsOneWidget);
      expect(controller.text, 'Wash dishes');
    },
  );
}
