/// The standard list-card container (spec `docs/specs/theme-v2.md` §3,
/// amending `docs/specs/design-language.md` "Depth / cards").
library;

import 'package:chore_app/app/famdo_colors.dart';
import 'package:flutter/material.dart';

/// Wraps [child] in a solid, flat (elevation 0) M3 card:
/// `colorScheme.surfaceContainerLow`, 16dp corner radius, a 1px
/// `outlineVariant` border, no elevation -- depth here is the border plus
/// (when [shadow] is true) an ambient [FamdoColors.lift] shadow, never M3's
/// elevation/surface-tint math (spec §7.7).
///
/// Used for occurrence/item tiles and rows so the underlying widget tree
/// (and every finder/semantic id it carries) is preserved — this only adds
/// an ancestor, never replaces anything.
class DepthCard extends StatelessWidget {
  /// Creates a card wrapper around [child]. [margin] defaults to the
  /// symmetric 12/4 spacing the design calls for; pass a tighter value for
  /// rows nested inside an already-padded container (e.g. an
  /// [ExpansionTile]'s children). [color] defaults to
  /// `colorScheme.surfaceContainerLow`; the first-run banner cards (spec
  /// `docs/specs/polish-round-1.md` A2/A3) pass `colorScheme.
  /// secondaryContainer` instead so they read as banners, not chores.
  /// [borderColor] defaults to `colorScheme.outlineVariant`; the overdue
  /// occurrence tile passes `FamdoColors.errorOutline` instead. [shadow]
  /// defaults to false (plain list cards get no shadow); pass true for a
  /// raised card (progress card, quick-add, welcome create card).
  const DepthCard({
    required this.child,
    this.margin,
    this.color,
    this.borderColor,
    this.shadow = false,
    super.key,
  });

  /// The content to render inside the card.
  final Widget child;

  /// Outer spacing around the card. Defaults to
  /// `EdgeInsets.symmetric(horizontal: 12, vertical: 4)`.
  final EdgeInsetsGeometry? margin;

  /// The card's fill color. Defaults to `colorScheme.surfaceContainerLow`.
  final Color? color;

  /// The card's 1px border color. Defaults to `colorScheme.outlineVariant`;
  /// the overdue occurrence tile (spec `docs/specs/theme-v2.md` §4.1 item 4,
  /// design option C) passes `FamdoColors.errorOutline` instead.
  final Color? borderColor;

  /// Whether to apply `FamdoColors.lift`'s ambient shadow (spec §3: raised
  /// cards only -- progress card, quick-add, welcome create card).
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(16));
    final card = Card(
      elevation: 0,
      color: color ?? colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borderColor ?? colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ? famdoColors(context).lift : null,
      ),
      child: card,
    );
  }
}
