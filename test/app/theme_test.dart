import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Theme v2 foundations tests (spec `docs/specs/theme-v2.md` §1, §1.2, §1.3):
/// the hand-authored `ColorScheme`s expose the spec's exact hex values,
/// `FamdoColors` resolves through the theme extension mechanism and lerps to
/// a valid instance, and `categoryTone` maps every seeded color (and an
/// unknown one) to the right light/dark render.
void main() {
  group('appLightTheme / appDarkTheme color schemes (spec §1.1)', () {
    test(
      'light scheme exposes the exact spec primary/surface/error values',
      () {
        final scheme = appLightTheme.colorScheme;
        expect(scheme.brightness, Brightness.light);
        expect(scheme.primary, const Color(0xFF1E7A6E));
        expect(scheme.onPrimary, const Color(0xFFFFFDF9));
        expect(scheme.surface, const Color(0xFFF6F1E9));
        expect(scheme.onSurface, const Color(0xFF241F19));
        expect(scheme.error, const Color(0xFFB44A2E));
        expect(scheme.onError, const Color(0xFFFFF6F2));
      },
    );

    test('dark scheme exposes the exact spec primary/surface/error values', () {
      final scheme = appDarkTheme.colorScheme;
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, const Color(0xFF63C9B8));
      expect(scheme.onPrimary, const Color(0xFF0E2622));
      expect(scheme.surface, const Color(0xFF161311));
      expect(scheme.onSurface, const Color(0xFFF0E9DF));
      expect(scheme.error, const Color(0xFFE58A6C));
      expect(scheme.onError, const Color(0xFF2A120A));
    });

    test('secondary/tertiary mirror primary on both schemes (no second '
        'accent)', () {
      for (final scheme in [
        appLightTheme.colorScheme,
        appDarkTheme.colorScheme,
      ]) {
        expect(scheme.secondary, scheme.primary);
        expect(scheme.onSecondary, scheme.onPrimary);
        expect(scheme.secondaryContainer, scheme.primaryContainer);
        expect(scheme.onSecondaryContainer, scheme.onPrimaryContainer);
        expect(scheme.tertiary, scheme.primary);
        expect(scheme.onTertiary, scheme.onPrimary);
        expect(scheme.tertiaryContainer, scheme.primaryContainer);
        expect(scheme.onTertiaryContainer, scheme.onPrimaryContainer);
      }
    });
  });

  group('FamdoColors (spec §1.2)', () {
    testWidgets('resolves to FamdoColors.light under appLightTheme', (
      tester,
    ) async {
      final context = await _pumpAndGetContext(tester, appLightTheme);
      final resolved = famdoColors(context);
      expect(resolved.primaryOutline, FamdoColors.light.primaryOutline);
      expect(resolved.errorOutline, FamdoColors.light.errorOutline);
      expect(resolved.errorChip, FamdoColors.light.errorChip);
      expect(resolved.onMemberColor, FamdoColors.light.onMemberColor);
      expect(resolved.navBarBackground, FamdoColors.light.navBarBackground);
      expect(resolved.lift, FamdoColors.light.lift);
      expect(resolved.fabShadow, FamdoColors.light.fabShadow);
      expect(resolved.sheetShadow, FamdoColors.light.sheetShadow);
    });

    testWidgets('resolves to FamdoColors.dark under appDarkTheme', (
      tester,
    ) async {
      final context = await _pumpAndGetContext(tester, appDarkTheme);
      final resolved = famdoColors(context);
      expect(resolved.primaryOutline, FamdoColors.dark.primaryOutline);
      expect(resolved.navBarBackground, FamdoColors.dark.navBarBackground);
      expect(resolved.lift, FamdoColors.dark.lift);
    });

    testWidgets('throws a clear error when no FamdoColors is registered', (
      tester,
    ) async {
      final context = await _pumpAndGetContext(
        tester,
        ThemeData(colorScheme: const ColorScheme.light()),
      );
      expect(() => famdoColors(context), throwsStateError);
    });

    test(
      'lerp returns a valid FamdoColors instance between light and dark',
      () {
        final lerped = FamdoColors.light.lerp(FamdoColors.dark, 0.5);
        expect(lerped, isA<FamdoColors>());
        expect(
          lerped.primaryOutline,
          Color.lerp(
            FamdoColors.light.primaryOutline,
            FamdoColors.dark.primaryOutline,
            0.5,
          ),
        );
        expect(lerped.lift.length, FamdoColors.light.lift.length);
        expect(lerped.fabShadow.length, FamdoColors.light.fabShadow.length);
        expect(lerped.sheetShadow.length, FamdoColors.light.sheetShadow.length);
      },
    );

    test('lerp at t=0 and t=1 returns the endpoints', () {
      final atStart = FamdoColors.light.lerp(FamdoColors.dark, 0);
      final atEnd = FamdoColors.light.lerp(FamdoColors.dark, 1);
      expect(atStart.primaryOutline, FamdoColors.light.primaryOutline);
      expect(atEnd.primaryOutline, FamdoColors.dark.primaryOutline);
    });

    test('copyWith replaces only the given fields', () {
      const replacement = Color(0xFF123456);
      final copy = FamdoColors.light.copyWith(primaryOutline: replacement);
      expect(copy.primaryOutline, replacement);
      expect(copy.errorOutline, FamdoColors.light.errorOutline);
      expect(copy.lift, FamdoColors.light.lift);
    });
  });

  group('categoryTone (spec §1.3)', () {
    const expectedLight = [
      Color(0xFF4E7E54), // Cleaning
      Color(0xFF6B57B0), // Kitchen
      Color(0xFFB96A4C), // Laundry
      Color(0xFF3F8697), // Garden
      Color(0xFFA86485), // Pets
      Color(0xFF8E7833), // Maintenance
      Color(0xFF5A73AD), // Errands
      Color(0xFF77716A), // Other
    ];
    const expectedDark = [
      Color(0xFF93C297), // Cleaning
      Color(0xFFB4A5E8), // Kitchen
      Color(0xFFF0AF95), // Laundry
      Color(0xFF8ACBD9), // Garden
      Color(0xFFE7AEC6), // Pets
      Color(0xFFDBC585), // Maintenance
      Color(0xFFA4B8E5), // Errands
      Color(0xFFC8C4BE), // Other
    ];

    testWidgets('maps each of the 8 seed colors to its light render', (
      tester,
    ) async {
      final context = await _pumpAndGetContext(tester, appLightTheme);
      for (var i = 0; i < CategoryRepository.seedColors.length; i++) {
        expect(
          categoryTone(context, CategoryRepository.seedColors[i]),
          expectedLight[i],
          reason: 'seed index $i',
        );
      }
    });

    testWidgets('maps each of the 8 seed colors to its dark render', (
      tester,
    ) async {
      final context = await _pumpAndGetContext(tester, appDarkTheme);
      for (var i = 0; i < CategoryRepository.seedColors.length; i++) {
        expect(
          categoryTone(context, CategoryRepository.seedColors[i]),
          expectedDark[i],
          reason: 'seed index $i',
        );
      }
    });

    testWidgets(
      'an unknown bright color is darkened (clamped to <= 0.42 lightness) '
      'in light',
      (tester) async {
        final context = await _pumpAndGetContext(tester, appLightTheme);
        // Pure red: HSL lightness 0.5, well above the 0.42 ceiling.
        const unknown = Color(0xFFFF0000);
        final rendered = categoryTone(context, unknown.toARGB32());

        final renderedHsl = HSLColor.fromColor(rendered);
        expect(renderedHsl.lightness, closeTo(0.42, 0.01));
        expect(renderedHsl.hue, closeTo(0, 1));
        expect(renderedHsl.saturation, closeTo(1.0, 0.02));
      },
    );

    testWidgets(
      'an unknown dim color is lightened (clamped to >= 0.70 lightness) in '
      'dark',
      (tester) async {
        final context = await _pumpAndGetContext(tester, appDarkTheme);
        // Pure red: HSL lightness 0.5, well below the 0.70 floor.
        const unknown = Color(0xFFFF0000);
        final rendered = categoryTone(context, unknown.toARGB32());

        final renderedHsl = HSLColor.fromColor(rendered);
        expect(renderedHsl.lightness, closeTo(0.70, 0.01));
        expect(renderedHsl.hue, closeTo(0, 1));
        expect(renderedHsl.saturation, closeTo(1.0, 0.02));
      },
    );

    testWidgets('an unknown color already within bounds is left alone (hue, '
        'saturation and lightness all preserved)', (tester) async {
      final context = await _pumpAndGetContext(tester, appLightTheme);
      // Pure red at HSL lightness 0.3 -- already under the 0.42 light
      // ceiling, so the clamp should be a no-op.
      const unknown = Color(0xFF990000);
      final unknownHsl = HSLColor.fromColor(unknown);
      expect(unknownHsl.lightness, closeTo(0.3, 0.01));

      final rendered = categoryTone(context, unknown.toARGB32());
      final renderedHsl = HSLColor.fromColor(rendered);
      expect(renderedHsl.hue, closeTo(unknownHsl.hue, 1));
      expect(renderedHsl.saturation, closeTo(unknownHsl.saturation, 0.02));
      expect(renderedHsl.lightness, closeTo(unknownHsl.lightness, 0.02));
    });
  });
}

/// Pumps a minimal [MaterialApp] using [theme] as its only theme (so
/// [Theme.of] resolves to it regardless of the test platform's brightness)
/// and returns a [BuildContext] under it.
Future<BuildContext> _pumpAndGetContext(
  WidgetTester tester,
  ThemeData theme,
) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return capturedContext;
}
