/// App-wide Material 3 theming (spec `docs/specs/theme-v2.md`): two
/// hand-authored warm light/dark [ColorScheme]s, the Inter [TextTheme],
/// component themes so screens inherit the look without per-widget
/// overrides, the category icon lookup, and the category/member color-tone
/// map.
library;

import 'package:chore_app/app/famdo_colors.dart';
import 'package:flutter/material.dart';

// -----------------------------------------------------------------------
// Public theme instances
// -----------------------------------------------------------------------

/// The app's light theme.
final ThemeData appLightTheme = _buildTheme(
  colorScheme: _lightColorScheme,
  famdo: FamdoColors.light,
);

/// The app's dark theme.
final ThemeData appDarkTheme = _buildTheme(
  colorScheme: _darkColorScheme,
  famdo: FamdoColors.dark,
);

// -----------------------------------------------------------------------
// Color schemes (spec §1.1) -- hand-authored, NOT ColorScheme.fromSeed:
// the tonal-palette algorithm can't express a warm neutral ramp with a
// low-chroma teal accent, which is the entire point of this design.
//
// secondary/tertiary (and their container/on- pairs) mirror primary -- this
// design has no second accent. surfaceContainer(Low/High/Lowest/Highest),
// surfaceDim, surfaceBright and shadow sit on the same warm ramp between
// `surface` and `surfaceContainerHigh` (never Flutter's grey/purple
// defaults, spec §1.1). surfaceTint is set to `surface` so M3's
// elevation-tint math is a no-op -- elevation here is an edge (outlineVariant
// border) plus an ambient FamdoColors shadow, never a surface tint (spec
// §7.7).
// -----------------------------------------------------------------------

const Color _lightPrimary = Color(0xFF1E7A6E);
const Color _lightOnPrimary = Color(0xFFFFFDF9);
const Color _lightPrimaryContainer = Color(0xFFDDEDE8);
const Color _lightOnPrimaryContainer = Color(0xFF0E2622);
const Color _lightSurface = Color(0xFFF6F1E9);

const ColorScheme _lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: _lightPrimary,
  onPrimary: _lightOnPrimary,
  primaryContainer: _lightPrimaryContainer,
  onPrimaryContainer: _lightOnPrimaryContainer,
  secondary: _lightPrimary,
  onSecondary: _lightOnPrimary,
  secondaryContainer: _lightPrimaryContainer,
  onSecondaryContainer: _lightOnPrimaryContainer,
  tertiary: _lightPrimary,
  onTertiary: _lightOnPrimary,
  tertiaryContainer: _lightPrimaryContainer,
  onTertiaryContainer: _lightOnPrimaryContainer,
  error: Color(0xFFB44A2E),
  onError: Color(0xFFFFF6F2),
  errorContainer: Color(0xFFFBEDE7),
  onErrorContainer: Color(0xFFB44A2E),
  surface: _lightSurface,
  onSurface: Color(0xFF241F19),
  onSurfaceVariant: Color(0xFF5A5147),
  outline: Color(0xFFCFC4B2),
  outlineVariant: Color(0xFFE3DACB),
  // #241F19 @ 42% opacity (spec §1.1).
  scrim: Color(0x6B241F19),
  inverseSurface: Color(0xFF2B2620),
  onInverseSurface: Color(0xFFF3EDE4),
  inversePrimary: Color(0xFF6FC7B7),
  // A no-op tint (see the section comment above).
  surfaceTint: _lightSurface,
  surfaceContainerLowest: Color(0xFFFFFEFB),
  surfaceContainerLow: Color(0xFFFFFDF9),
  surfaceContainer: Color(0xFFF3EDE4),
  surfaceContainerHigh: Color(0xFFEFE8DD),
  surfaceContainerHighest: Color(0xFFEDE5D9),
  surfaceDim: Color(0xFFE9E1D3),
  surfaceBright: Color(0xFFF9F5EE),
  shadow: Color(0xFFE9E1D3),
);

const Color _darkPrimary = Color(0xFF63C9B8);
const Color _darkOnPrimary = Color(0xFF0E2622);
const Color _darkPrimaryContainer = Color(0xFF1D3833);
const Color _darkOnPrimaryContainer = Color(0xFFB9D8D0);
const Color _darkSurface = Color(0xFF161311);

