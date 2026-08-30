/// `ColorSwatchPicker` renders the twelve-colour palette (spec
/// `docs/specs/theme-v2.md` §1.3) as theme-rendered rings, six per row, and
/// marks colours another member already holds as inert and badged.
library;

import 'package:chore_app/app/color_swatch_picker.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpPicker(
  WidgetTester tester,
  ThemeData theme, {
  required int selected,
  Map<int, TakenSwatch> taken = const {},
  ValueChanged<int>? onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ColorSwatchPicker(
            colors: CategoryRepository.palette,
            selected: selected,
            onSelected: onSelected ?? (_) {},
            semanticIdPrefix: 'test.color',
            taken: taken,
          ),
        ),
      ),
    ),
  );
}

/// The decorated box each swatch draws its ring with.
Iterable<BoxDecoration> _swatchDecorations(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.border != null);

void main() {
  testWidgets('renders all twelve palette colours', (tester) async {
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette.first,
    );
    expect(_swatchDecorations(tester), hasLength(12));
  });

  testWidgets('swatch rings use categoryTone, not the raw stored value', (
    tester,
  ) async {
    // Index 2 is stored as 0xFFD98E73 and renders as 0xFFB96A4C in light --
    // the two differ, so this distinguishes toned from raw.
    const stored = 0xFFD98E73;
    await _pumpPicker(tester, appLightTheme, selected: stored);
    final context = tester.element(find.byType(ColorSwatchPicker));
    final expected = categoryTone(context, stored);
    expect(expected, isNot(const Color(stored)));

    final borders = _swatchDecorations(
      tester,
    ).map((d) => (d.border! as Border).top.color).toList();
    expect(borders, contains(expected));
    expect(borders, isNot(contains(const Color(stored))));
  });

  testWidgets('swatch rings use the DARK tone under the dark theme', (
    tester,
  ) async {
    const stored = 0xFFD98E73;
    await _pumpPicker(tester, appDarkTheme, selected: stored);
    final context = tester.element(find.byType(ColorSwatchPicker));
    final expected = categoryTone(context, stored);
    expect(expected, const Color(0xFFF0AF95));

    final borders = _swatchDecorations(
      tester,
    ).map((d) => (d.border! as Border).top.color).toList();
    expect(borders, contains(expected));
  });

  testWidgets('lays the twelve out six per row', (tester) async {
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette.first,
    );
    final handle = tester.ensureSemantics();
    final firstRowY = tester
        .getCenter(find.bySemanticsIdentifier('test.color.0'))
        .dy;
    for (var i = 1; i < 6; i++) {
      expect(
        tester.getCenter(find.bySemanticsIdentifier('test.color.$i')).dy,
        firstRowY,
        reason: 'index $i belongs on the first row',
      );
    }
    expect(
      tester.getCenter(find.bySemanticsIdentifier('test.color.6')).dy,
      greaterThan(firstRowY),
      reason: 'index 6 starts the second row',
    );
    handle.dispose();
  });

  testWidgets('the selected swatch is marked by a check, not colour alone', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette[3],
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('a taken swatch is inert and shows the owner initials', (
    tester,
  ) async {
    const taken = 0xFFD98E73;
    var picked = -1;
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette.first,
      onSelected: (value) => picked = value,
      taken: const {
        taken: TakenSwatch(initials: 'AN', semanticsLabel: 'Taken by Anna'),
      },
    );
    final handle = tester.ensureSemantics();

    // Index 2 is the taken colour; its badge is drawn and its tap is inert.
    expect(find.text('AN'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('test.color.2'));
    await tester.pump();
    expect(picked, -1, reason: 'a taken swatch must not fire onSelected');

    // A free swatch still works.
    await tester.tap(find.bySemanticsIdentifier('test.color.3'));
    await tester.pump();
    expect(picked, CategoryRepository.palette[3]);

    handle.dispose();
  });

  testWidgets('an empty taken map leaves every swatch tappable', (
    tester,
  ) async {
    var picked = -1;
    await _pumpPicker(
      tester,
      appLightTheme,
      selected: CategoryRepository.palette.first,
      onSelected: (value) => picked = value,
    );
    final handle = tester.ensureSemantics();
    await tester.tap(find.bySemanticsIdentifier('test.color.2'));
    await tester.pump();
    expect(picked, CategoryRepository.palette[2]);
    handle.dispose();
  });
}
