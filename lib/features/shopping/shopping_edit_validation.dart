/// Pure validation rules for the shopping item edit sheet's required field.
///
/// Kept separate from the sheet's state, mirroring
/// `lib/features/chores/chore_form/form_validation.dart`: the rule returns
/// a small error enum (or `null`) rather than a user-facing string, so this
/// file stays a plain, localization-free unit under test; the widget layer
/// (`_ShoppingEditSheet`) maps the enum value to its localized message via
/// `AppLocalizations`.
library;

/// A [validateItemName] failure.
enum ItemNameError {
  /// The already-trimmed name is empty.
  required,
}

/// [ItemNameError.required] if the already-trimmed [name] is empty, else
/// `null`.
ItemNameError? validateItemName(String name) {
  return name.isEmpty ? ItemNameError.required : null;
}
