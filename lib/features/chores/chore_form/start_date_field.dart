/// The chore form's start-date picker field.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A tappable field showing [value], opening a date picker on tap.
///
/// Styled as a labelled card matching `LabelledFieldCard`'s family (spec
/// `docs/specs/theme-v2.md` §4.4 item 1) -- an uppercase micro-label above
/// the value -- but plain (`outlineVariant` border always, since it never
/// takes keyboard focus) and with a trailing calendar glyph instead of an
/// editable [TextField].
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

  /// Today, per `todayProvider` — the reference point for the picker's
  /// selectable range. Derived from `clockProvider` and refreshed at local
  /// midnight, so a form left open overnight gets an honest range.
  final PlainDate today;

  /// Called with the newly-picked date.
  final ValueChanged<PlainDate> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final dateTime = DateTime.utc(value.year, value.month, value.day);

    return semantic(
      'chore_form.start_date',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pick(context),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: l10n.choreFormStartDateLabel,
                        child: ExcludeSemantics(
                          child: Text(
                            l10n.choreFormStartDateLabel.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        DateFormat.yMMMd(localeName).format(dateTime),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.calendar_today_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
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
