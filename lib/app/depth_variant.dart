/// Prototype widgets for the `cards`/`glassCards` depth variants (see
/// `docs/next-session-plan.md` #6 and [designVariant]). Every widget here is
/// a no-op passthrough while `designVariant == DesignVariant.flat` — the
/// shipped default — so importing this file changes nothing until the
/// switch is flipped.
library;

import 'package:chore_app/app/theme.dart';
import 'package:flutter/material.dart';

/// Wraps [child] in a solid, flat (elevation 0) M3 card for the `cards` and
/// `glassCards` variants; returns [child] unchanged for `flat`.
///
/// Used for occurrence/item tiles and rows so the underlying widget tree
/// (and every finder/semantic id it carries) is preserved — this only adds
/// an ancestor, never replaces anything.
class DepthCard extends StatelessWidget {
  /// Creates a card wrapper around [child]. [margin] defaults to the
  /// symmetric 12/4 spacing the design calls for; pass a tighter value for
  /// rows nested inside an already-padded container (e.g. an
  /// [ExpansionTile]'s children).
  const DepthCard({required this.child, this.margin, super.key});

  /// The content to render inside the card (or as-is, under `flat`).
  final Widget child;

  /// Outer spacing around the card. Defaults to
  /// `EdgeInsets.symmetric(horizontal: 12, vertical: 4)`.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    if (designVariant == DesignVariant.flat) {
      return child;
    }
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Gives header/status text a subtle solid-surface pill backdrop under
/// `glassCards`, so it never sits directly on the gradient wash (hard rule,
/// see the #6 plan). A no-op under `flat`/`cards`.
class DepthTextBackdrop extends StatelessWidget {
  /// Creates a pill backdrop around [child] for `glassCards` only.
  const DepthTextBackdrop({required this.child, super.key});

  /// The text (or text-bearing row) to give a readable backdrop.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (designVariant != DesignVariant.glassCards) {
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: child,
      ),
    );
  }
}

/// The `glassCards` variant's static full-bleed background wash: two large,
/// soft radial gradients (seed-tinted `primaryContainer` /
/// `tertiaryContainer`) over the plain surface color, top-left and
/// bottom-right. Deliberately NOT animated or blurred at runtime (E2E
/// determinism) — the "pre-blurred" look comes from wide gradient stops.
///
/// A no-op passthrough under `flat`/`cards`. Meant to wrap just the
/// scrollable list content, not the whole `Scaffold` body — callers that
/// also render a pinned control above the list (e.g. the shopping quick-add
/// row) keep that control outside this wrapper so its field never sits on
/// the gradient.
class DepthBackground extends StatelessWidget {
  /// Creates the background wash behind [child].
  const DepthBackground({required this.child, super.key});

  /// The content painted on top of the wash.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (designVariant != DesignVariant.glassCards) {
      return child;
    }
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Lower opacity in dark mode keeps contrast intact against the dark
    // surface (design-language contrast rule); light mode can afford a
    // richer wash.
    final primaryOpacity = isDark ? 0.16 : 0.45;
    final tertiaryOpacity = isDark ? 0.12 : 0.35;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: scheme.surface)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -0.9),
                radius: 1.2,
                colors: [
                  scheme.primaryContainer.withValues(alpha: primaryOpacity),
                  scheme.primaryContainer.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, 0.9),
                radius: 1.2,
                colors: [
                  scheme.tertiaryContainer.withValues(alpha: tertiaryOpacity),
                  scheme.tertiaryContainer.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
