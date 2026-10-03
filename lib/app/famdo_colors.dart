/// The theme roles Material 3's [ColorScheme] has no slot for (spec
/// `docs/specs/theme-v2.md` §1.2): accent-outline/error-chip colors, the
/// success/warning due-tone colors, the
/// member-avatar initial ink, the bottom tab bar ground, and the three
/// custom ambient-shadow lists this design uses instead of M3's surface-tint
/// elevation (spec §7.7).
library;

import 'package:flutter/material.dart';

/// Theme roles beyond Material 3's [ColorScheme], registered on both
/// [ThemeData.extensions] (see `appLightTheme`/`appDarkTheme` in
/// `lib/app/theme.dart`).
///
/// Read via the [famdoColors] helper, never via a global constant --
/// [FamdoColors.light]/[FamdoColors.dark] exist so `appLightTheme` and
/// `appDarkTheme` have something to register, not for callers to read
/// directly, or the light/dark switch would silently stop working.
@immutable
class FamdoColors extends ThemeExtension<FamdoColors> {
  /// Creates a set of Famdo-specific theme roles.
  const FamdoColors({
    required this.primaryOutline,
    required this.errorOutline,
    required this.errorChip,
    required this.success,
    required this.successContainer,
    required this.successOutline,
    required this.successChip,
    required this.warning,
    required this.warningContainer,
    required this.warningOutline,
    required this.warningChip,
    required this.onMemberColor,
    required this.navBarBackground,
    required this.lift,
    required this.fabShadow,
    required this.sheetShadow,
  });

  /// Border color for accent-bordered cards and selected chips.
  final Color primaryOutline;

  /// Border color for an occurrence tile overdue by 7 or more days.
  final Color errorOutline;

  /// Ground color for the due-chip of a tile overdue by 7 or more days.
  final Color errorChip;

  /// Accent (left edge, header label) for a tile due today -- the
  /// success counterpart of `ColorScheme.error`.
  final Color success;

  /// Ground color for a tile due today.
  final Color successContainer;

  /// Border color for a tile due today.
  final Color successOutline;

  /// Ground color for a success-toned due-chip.
  final Color successChip;

  /// Accent and due-chip ink for a tile overdue by fewer than 7 days.
  final Color warning;

  /// Ground color for a tile overdue by fewer than 7 days.
  final Color warningContainer;

  /// Border color for a tile overdue by fewer than 7 days.
  final Color warningOutline;

  /// Ground color for the due-chip of a tile overdue by fewer than 7 days.
  final Color warningChip;

  /// Ink color for the initial drawn on a member avatar -- paired with
  /// `categoryTone`'s fill so every avatar clears contrast by construction
  /// (`lib/features/members/member_avatar.dart` no longer derives this from
  /// the fill color itself).
  final Color onMemberColor;

  /// Ground color for the bottom tab bar.
  final Color navBarBackground;

  /// Ambient shadow for raised cards (progress card, quick-add, welcome
  /// create card) -- plain list cards get no shadow at all.
  final List<BoxShadow> lift;

  /// Ambient shadow under the FAB.
  final List<BoxShadow> fabShadow;

  /// Ambient shadow above a modal bottom sheet.
  final List<BoxShadow> sheetShadow;

