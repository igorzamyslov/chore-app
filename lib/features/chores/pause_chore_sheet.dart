/// The "Pause" choice sheet: until resumed by hand, or until a date
/// (persona review 2026-10-06 C2, plan W3 "Pause until").
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// What the user chose in [showPauseChoreSheet]: pause with no resume day
/// ([until] `null`), or until [until].
class PauseChoice {
  /// Creates a choice; [until] `null` means "until I resume it".
  const PauseChoice({this.until});

  /// The local day the chore resumes on by itself, or `null`.
  final PlainDate? until;
}

enum _PauseOption { indefinite, untilDate }

/// Asks how long to pause for, and resolves to the [PauseChoice] (or `null`
/// if the sheet or the date picker was dismissed — nothing is paused then).
///
/// "Until a date…" opens a date picker whose earliest day is tomorrow
/// relative to [today]: pausing until today would resume on the spot.
/// Riverpod-free, like the other chore sheets; the caller passes [today].
Future<PauseChoice?> showPauseChoreSheet(
  BuildContext context, {
  required PlainDate today,
}) async {
  final option = await showModalBottomSheet<_PauseOption>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return semantic(
        'chores.pause.sheet',
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l10n.choresPauseSheetTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              semantic(
                'chores.pause.indefinite',
                child: ListTile(
                  leading: const Icon(Icons.pause_circle_outlined, size: 22),
                  title: Text(l10n.choresPauseUntilResumed),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PauseOption.indefinite),
                ),
              ),
              semantic(
                'chores.pause.untilDate',
                child: ListTile(
                  leading: const Icon(Icons.event_outlined, size: 22),
                  title: Text(l10n.choresPauseUntilDate),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PauseOption.untilDate),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  switch (option) {
    case null:
      return null;
    case _PauseOption.indefinite:
      return const PauseChoice();
    case _PauseOption.untilDate:
      if (!context.mounted) {
        return null;
      }
      final tomorrow = today.addDays(1);
      final last = today.addDays(365);
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
        firstDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
        lastDate: DateTime(last.year, last.month, last.day),
      );
      if (picked == null) {
        return null;
      }
      return PauseChoice(until: PlainDate.fromDateTime(picked));
  }
}
