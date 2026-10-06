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
