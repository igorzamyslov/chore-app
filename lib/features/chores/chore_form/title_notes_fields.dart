/// The chore form's title and notes text fields.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/chores/chore_form/labelled_field_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
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
      child: LabelledFieldCard(
        label: AppLocalizations.of(context).choreFormTitleLabel,
        controller: controller,
        errorText: errorText,
        // C7 (conventions audit) asked for title -> notes keyboard chaining
        // here. DELIBERATELY NOT DONE, after measuring it on a device:
        //
        // `TextInputAction.next` makes Enter jump into `notes`, an OPTIONAL
        // 3-line field, and leaves the keyboard up. The Save action lives in
        // the Scaffold's bottomNavigationBar, and with the keyboard open it
        // is not in the accessibility tree at all (verified 2026-08-06 by
        // dumping the live hierarchy: keyboard occupies y1517-2274, form
        // content ends at y1480, no `chore_form.save` node). So chaining
        // strands the user mid-form with no visible way to save.
        //
        // The default for this single-line field is `done`, which dismisses
        // the keyboard and reveals Save -- the right behavior for a form
        // whose common path is "type a title, save". Chaining is the correct
        // convention for forms of sequential REQUIRED fields; this isn't one.
        //
        // The underlying flaw (Save unreachable while the keyboard is up) is
        // logged as C15 in docs/feedback/2026-08-06-conventions-audit.md.
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
      child: LabelledFieldCard(
        label: AppLocalizations.of(context).choreFormNotesLabel,
        controller: controller,
        maxLines: 3,
        minLines: 3,
      ),
    );
  }
}