const ColorScheme _darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: _darkPrimary,
  onPrimary: _darkOnPrimary,
  primaryContainer: _darkPrimaryContainer,
  onPrimaryContainer: _darkOnPrimaryContainer,
  secondary: _darkPrimary,
  onSecondary: _darkOnPrimary,
  secondaryContainer: _darkPrimaryContainer,
  onSecondaryContainer: _darkOnPrimaryContainer,
  tertiary: _darkPrimary,
  onTertiary: _darkOnPrimary,
  tertiaryContainer: _darkPrimaryContainer,
  onTertiaryContainer: _darkOnPrimaryContainer,
  error: Color(0xFFE58A6C),
  onError: Color(0xFF2A120A),
  errorContainer: Color(0xFF241812),
  onErrorContainer: Color(0xFFE58A6C),
  surface: _darkSurface,
  onSurface: Color(0xFFF0E9DF),
  onSurfaceVariant: Color(0xFFB6AA9C),
  outline: Color(0xFF4A4137),
  outlineVariant: Color(0xFF332C25),
  // #0A0806 @ 64% opacity (spec §1.1).
  scrim: Color(0xA30A0806),
  inverseSurface: Color(0xFFEFE7DC),
  onInverseSurface: Color(0xFF231E19),
  inversePrimary: Color(0xFF1E7A6E),
  // A no-op tint (see the section comment above).
  surfaceTint: _darkSurface,
  surfaceContainerLowest: Color(0xFF131110),
  surfaceContainerLow: Color(0xFF211C18),
  surfaceContainer: Color(0xFF181513),
  surfaceContainerHigh: Color(0xFF1C1815),
  surfaceContainerHighest: Color(0xFF1E1A16),
  surfaceDim: Color(0xFF100E0D),
  surfaceBright: Color(0xFF221D19),
  shadow: Color(0xFF100E0D),
);

// -----------------------------------------------------------------------
// Typography (spec §2) -- Inter, bundled as static TTFs. Only geometry
// (size/weight/letter-spacing) is set here, never color: `ThemeData` merges
// this on top of `Typography.material2021(colorScheme: ...)`'s
// colorScheme-derived text theme, so every role already inherits the right
// onSurface-family color for whichever ColorScheme it's merged onto --
// baking a color in here would instead hardcode ONE brightness's color into
// both themes. Widgets that need a different role (e.g. onSurfaceVariant
// metadata text) apply that with an explicit `.copyWith(color: ...)` at the
// call site, same as before this wave.
//
// The design's weights 550/650 don't exist as static cuts; both map to
// FontWeight.w600 (spec §2). displayLarge/Medium/Small and headlineLarge
// aren't named in spec §2's table (no current screen uses them) but are
// still given Inter/a size on the same scale, so nothing silently falls
// back to the system font if a future widget ever reaches for one.
// -----------------------------------------------------------------------

const String _interFontFamily = 'Inter';

const TextTheme _textTheme = TextTheme(
  displayLarge: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 57,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
  ),
  displayMedium: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 45,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
  ),
  displaySmall: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w600,
    letterSpacing: -1,
  ),
  // Larger than headlineMedium on purpose: spec §2 pins headlineMedium at
  // 32 (the Welcome wordmark), so an unnamed headlineLarge has to sit
  // ABOVE it or a caller reaching for "large" would silently get smaller
  // text than "medium".
  headlineLarge: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -1,
  ),
  headlineMedium: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.9,
  ),
  headlineSmall: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  ),
  titleLarge: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  ),
  titleMedium: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.15,
  ),
  titleSmall: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
  ),
  bodyLarge: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
  ),
  bodyMedium: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  ),
  bodySmall: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
  ),
  labelLarge: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  ),
  labelMedium: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
  ),
  labelSmall: TextStyle(
    fontFamily: _interFontFamily,
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  ),
);

