/// Pure validation rules for the chore form's required fields.
///
/// Each rule returns a small error enum (or `null`) rather than a
/// user-facing string, so this file stays a plain, localization-free unit
/// under test; the widget layer (`ChoreFormScreen`) maps each enum value to
/// its localized message via `AppLocalizations`. Kept separate from the
/// form screen's state so each rule is trivially unit-testable without a
/// `BuildContext`.
library;

import 'package:chore_app/data/db/app_database.dart';

/// A [validateTitle] failure.
enum TitleError {
  /// The already-trimmed title is empty.
  required,
}

/// [TitleError.required] if the already-trimmed [title] is empty, else
/// `null`.
TitleError? validateTitle(String title) {
  return title.isEmpty ? TitleError.required : null;
}

/// A [validateInterval] failure.
enum IntervalError {
  /// The parsed value is missing, or less than 1.
  tooSmall,
}

/// [IntervalError.tooSmall] unless [raw] parses to an integer >= 1, else
/// `null`.
IntervalError? validateInterval(String raw) {
  final parsed = int.tryParse(raw.trim());
  return parsed == null || parsed < 1 ? IntervalError.tooSmall : null;
}

/// A [validateAssignment] failure.
enum AssignmentError {
  /// `fixed` mode doesn't have exactly one member selected.
  needsOneMember,

  /// `rotation` mode has fewer than two members selected.
  needsTwoMembers,
}

/// The assignment validation error for [mode] given [selectedMemberIds], or
/// `null` if valid: `fixed` needs exactly one member, `rotation` needs at
/// least two, `anyone` needs none (and is always valid).
AssignmentError? validateAssignment({
  required AssignmentMode mode,
  required List<String> selectedMemberIds,
}) {
  switch (mode) {
    case AssignmentMode.fixed:
      return selectedMemberIds.length == 1
          ? null
          : AssignmentError.needsOneMember;
    case AssignmentMode.rotation:
      return selectedMemberIds.length >= 2
          ? null
          : AssignmentError.needsTwoMembers;
    case AssignmentMode.anyone:
      return null;
  }
}
