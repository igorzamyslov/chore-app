/// App-wide Material 3 theming and category icon lookup.
library;

import 'package:flutter/material.dart';

/// Prototype switch for docs/next-session-plan.md #6 — flat is the
/// shipped look; the other two exist only for the side-by-side decision.
enum DesignVariant {
  /// The shipped look: no cards, no background wash. Every variant-gated
  /// widget in `lib/app/depth_variant.dart` is a no-op under this value.
  flat,

  /// Solid M3 `surfaceContainerLow` cards around tiles/rows, plain
  /// background.
  cards,

  /// [cards], plus a static seed-tinted gradient wash behind the list.
  glassCards,
}

/// Which [DesignVariant] the app is compiled with. The orchestrator flips
/// this constant to build each variant for a side-by-side screenshot
/// comparison; ship-time default is [DesignVariant.flat].
const DesignVariant designVariant = DesignVariant.flat;

/// The seed color every [ColorScheme] in this app is derived from.
const Color _seedColor = Color(0xFF26A69A);

/// The app's light theme.
final ThemeData appLightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
  appBarTheme: _appBarTheme,
);

/// The app's dark theme.
final ThemeData appDarkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
  ),
  appBarTheme: _appBarTheme,
);

/// App bars left-align their titles on every screen and platform.
///
/// Without this, iOS centers the title on action-less app bars (Shopping)
/// while action-bearing ones (Chores) left-align — visual QA caught the
/// tabs disagreeing with each other.
const AppBarTheme _appBarTheme = AppBarTheme(centerTitle: false);

/// Maps a Material Symbols icon identifier (as used by
/// `CategoryRepository`'s seeded categories, e.g. `cleaning_services`) to an
/// [IconData] constant, falling back to [Icons.label_outlined] for an
/// unrecognized [identifier].
///
/// Icons are always looked up at regular weight and drawn by the caller in
/// the category's own color — flat, not colorful-emoji.
///
/// Two seed identifiers (`skillet`, `nutrition`) have no equivalent in
/// Flutter's bundled Material Icons font (they only exist as Material
/// Symbols, a separate icon set this app doesn't depend on); those map to
/// the closest visual equivalent instead ([Icons.kitchen], [Icons.eco]).
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
    default:
      return Icons.label_outlined;
  }
}