// -----------------------------------------------------------------------
// Component themes (spec §3) -- so screens inherit the look without
// per-widget overrides. Every card-like surface stays `elevation: 0` (spec
// §7.7): depth comes from a 1px outlineVariant border, plus (waves T2+) a
// FamdoColors ambient shadow applied by the widget itself, never from M3's
// elevation/surface-tint math.
// -----------------------------------------------------------------------

ThemeData _buildTheme({
  required ColorScheme colorScheme,
  required FamdoColors famdo,
}) {
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  const buttonMinimumSize = Size(64, 48);

  return ThemeData(
    colorScheme: colorScheme,
    textTheme: _textTheme,
    extensions: [famdo],
    appBarTheme: AppBarThemeData(
      centerTitle: false,
      backgroundColor: colorScheme.surface,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: _textTheme.headlineSmall?.copyWith(
        color: colorScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        minimumSize: buttonMinimumSize,
        textStyle: _textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        minimumSize: buttonMinimumSize,
        textStyle: _textTheme.labelLarge,
      ),
    ),
    // Selected/unselected fill and border are set here; label-text color is
    // deliberately left to each chip variant's own Material-3 default
    // (ChipThemeData.labelStyle is a single fixed TextStyle, not a
    // WidgetStateProperty, so it can't express spec §3's "onSurface
    // selected / onSurfaceVariant unselected" split at the theme level --
    // see the wave report).
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return BorderSide(color: famdo.primaryOutline);
        }
        return BorderSide(color: colorScheme.outlineVariant);
      }),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primaryContainer;
        }
        return colorScheme.surfaceContainerLow;
      }),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      modalBackgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: colorScheme.outlineVariant,
      dragHandleSize: const Size(34, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: _textTheme.bodyMedium?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      actionTextColor: colorScheme.inversePrimary,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: famdo.primaryOutline, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainerHigh,
        foregroundColor: colorScheme.onSurfaceVariant,
        selectedBackgroundColor: colorScheme.surfaceContainerLow,
        selectedForegroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: _textTheme.labelLarge,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colorScheme.onPrimary
            : colorScheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colorScheme.primary
            : colorScheme.surfaceContainerHigh;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : colorScheme.outline;
      }),
    ),
  );
}

/// Maps a Material Symbols icon identifier (as used by
/// `CategoryRepository`'s seeded categories, e.g. `cleaning_services`) to an
/// [IconData] constant, falling back to [Icons.label_outlined] for an
/// unrecognized [identifier].
///
/// Icons are always looked up at regular weight and drawn by the caller in
/// the category's own color — flat, not colorful-emoji.
///
/// Three identifiers (`skillet`, `nutrition`, `potted_plant`) have no
/// equivalent in Flutter's bundled Material Icons font (they only exist as
/// Material Symbols, a separate icon set this app doesn't depend on); those
/// map to the closest visual equivalent instead ([Icons.kitchen],
/// [Icons.eco], [Icons.local_florist]).
///
/// Every case here must stay in step with `categoryIconIdentifiers`
/// (`lib/features/categories/category_icons.dart`): an identifier offered by
/// the picker but missing a case here falls through to the `default` branch
/// and renders as a plausible-looking but duplicated tile. That invariant is
/// pinned by a test — see `test/app/theme_test.dart`.
IconData categoryIcon(String identifier) {
  switch (identifier) {
    case 'cleaning_services':
      return Icons.cleaning_services;
    case 'skillet':
      return Icons.kitchen;
    case 'local_laundry_service':
      return Icons.local_laundry_service;
    case 'yard':
      return Icons.yard;
    case 'pets':
      return Icons.pets;
    case 'build':
      return Icons.build;
    case 'directions_car':
      return Icons.directions_car;
    case 'nutrition':
      return Icons.eco;
    case 'egg':
      return Icons.egg;
    case 'set_meal':
      return Icons.set_meal;
    case 'bakery_dining':
      return Icons.bakery_dining;
    case 'ac_unit':
      return Icons.ac_unit;
    case 'local_cafe':
      return Icons.local_cafe;
    case 'home':
      return Icons.home;
    case 'shopping_bag':
      return Icons.shopping_bag;
    case 'bathtub':
      return Icons.bathtub;
    case 'delete':
      // The "bins" category's trash-can glyph -- shares its identifier
      // name with the app's actual delete actions elsewhere, which is a
      // naming coincidence in Material's icon set, not a collision:
      // IconData values carry no behavior, only a glyph.
      return Icons.delete;
    case 'potted_plant':
      // No bundled-Flutter equivalent (Material Symbols only, same gap as
      // skillet/nutrition above) -- local_florist is the closest visual
      // match not already taken by 'yard' (outdoor garden).
      return Icons.local_florist;
    case 'child_care':
      return Icons.child_care;
    case 'pedal_bike':
      return Icons.pedal_bike;
    case 'description':
      return Icons.description;
    case 'celebration':
      return Icons.celebration;
    case 'thermostat':
      return Icons.thermostat;
    case 'fitness_center':
      return Icons.fitness_center;
    default:
      return Icons.label_outlined;
  }
}

