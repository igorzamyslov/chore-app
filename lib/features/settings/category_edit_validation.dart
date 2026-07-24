/// Pure validation rules for the category edit sheet's required name field.
///
/// Mirrors `lib/features/shopping/shopping_edit_validation.dart` and
/// `lib/features/chores/chore_form/form_validation.dart`: the rule returns
/// a small error enum (or `null`) rather than a user-facing string, so this
/// file stays a plain, localization-free unit under test; the widget layer
/// maps the enum value to its localized message via `AppLocalizations`.
library;

/// A [validateCategoryName] failure.
enum CategoryNameError {
  /// The already-trimmed name is empty.
  required,
}

/// [CategoryNameError.required] if the already-trimmed [name] is empty,
/// else `null`.
CategoryNameError? validateCategoryName(String name) {
  return name.isEmpty ? CategoryNameError.required : null;
}
