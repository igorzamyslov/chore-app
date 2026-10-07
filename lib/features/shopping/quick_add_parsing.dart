/// Pure parsing of what is typed into the shopping quick-add field.
library;

/// Splits quick-add [input] into one name per item: on commas and on
/// newlines (a pasted "oat milk, sourdough" message, persona finding F7),
/// each part trimmed, empty parts dropped.
List<String> splitQuickAddInput(String input) {
  return [
    for (final part in input.split(RegExp(r'[,\r\n]+')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

final _leadingCount = RegExp(r'^(\d+)\s*[x×]?\s+(.+)$', caseSensitive: false);
final _trailingCount = RegExp(r'^(.+?)\s+[x×]\s*(\d+)$', caseSensitive: false);

/// A quick-add entry split into its item name and an optional quantity
/// note.
typedef ParsedQuickAdd = ({String name, String? quantityNote});

/// Recognises a count typed with the name (persona finding F6) so
/// "2x Milch" is stored as "Milch" with the note "2" instead of becoming a
/// separate staple that never matches "Milch" for duplicates or
/// suggestions.
///
/// - leading: `2 Milch`, `2x Milch`, `2 × Milch`  → name "Milch", note "2"
/// - trailing: `Milch x2`, `Milch × 2`            → name "Milch", note "2"
///
/// Anything else is returned unchanged (trimmed) with no note. Used by the
/// quick-add field only; the edit sheet takes whatever the person types.
ParsedQuickAdd parseQuantity(String raw) {
  final text = raw.trim();
  final leading = _leadingCount.firstMatch(text);
  if (leading != null) {
    return (name: leading.group(2)!.trim(), quantityNote: leading.group(1));
  }
  final trailing = _trailingCount.firstMatch(text);
  if (trailing != null) {
    return (name: trailing.group(1)!.trim(), quantityNote: trailing.group(2));
  }
  return (name: text, quantityNote: null);
}
