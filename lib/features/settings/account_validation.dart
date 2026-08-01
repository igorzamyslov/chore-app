/// Pure "plausible email" check gating the Account section's 'Send sign-in
/// link' button.
///
/// Deliberately not full RFC 5322 validation -- that job effectively
/// belongs to the magic-link email itself failing to arrive; this only
/// needs to keep the button disabled for obviously-incomplete input.
/// Mirrors `lib/features/settings/category_edit_validation.dart`'s
/// "pure, localization-free unit" shape.
library;

/// Whether [email] looks like a plausible email address: a non-empty local
/// part, an `@`, and a domain containing an internal `.`.
bool isPlausibleEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0 || at == email.length - 1) {
    return false;
  }
  final domain = email.substring(at + 1);
  final dot = domain.indexOf('.');
  return dot > 0 && dot < domain.length - 1;
}
