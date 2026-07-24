/// The chore form's start-date picker field.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A tappable field showing [value], opening a date picker on tap.
///
/// The picker's minimum selectable date is one year before [today]; there's
/// no maximum beyond a generous ten-year ceiling (a picker needs *some*
/// upper bound).
class StartDateField extends StatelessWidget {
  /// Creates the start date field.
  const StartDateField({
    required this.value,
    required this.today,
    required this.onChanged,
    super.key,
  });

  /// The currently-selected start date.
  final PlainDate value;

  /// Today, per `clockProvider` — the reference point for the picker's
  /// selectable range.
  final PlainDate today;

  /// Called with the newly-picked date.
  final ValueChanged<PlainDate> onChanged;

  @override
  Widget build(BuildContext context) {
    final localeName = Localizations.localeOf(context).toString();
    final dateTime = DateTime.utc(value.year, value.month, value.day);
    return semantic(
      'chore_form.start_date',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(AppLocalizations.of(context).choreFormStartDateLabel),
        subtitle: Text(DateFormat.yMMMd(localeName).format(dateTime)),
        trailing: const Icon(Icons.calendar_today_outlined),
        onTap: () => _pick(context),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final firstDate = today.addDays(-365);
    final lastDate = today.addDays(3650);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(value.year, value.month, value.day),
      firstDate: DateTime(firstDate.year, firstDate.month, firstDate.day),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
    );
    if (picked != null) {
      onChanged(PlainDate.fromDateTime(picked));
    }
  }
}