// -----------------------------------------------------------------------
// Category / member tone mapping (spec §1.3).
// -----------------------------------------------------------------------

/// One seeded color's hand-picked light/dark render.
typedef _ToneRender = ({Color light, Color dark});

/// The eight `CategoryRepository.seedColors` (shared by categories and
/// members), each mapped to its light/dark render (spec §1.3 table): drawn
/// raw, none of them clears 4.5:1 on both grounds at the 12sp category-label
/// size, so the theme darkens them on paper and lightens them on the dark
/// ground.
const Map<int, _ToneRender> _categoryTones = {
  0xFF6D9F71: (light: Color(0xFF4E7E54), dark: Color(0xFF93C297)), // Cleaning
  0xFF8C7BC9: (light: Color(0xFF6B57B0), dark: Color(0xFFB4A5E8)), // Kitchen
  0xFFD98E73: (light: Color(0xFFB96A4C), dark: Color(0xFFF0AF95)), // Laundry
  0xFF5FA8B8: (light: Color(0xFF3F8697), dark: Color(0xFF8ACBD9)), // Garden
  0xFFC98CA7: (light: Color(0xFFA86485), dark: Color(0xFFE7AEC6)), // Pets
  0xFFB8A15F: (
    light: Color(0xFF8E7833),
    dark: Color(0xFFDBC585),
  ), // Maintenance
  0xFF7B93C9: (light: Color(0xFF5A73AD), dark: Color(0xFFA4B8E5)), // Errands
  0xFFA9A9A9: (light: Color(0xFF77716A), dark: Color(0xFFC8C4BE)), // Other
};

/// The lightness ceiling an unknown color is clamped to for the light
/// theme (spec §1.3).
const double _unknownToneLightMaxLightness = 0.42;

/// The lightness floor an unknown color is clamped to for the dark theme
/// (spec §1.3).
const double _unknownToneDarkMinLightness = 0.70;

/// Renders [storedArgb] (a category or member's stored color) for the
/// current theme brightness (spec `docs/specs/theme-v2.md` §1.3).
///
/// The eight `CategoryRepository.seedColors` resolve through the hand-picked
/// table above; any other stored value (a future picker, an imported
/// archive) falls back to an HSL lightness clamp -- light theme: at most
/// [_unknownToneLightMaxLightness]; dark theme: at least
/// [_unknownToneDarkMinLightness] -- preserving hue and saturation so an
/// unknown color degrades gracefully instead of becoming unreadable.
///
/// [storedArgb] itself is never rewritten by this call: the remap is
/// render-time only, so sync/export never sees a changed value.
Color categoryTone(BuildContext context, int storedArgb) {
  final brightness = Theme.of(context).colorScheme.brightness;
  final tone = _categoryTones[storedArgb];
  if (tone != null) {
    return brightness == Brightness.dark ? tone.dark : tone.light;
  }
  final hsl = HSLColor.fromColor(Color(storedArgb));
  final clampedLightness = brightness == Brightness.dark
      ? _atLeast(hsl.lightness, _unknownToneDarkMinLightness)
      : _atMost(hsl.lightness, _unknownToneLightMaxLightness);
  return hsl.withLightness(clampedLightness).toColor();
}

double _atLeast(double value, double minimum) =>
    value < minimum ? minimum : value;

double _atMost(double value, double maximum) =>
    value > maximum ? maximum : value;
