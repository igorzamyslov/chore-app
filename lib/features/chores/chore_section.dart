/// Pure due-date bucketing for the chores list's section headers.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/l10n/app_localizations.dart';

/// A section of the chores list, in display order.
enum ChoreSection {
  /// Due strictly before [today].
  overdue,

  /// Due on [today].
  today,

  /// Due on `today + 1 day`.
  tomorrow,

  /// Due after tomorrow, up to and including the coming Sunday.
  thisWeek,

  /// Due after the coming Sunday, but still within [today]'s calendar
  /// month.
  thisMonth,

  /// Due after the coming Sunday, in a later calendar month.
  later,
}

/// This section's localized header, as shown in the chores list.
extension ChoreSectionLabel on ChoreSection {
  /// The header text shown above this section's tiles.
  String label(AppLocalizations l10n) {
    switch (this) {
      case ChoreSection.overdue:
        return l10n.choresSectionOverdue;
      case ChoreSection.today:
        return l10n.choresSectionToday;
      case ChoreSection.tomorrow:
        return l10n.choresSectionTomorrow;
      case ChoreSection.thisWeek:
        return l10n.choresSectionThisWeek;
      case ChoreSection.thisMonth:
        return l10n.choresSectionThisMonth;
      case ChoreSection.later:
        return l10n.choresSectionLater;
    }
  }
}

/// Which [ChoreSection] a [dueDate] falls into, relative to [today].
///
/// "This week" ends on the coming Sunday (inclusive); on a Sunday, that
/// range is empty (there's no "coming Sunday" left this week), so the very
/// next day (Monday) is evaluated against [ChoreSection.thisMonth] instead
/// (and falls into [ChoreSection.later] unless it happens to still be
/// [today]'s calendar month).
///
/// "This month" is due after the coming Sunday but still in [today]'s
/// calendar year/month. When the coming Sunday already falls in the next
/// calendar month (i.e. near month end), every date through that Sunday is
/// still caught by [ChoreSection.thisWeek], so [ChoreSection.thisMonth]
/// naturally ends up empty that week — there's no date left in [today]'s
/// month after the Sunday for it to hold.
ChoreSection sectionFor({
  required PlainDate today,
  required PlainDate dueDate,
}) {
  if (dueDate.isBefore(today)) {
    return ChoreSection.overdue;
  }
  if (dueDate == today) {
    return ChoreSection.today;
  }
  final tomorrow = today.addDays(1);
  if (dueDate == tomorrow) {
    return ChoreSection.tomorrow;
  }
  final sunday = today.addDays(7 - today.weekday);
  if (dueDate.isAfter(tomorrow) && dueDate.isOnOrBefore(sunday)) {
    return ChoreSection.thisWeek;
  }
  if (dueDate.year == today.year && dueDate.month == today.month) {
    return ChoreSection.thisMonth;
  }
  return ChoreSection.later;
}
