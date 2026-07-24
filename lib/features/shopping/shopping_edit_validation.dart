/// Pure validation rules for the shopping item edit sheet's required field.
///
/// Kept separate from the sheet's state, mirroring
/// `lib/features/chores/chore_form/form_validation.dart`, so the rule is
/// trivially unit-testable and matches the exact inline error string the
/// widget test suite asserts on.
library;

/// `'Name is required'` if the already-trimmed [name] is empty, else `null`.
String? validateItemName(String name) {
  return name.isEmpty ? 'Name is required' : null;
}
