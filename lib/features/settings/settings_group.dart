/// The Settings tab's reusable "labelled group" building blocks (spec
/// `docs/specs/theme-v2.md` §4.2): a [SettingsGroup] renders an uppercase
/// section header followed by one card of hairline-separated [SettingsRow]s,
/// replacing the flat `ListView` of unrelated rows the pre-theme-v2 screen
/// used.
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:flutter/material.dart';

/// A labelled group of settings rows: a `labelSmall` uppercase header in
/// `onSurfaceVariant`, followed by one [DepthCard] whose [children] are
/// separated by 1px `outlineVariant` hairlines -- never a hairline after the
/// last row.
///
/// [label] is uppercased by this widget (`.toUpperCase()`), never by an
/// already-uppercase ARB string -- German capitalization rules differ, so
/// the translator must see (and translate) the natural-case source.
class SettingsGroup extends StatelessWidget {
  /// Creates a labelled settings group. [children] are typically
  /// [SettingsRow]s, but the Household group's first child wraps the
  /// existing (non-decomposed) Account section body instead (spec
  /// `docs/feedback/2026-08-07-field-feedback.md` B2).
  const SettingsGroup({required this.label, required this.children, super.key});

  /// The group's natural-case header text, e.g. "Household".
  final String label;

  /// The card's rows, hairline-separated in the order given.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Left inset (28 = the card's own 12dp margin + its rows' 16dp
          // content padding) lines the header text up with the row titles
          // below it, rather than with the card's outer edge.
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
          // Uppercase is typography, not content: the natural-case label
          // stays as the accessibility label so TalkBack announces
          // "Household", not "HOUSEHOLD".
          child: Semantics(
            label: label,
            child: ExcludeSemantics(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        DepthCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(height: 1, thickness: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single row inside a [SettingsGroup]'s card: a leading 21dp icon
/// (`onSurfaceVariant`, or `error` when [destructive]), a `titleSmall` label
/// with an optional `bodySmall` sub-line, and at most one trailing element --
/// a value, a switch, or a chevron, never two. A row showing a value never
/// also shows a chevron, even when tapping it opens something -- the value
/// replaces it.
class SettingsRow extends StatelessWidget {
  /// Creates a settings row. Exactly one of [value], [onSwitchChanged] (to
  /// show a switch) or [showChevron] may be used at a time -- passing more
  /// than one trips an assertion.
  const SettingsRow({
    required this.icon,
    required this.label,
    this.sublabel,
    this.value,
    this.switchValue,
    this.onSwitchChanged,
    this.showChevron = false,
    this.destructive = false,
    this.onTap,
    super.key,
  }) : assert(
         (value != null ? 1 : 0) +
                 (onSwitchChanged != null ? 1 : 0) +
                 (showChevron ? 1 : 0) <=
             1,
         'A SettingsRow shows at most one trailing element -- a value, a '
         'switch, or a chevron -- never two.',
       );

  /// The row's leading glyph, drawn at 21dp.
  final IconData icon;

  /// The row's `titleSmall` label.
  final String label;

  /// An optional `bodySmall` sub-line under [label].
  final String? sublabel;

  /// The current value shown at trailing, in `bodyLarge`/`onSurfaceVariant`
  /// -- mutually exclusive with [onSwitchChanged] and [showChevron].
  final String? value;

  /// The trailing switch's current state, when this row shows one. Ignored
  /// unless [onSwitchChanged] is also set.
  final bool? switchValue;

  /// Non-null makes this row show a trailing switch instead of a value or a
  /// chevron. Called with the flipped state both when the switch itself is
  /// tapped and when the row is tapped anywhere else (mirroring
  /// `SwitchListTile`, whose whole tile toggles the switch).
  final ValueChanged<bool>? onSwitchChanged;

  /// Whether to show a trailing chevron (the row opens something).
  final bool showChevron;

  /// Whether this is a destructive row -- icon and label draw in `error`.
  final bool destructive;

  /// Called when the row is tapped. Ignored when [onSwitchChanged] is set,
  /// which drives the row's tap behavior instead.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = destructive
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final labelColor = destructive ? colorScheme.error : colorScheme.onSurface;
    final switchChanged = onSwitchChanged;

    // At large text scales a trailing value takes so much of the row that
    // `ListTile` squeezes the label into a column narrower than one word --
    // visual QA at text scale 2.0 rendered "Language" as "Langu / age"
    // (spec `docs/specs/theme-v2.md` §5 makes 2.0 a release gate). Above
    // 1.3x the value moves BELOW the label instead, which is the ordinary
    // responsive answer and keeps both readable.
    final stackValueUnderLabel =
        value != null && MediaQuery.textScalerOf(context).scale(1) > 1.3;

    Widget? trailing;
    if (value != null && !stackValueUnderLabel) {
      trailing = Text(
        value!,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    } else if (switchChanged != null) {
      trailing = Switch(
        value: switchValue ?? false,
        onChanged: switchChanged,
      );
    } else if (showChevron) {
      trailing = Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant);
    }

    return ListTile(
      leading: Icon(icon, size: 21, color: iconColor),
      title: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(color: labelColor),
      ),
      subtitle: switch ((sublabel, stackValueUnderLabel)) {
        (null, false) => null,
        (final String sub, false) => Text(
          sub,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        // Value stacked under the label (see stackValueUnderLabel above);
        // when the row also has a sub-line, both stack, sub-line first.
        (final String? sub, true) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sub != null)
              Text(
                sub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              value!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      },
      trailing: trailing,
      onTap: switchChanged != null
          ? () => switchChanged(!(switchValue ?? false))
          : onTap,
    );
  }
}
