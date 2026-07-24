/// The chore form's title and notes text fields.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:flutter/material.dart';

/// The required chore title field, with an inline validation error.
class TitleField extends StatelessWidget {
  /// Creates the title field.
  const TitleField({required this.controller, this.errorText, super.key});

  /// Backs the raw title text the user typed.
  final TextEditingController controller;

  /// Inline validation error, or `null` if valid (or not yet submitted).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return semantic(
      'chore_form.title',
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: 'Title', errorText: errorText),
      ),
    );
  }
}

/// The optional, multiline notes field.
class NotesField extends StatelessWidget {
  /// Creates the notes field.
  const NotesField({required this.controller, super.key});

  /// Backs the raw notes text the user typed.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return semantic(
      'chore_form.notes',
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Notes'),
        maxLines: 3,
        minLines: 3,
      ),
    );
  }
}
