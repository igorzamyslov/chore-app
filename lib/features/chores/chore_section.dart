/// Pure due-date bucketing for the chores list's section headers.
library;

import 'package:chore_app/domain/recurrence/plain_date.dart';

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

  /// Due after the coming Sunday.
  later,
}

/// This section's plain-text header, as shown in the chores list.
extension ChoreSectionLabel on ChoreSection {
  /// The header text shown above this section's tiles.
  String get label {
    switch (this) {
      case ChoreSection.overdue:
        return 'Overdue';
      case ChoreSection.today:
        return 'Today';
      case ChoreSection.tomorrow:
        return 'Tomorrow';
      case ChoreSection.thisWeek:
        return 'This week';
      case ChoreSection.later:
        return 'Later';
    }
  }
}

/// Which [ChoreSection] a [dueDate] falls into, relative to [today].
///
/// "This week" ends on the coming Sunday (inclusive); on a Sunday, that
/// range is empty (there's no "coming Sunday" left this week), so the very
/// next day (Monday) already falls into [ChoreSection.later].
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
  return ChoreSection.later;
}
