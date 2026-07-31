/// Shared circular-picker building blocks: a fixed-size tappable tile
/// ([PickerTile]) and a wrapped row of color swatches drawn from a caller-
/// supplied fixed palette ([ColorSwatchPicker]).
///
/// Originally written for the category edit sheet's icon/color pickers,
/// then extracted here so the member edit sheet (spec
/// `docs/specs/members-management.md` §3) can reuse the same color-swatch
/// widget and palette rather than forking it.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:flutter/material.dart';

/// A 48dp-minimum tappable circular tile (design-language: touch targets
/// >= 48dp, enforced with sizing, not hope). Used by both the category
/// edit sheet's icon grid and [ColorSwatchPicker].
class PickerTile extends StatelessWidget {
  /// Creates a picker tile wrapping [child].
  const PickerTile({
    required this.isSelected,
    required this.onTap,
    required this.child,
    super.key,
  });

  /// Whether this tile is the current selection; drawn with a filled
  /// background when true.
  final bool isSelected;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// The tile's content, centered within the 48x48 tappable area.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: child)),
      ),
    );
  }
}

/// The color picker: a wrapped row of [colors] swatches, each a
/// [PickerTile]. The selected swatch is marked two ways — a contrasting
/// border ring AND a checkmark — so selection never rides on color alone
/// (`docs/specs/design-language.md` color-usage rules).
///
/// Each swatch is wrapped with `semantic('$semanticIdPrefix.$index', ...)`
/// so callers with different id schemes (the category edit sheet's
/// `settings.categories.color.*`, the member edit sheet's
/// `members.edit.color.*`) can both use this widget unmodified.
class ColorSwatchPicker extends StatelessWidget {
  /// Creates a color swatch picker over [colors].
  const ColorSwatchPicker({
    required this.colors,
    required this.selected,
    required this.onSelected,
    required this.semanticIdPrefix,
    super.key,
  });

  /// The fixed palette of ARGB colors to choose from, in display order.
  final List<int> colors;

  /// The currently-selected color; must be one of [colors] for its swatch
  /// to render as selected (a value outside [colors] simply selects none).
  final int selected;

  /// Called with the newly-tapped swatch's color.
  final ValueChanged<int> onSelected;

  /// Prefix combined with each swatch's index to form its semantic id.
  final String semanticIdPrefix;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < colors.length; index++)
          semantic(
            '$semanticIdPrefix.$index',
            child: _ColorSwatch(
              color: Color(colors[index]),
              isSelected: colors[index] == selected,
              ringColor: onSurface,
              onTap: () => onSelected(colors[index]),
            ),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.ringColor,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final Color ringColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return PickerTile(
      isSelected: false,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: ringColor, width: 2) : null,
        ),
        child: isSelected
            ? Icon(Icons.check, color: checkColor, size: 18)
            : null,
      ),
    );
  }
}
