/// Shared picker building blocks: a fixed-size tappable tile ([PickerTile])
/// and a fixed six-across grid of color swatches drawn from a caller-
/// supplied fixed palette ([ColorSwatchPicker]).
///
/// Originally written for the category edit sheet's icon/color pickers,
/// then extracted here so the member edit sheet (spec
/// `docs/specs/members-management.md` §3) can reuse the same color-swatch
/// widget and palette rather than forking it.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:flutter/material.dart';

/// A 48dp-minimum tappable tile (design-language: touch targets >= 48dp,
/// enforced with sizing, not hope). Used by both the category edit sheet's
/// icon grid and [ColorSwatchPicker].
class PickerTile extends StatelessWidget {
  /// Creates a picker tile wrapping [child].
  const PickerTile({
    required this.isSelected,
    required this.onTap,
    required this.child,
    this.shape = const CircleBorder(),
    super.key,
  });

  /// Whether this tile is the current selection; drawn with a filled
  /// background when true.
  final bool isSelected;

  /// Called when the tile is tapped. `null` renders the tile inert (no ink,
  /// no callback) -- used by [ColorSwatchPicker] for a color another member
  /// has already taken.
  final VoidCallback? onTap;

  /// The tile's content, centered within the 48x48 tappable area.
  final Widget child;

  /// The tile's ink and selection shape. Circular by default (the icon
  /// grid); [ColorSwatchPicker] passes a rounded rectangle to match the
  /// design canvas's swatch.
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: child)),
      ),
    );
  }
}

/// A palette color that is already spoken for, and how to say so.
///
/// Member colors are unique per household (G-4, design canvas frame 1b:
/// "Taking one that is used shows it disabled with the owner's initials on
/// it"), so the member edit sheet marks colors other members hold. The
/// category picker has no such rule and passes none.
class TakenSwatch {
  /// Creates a taken-swatch badge.
  const TakenSwatch({required this.initials, required this.semanticsLabel});

  /// The owner's initials, drawn on the swatch -- so the disabled state is
  /// carried by a glyph and not by color alone
  /// (`docs/specs/design-language.md` color-usage rules).
  final String initials;

  /// The already-localized screen-reader label, e.g. "Taken by Anna".
  final String semanticsLabel;
}

/// The color picker: [colors] drawn as rings, six per row (design canvas
/// frames 1b/1d). The selected swatch is marked two ways -- an outer glow
/// AND a checkmark -- so selection never rides on color alone
/// (`docs/specs/design-language.md` color-usage rules).
///
/// Each swatch is wrapped with `semantic('$semanticIdPrefix.$index', ...)`
/// so callers with different id schemes (the category edit sheet's
/// `settings.categories.color.*`, the member edit sheet's
/// `members.edit.color.*`) can both use this widget unmodified. Those ids
/// are INDEXED and are API (spec `docs/specs/theme-v2.md` §0): pass a
/// [colors] list whose leading entries keep their historical positions.
class ColorSwatchPicker extends StatelessWidget {
  /// Creates a color swatch picker over [colors].
  const ColorSwatchPicker({
    required this.colors,
    required this.selected,
    required this.onSelected,
    required this.semanticIdPrefix,
    this.taken = const {},
    super.key,
  });

  /// How many swatches share a row (design: "both grids stay six across so
  /// the sheet height does not grow past a thumb's reach").
  static const int columns = 6;

  /// The fixed palette of stored ARGB colors to choose from, in display
  /// order. Each is rendered through `categoryTone`, not drawn raw.
  final List<int> colors;

  /// The currently-selected color; must be one of [colors] for its swatch
  /// to render as selected (a value outside [colors] simply selects none).
  final int selected;

  /// Called with the newly-tapped swatch's color.
  final ValueChanged<int> onSelected;

  /// Prefix combined with each swatch's index to form its semantic id.
  final String semanticIdPrefix;

  /// Colors that are unavailable, keyed by stored ARGB value. An entry
  /// renders its swatch inert and badged; the default (`const {}`) makes
  /// every color selectable.
  final Map<int, TakenSwatch> taken;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < colors.length; start += columns) {
      final end = start + columns > colors.length
          ? colors.length
          : start + columns;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: start == 0 ? 0 : 8),
          child: Row(
            children: [
              for (var index = start; index < end; index++)
                Expanded(
                  // Expanded hands its child a TIGHT horizontal constraint,
                  // which PickerTile's SizedBox(width: 48) would resolve to
                  // the full column width -- stretching the tile into a
                  // lozenge on a phone-width sheet. Center shrink-wraps it
                  // back to 48 while Expanded still divides the row into six
                  // equal columns.
                  child: Center(
                    child: semantic(
                      '$semanticIdPrefix.$index',
                      child: _ColorSwatch(
                        // The THEME-RENDERED tone, not the raw stored ARGB.
                        // The swatch is a ring and so is the avatar it
                        // previews, so the two must agree; and four of the
                        // twelve stored values are unreadable drawn raw on
                        // the dark ground. (A comment here once claimed
                        // theme-v2 §1.3 exempted this widget from the tone
                        // map. It does not -- the spec says nothing about
                        // the picker; grep it for "swatch" or "exempt".)
                        tone: categoryTone(context, colors[index]),
                        isSelected: colors[index] == selected,
                        taken: taken[colors[index]],
                        onTap: () => onSelected(colors[index]),
                      ),
                    ),
                  ),
                ),
              // Pad a short final row so its swatches keep the same width
              // as every full row above them.
              for (var filler = end; filler < start + columns; filler++)
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.tone,
    required this.isSelected,
    required this.taken,
    required this.onTap,
  });

  final Color tone;
  final bool isSelected;
  final TakenSwatch? taken;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
    final owner = taken;
    final isTaken = owner != null;
    return PickerTile(
      isSelected: false,
      // Inert, not merely ignored: a null onTap also removes the ink
      // splash, so the swatch does not look pressable.
      onTap: isTaken ? null : onTap,
      shape: shape,
      child: Semantics(
        label: owner?.semanticsLabel,
        enabled: !isTaken,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: tone, width: 2.5),
            boxShadow: isSelected
                ? [
                    // The design's double glow: a surface-colored gap, then
                    // the tone again, so the selected swatch reads as picked
                    // from across the grid.
                    BoxShadow(color: colorScheme.surface, spreadRadius: 2),
                    BoxShadow(color: tone, spreadRadius: 4),
                  ]
                : null,
          ),
          child: switch (owner) {
            final TakenSwatch badge => Text(
              badge.initials,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
            null when isSelected => Icon(Icons.check, color: tone, size: 20),
            null => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}
