/// A shared "explanatory radio card" for the chore form's two-option repeat
/// choices (spec `docs/specs/theme-v2.md` §4.4 item 4): the recurrence
/// anchor (fixed schedule vs. after last completion, `AnchorRow`) and the
/// monthly mode (day-of-month vs. nth weekday, `MonthlyModeRow`) each render
/// as two of these instead of a bare `ListTile` radio row.
library;

import 'package:chore_app/app/famdo_colors.dart';
import 'package:flutter/material.dart';

/// A single explanatory radio card: a radio glyph, a `titleSmall` title,
/// and an optional `bodySmall` subtitle explaining what picking this option
/// means in concrete terms (never a generic example).
///
/// Selected = `primaryContainer` fill + `primaryOutline` border; unselected
/// = `surfaceContainerLow` fill + `outlineVariant` border.
class RepeatRadioCard extends StatelessWidget {
  /// Creates a radio card.
  const RepeatRadioCard({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  /// Whether this card is the currently-chosen option.
  final bool selected;

  /// The option's `titleSmall` title.
  final String title;

  /// The option's `bodySmall` explanatory subtitle, or `null` when the
  /// title alone is self-explanatory (e.g. the monthly-mode cards).
  final String? subtitle;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final famdo = famdoColors(context);
    final fillColor = selected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLow;
    final borderColor = selected
        ? famdo.primaryOutline
        : colorScheme.outlineVariant;
    final radioColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final subtitleText = subtitle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: selected ? 2 : 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: radioColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        if (subtitleText != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitleText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
