/// The standard list-card container (see `docs/specs/design-language.md`
/// "Depth / cards").
library;

import 'package:flutter/material.dart';

/// Wraps [child] in a solid, flat (elevation 0) M3 card:
/// `colorScheme.surfaceContainerLow`, 12dp corner radius, no elevation.
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
  const DepthCard({required this.child, this.margin, this.color, super.key});

  /// The content to render inside the card.
  final Widget child;

  /// Outer spacing around the card. Defaults to
  /// `EdgeInsets.symmetric(horizontal: 12, vertical: 4)`.
  final EdgeInsetsGeometry? margin;

  /// The card's fill color. Defaults to `colorScheme.surfaceContainerLow`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
