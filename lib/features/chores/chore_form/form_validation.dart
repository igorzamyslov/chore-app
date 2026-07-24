/// Pure validation rules for the chore form's required fields.
///
/// Kept separate from the form screen's state so each rule is trivially
/// unit-testable and matches the exact inline error strings the widget test
/// suite (and any E2E test) asserts on.
library;

import 'package:chore_app/data/db/app_database.dart';

/// `'Title is required'` if the already-trimmed [title] is empty, else
/// `null`.
String? validateTitle(String title) {
  return title.isEmpty ? 'Title is required' : null;
}

/// `'Must be at least 1'` unless [raw] parses to an integer >= 1, else
/// `null`.
String? validateInterval(String raw) {
  final parsed = int.tryParse(raw.trim());
  return parsed == null || parsed < 1 ? 'Must be at least 1' : null;
}

/// The assignment validation error for [mode] given [selectedMemberIds], or
/// `null` if valid: `fixed` needs exactly one member, `rotation` needs at
/// least two, `anyone` needs none (and is always valid).
String? validateAssignment({
  required AssignmentMode mode,
  required List<String> selectedMemberIds,
}) {
  switch (mode) {
    case AssignmentMode.fixed:
      return selectedMemberIds.length == 1 ? null : 'Pick one member';
    case AssignmentMode.rotation:
      return selectedMemberIds.length >= 2 ? null : 'Pick at least two';
    case AssignmentMode.anyone:
      return null;
  }
}