  /// The light-theme instance, registered on [ThemeData.extensions] by
  /// `appLightTheme`.
  static const FamdoColors light = FamdoColors(
    primaryOutline: Color(0xFFB9D8D0),
    errorOutline: Color(0xFFEBD2C6),
    errorChip: Color(0xFFF4DDD3),
    success: Color(0xFF3D7531),
    successContainer: Color(0xFFEEF4E6),
    successOutline: Color(0xFFD2E2C3),
    successChip: Color(0xFFDDEAD0),
    warning: Color(0xFF8C5A0C),
    warningContainer: Color(0xFFFBF2E1),
    warningOutline: Color(0xFFEEDDB9),
    warningChip: Color(0xFFF5E5C4),
    onMemberColor: Color(0xFFFFFFFF),
    navBarBackground: Color(0xFFF1EBE1),
    lift: [
      BoxShadow(color: Color(0x0D3C2D19), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(
        color: Color(0x0D3C2D19),
        offset: Offset(0, 6),
        blurRadius: 18,
      ),
    ],
    fabShadow: [
      BoxShadow(
        color: Color(0x4D1E7A6E),
        offset: Offset(0, 8),
        blurRadius: 22,
      ),
    ],
    sheetShadow: [
      BoxShadow(
        color: Color(0x2E281E0F),
        offset: Offset(0, -8),
        blurRadius: 40,
      ),
    ],
  );

  /// The dark-theme instance, registered on [ThemeData.extensions] by
  /// `appDarkTheme`.
  static const FamdoColors dark = FamdoColors(
    primaryOutline: Color(0xFF2C544C),
    errorOutline: Color(0xFF43291D),
    errorChip: Color(0xFF3A241A),
    success: Color(0xFF9CC77D),
    successContainer: Color(0xFF161E12),
    successOutline: Color(0xFF2D4123),
    successChip: Color(0xFF22301A),
    warning: Color(0xFFE2B062),
    warningContainer: Color(0xFF231C10),
    warningOutline: Color(0xFF46361A),
    warningChip: Color(0xFF3A2D15),
    onMemberColor: Color(0xFF1A1612),
    navBarBackground: Color(0xFF1B1714),
    lift: [
      BoxShadow(color: Color(0x08FFFFFF), offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x59000000),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
    fabShadow: [
      BoxShadow(
        color: Color(0x80000000),
        offset: Offset(0, 8),
        blurRadius: 26,
      ),
    ],
    sheetShadow: [
      BoxShadow(
        color: Color(0x8C000000),
        offset: Offset(0, -10),
        blurRadius: 44,
      ),
    ],
  );

  @override
  FamdoColors copyWith({
    Color? primaryOutline,
    Color? errorOutline,
    Color? errorChip,
    Color? success,
    Color? successContainer,
    Color? successOutline,
    Color? successChip,
    Color? warning,
    Color? warningContainer,
    Color? warningOutline,
    Color? warningChip,
    Color? onMemberColor,
    Color? navBarBackground,
    List<BoxShadow>? lift,
    List<BoxShadow>? fabShadow,
    List<BoxShadow>? sheetShadow,
  }) {
    return FamdoColors(
      primaryOutline: primaryOutline ?? this.primaryOutline,
      errorOutline: errorOutline ?? this.errorOutline,
      errorChip: errorChip ?? this.errorChip,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      successOutline: successOutline ?? this.successOutline,
      successChip: successChip ?? this.successChip,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      warningOutline: warningOutline ?? this.warningOutline,
      warningChip: warningChip ?? this.warningChip,
      onMemberColor: onMemberColor ?? this.onMemberColor,
      navBarBackground: navBarBackground ?? this.navBarBackground,
      lift: lift ?? this.lift,
      fabShadow: fabShadow ?? this.fabShadow,
      sheetShadow: sheetShadow ?? this.sheetShadow,
    );
  }

  @override
  FamdoColors lerp(ThemeExtension<FamdoColors>? other, double t) {
    if (other is! FamdoColors) {
      return this;
    }
    return FamdoColors(
      primaryOutline: Color.lerp(primaryOutline, other.primaryOutline, t)!,
      errorOutline: Color.lerp(errorOutline, other.errorOutline, t)!,
      errorChip: Color.lerp(errorChip, other.errorChip, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      successOutline: Color.lerp(successOutline, other.successOutline, t)!,
      successChip: Color.lerp(successChip, other.successChip, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      warningOutline: Color.lerp(warningOutline, other.warningOutline, t)!,
      warningChip: Color.lerp(warningChip, other.warningChip, t)!,
      onMemberColor: Color.lerp(onMemberColor, other.onMemberColor, t)!,
      navBarBackground: Color.lerp(
        navBarBackground,
        other.navBarBackground,
        t,
      )!,
      lift: BoxShadow.lerpList(lift, other.lift, t) ?? lift,
      fabShadow: BoxShadow.lerpList(fabShadow, other.fabShadow, t) ?? fabShadow,
      sheetShadow:
          BoxShadow.lerpList(sheetShadow, other.sheetShadow, t) ?? sheetShadow,
    );
  }
}

/// Returns the [FamdoColors] registered on the current [Theme].
///
/// Throws a [StateError] if none is registered, so a caller never has to
/// null-assert `Theme.of(context).extension<FamdoColors>()` inline --
/// `appLightTheme` and `appDarkTheme` (`lib/app/theme.dart`) both always
/// register one, so this only fails if some other [ThemeData] (a bare one
/// in a test, say) is pumped without it.
FamdoColors famdoColors(BuildContext context) {
  final extension = Theme.of(context).extension<FamdoColors>();
  if (extension == null) {
    throw StateError(
      'No FamdoColors registered on the current Theme -- pump appLightTheme '
      'or appDarkTheme (lib/app/theme.dart), or register '
      'FamdoColors.light or FamdoColors.dark on ThemeData.extensions '
      'directly.',
    );
  }
  return extension;
}
