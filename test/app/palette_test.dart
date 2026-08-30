/// The twelve-colour palette (spec `docs/specs/theme-v2.md` §1.3, design
/// canvas frames 1b/1d) must resolve through the hand-picked tone table in
/// BOTH themes -- never through `categoryTone`'s HSL fallback, which exists
/// only for colours arriving from sync or an imported archive.
library;

import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _pumpAndGetContext(
  WidgetTester tester,
  ThemeData theme,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

/// WCAG 2.1 contrast ratio between two opaque colours.
double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const expectedLight = <Color>[
    Color(0xFF4E7E54),
    Color(0xFF6B57B0),
    Color(0xFFB96A4C),
    Color(0xFF3F8697),
    Color(0xFFA86485),
    Color(0xFF8E7833),
    Color(0xFF5A73AD),
    Color(0xFF77716A),
    // Slot 8 is plum, NOT the canvas's #1E7A6E -- see R1: that hex is
    // `_lightPrimary`, so a ring drawn in it reads as "selected".
    Color(0xFF9A3D80),
    Color(0xFF96562F),
    Color(0xFF7A5AA8),
    Color(0xFF4C6B45),
  ];
  const expectedDark = <Color>[
    Color(0xFF93C297),
    Color(0xFFB4A5E8),
    Color(0xFFF0AF95),
    Color(0xFF8ACBD9),
    Color(0xFFE7AEC6),
    Color(0xFFDBC585),
    Color(0xFFA4B8E5),
    Color(0xFFC8C4BE),
    Color(0xFFD9A0C9),
    Color(0xFFDFB49A),
    Color(0xFFB9A8D1),
    Color(0xFFB4CBAE),
  ];

  test('the palette is twelve colours, extending seedColors in order', () {
    expect(CategoryRepository.palette, hasLength(12));
    expect(
      CategoryRepository.palette.sublist(0, 8),
      CategoryRepository.seedColors,
      reason:
          'indices 0-7 must keep addressing exactly the colours they address '
          'today: the members.edit.color.N / settings.categories.color.N '
          'semantic ids are indexed and must not change meaning',
    );
    expect(CategoryRepository.palette.toSet(), hasLength(12));
  });

  testWidgets('every palette colour has a hand-picked LIGHT render', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appLightTheme);
    for (var i = 0; i < CategoryRepository.palette.length; i++) {
      expect(
        categoryTone(context, CategoryRepository.palette[i]),
        expectedLight[i],
        reason: 'palette index $i',
      );
    }
  });

  testWidgets('every palette colour has a hand-picked DARK render', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appDarkTheme);
    for (var i = 0; i < CategoryRepository.palette.length; i++) {
      expect(
        categoryTone(context, CategoryRepository.palette[i]),
        expectedDark[i],
        reason: 'palette index $i',
      );
    }
  });

  testWidgets('every LIGHT render clears 3:1 on every light ground', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appLightTheme);
    final scheme = Theme.of(context).colorScheme;
    final grounds = <Color>[
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.surfaceContainerHigh,
    ];
    for (final stored in CategoryRepository.palette) {
      final tone = categoryTone(context, stored);
      for (final ground in grounds) {
        expect(
          _contrastRatio(tone, ground),
          greaterThanOrEqualTo(3),
          reason:
              'light tone $tone on $ground '
              '(ring is a UI edge: 3:1, design canvas frame 1b)',
        );
      }
    }
  });

  testWidgets('every DARK render clears 3:1 on every dark ground', (
    tester,
  ) async {
    final context = await _pumpAndGetContext(tester, appDarkTheme);
    final scheme = Theme.of(context).colorScheme;
    final grounds = <Color>[
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.surfaceContainerHigh,
    ];
    for (final stored in CategoryRepository.palette) {
      final tone = categoryTone(context, stored);
      for (final ground in grounds) {
        expect(
          _contrastRatio(tone, ground),
          greaterThanOrEqualTo(3),
          reason: 'dark tone $tone on $ground',
        );
      }
    }
  });
}
