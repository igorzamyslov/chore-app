/// The chore form's labelled text-field card (spec `docs/specs/theme-v2.md`
/// §4.4 item 1): a filled `surfaceContainerLow` card, radius 14, with a
/// PERMANENTLY visible uppercase micro-label above the value -- never a
/// floating label that vanishes once typing starts. Reused by the welcome
/// screen's name field too (spec §4.5's "always-visible name field" is the
/// same idea, one screen over).
library;

import 'package:chore_app/app/famdo_colors.dart';
import 'package:flutter/material.dart';

/// A text field wrapped in a labelled card: the border is `primaryOutline`
/// while focused, `outlineVariant` otherwise; the label ink follows the
/// same split (`primary` focused, `onSurfaceVariant` otherwise).
///
/// [errorText] renders as a `bodySmall`/`error` line under the card without
/// ever clearing [controller]'s text -- inline validation that never loses
/// input (design-language rule 7).
class LabelledFieldCard extends StatefulWidget {
  /// Creates a labelled field card wrapping a single [TextField].
  const LabelledFieldCard({
    required this.label,
    required this.controller,
    this.errorText,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  /// The permanently-visible micro-label above the value, in natural case.
  ///
  /// This widget uppercases it for DISPLAY only (`.toUpperCase()`) while
  /// keeping the natural-case string as the accessibility label -- matching
  /// `_SectionHeader`'s established pattern
  /// (`lib/features/chores/chores_list_screen.dart`): German capitalization
  /// rules differ, so the translator must see the natural-case source, and
  /// TalkBack must not shout it.
  final String label;

  /// Backs the field's raw text.
  final TextEditingController controller;

  /// Inline validation error shown below the card, or `null` if valid (or
  /// not yet submitted). Never clears [controller]'s text.
  final String? errorText;

  /// Forwarded to the inner [TextField].
  final TextInputType? keyboardType;

  /// Forwarded to the inner [TextField].
  final int maxLines;

  /// Forwarded to the inner [TextField].
  final int? minLines;

  /// Forwarded to the inner [TextField].
  final TextInputAction? textInputAction;

  /// Forwarded to the inner [TextField] -- called when the user submits via
  /// the keyboard action (e.g. Enter). Load-bearing on the welcome screen's
  /// name field: Enter must be the SOLE submit path there (spec
  /// `docs/specs/onboarding-v2.md`, E2E `e2e/common/onboard_fresh.yaml`).
  final ValueChanged<String>? onSubmitted;

  /// Forwarded to the inner [TextField].
  final bool autofocus;

  @override
  State<LabelledFieldCard> createState() => _LabelledFieldCardState();
}

class _LabelledFieldCardState extends State<LabelledFieldCard> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final famdo = famdoColors(context);
    final borderColor = _focused
        ? famdo.primaryOutline
        : colorScheme.outlineVariant;
    final labelColor = _focused
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: _focused ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: widget.label,
                child: ExcludeSemantics(
                  child: Text(
                    widget.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: labelColor,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: widget.keyboardType,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                textInputAction: widget.textInputAction,
                onSubmitted: widget.onSubmitted,
                autofocus: widget.autofocus,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                ),
              ),
            ],
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
