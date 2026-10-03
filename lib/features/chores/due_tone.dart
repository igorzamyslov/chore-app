/// The status tone a pending occurrence is drawn in, by how its due date
/// relates to today (spec `docs/specs/theme-v2.md` §4.1 item 4).
library;

import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:flutter/material.dart';

/// How many days overdue an occurrence must be before it is drawn in the
/// error tone rather than the warning tone.
const int overdueErrorThresholdDays = 7;

/// A pending occurrence's status tone.
enum DueTone {
  /// Due in the future: the default surface, no accent.
  neutral,

  /// Due today.
  success,

  /// Overdue by fewer than [overdueErrorThresholdDays] days.
  warning,

  /// Overdue by [overdueErrorThresholdDays] days or more.
  error,
}

/// The [DueTone] for an occurrence due on [dueDate], relative to [today].
DueTone dueTone({required PlainDate today, required PlainDate dueDate}) {
  final daysOverdue = dueDate.daysUntil(today);
  if (daysOverdue >= overdueErrorThresholdDays) {
    return DueTone.error;
  }
  if (daysOverdue > 0) {
    return DueTone.warning;
  }
  if (daysOverdue == 0) {
    return DueTone.success;
  }
  return DueTone.neutral;
}

/// The colors one non-neutral [DueTone] resolves to in the current theme.
typedef DueToneColors = ({
  Color accent,
  Color container,
  Color outline,
  Color chip,
});

/// The theme colors for [tone], or `null` for [DueTone.neutral] (which
/// keeps every widget's default colors).
DueToneColors? dueToneColors(BuildContext context, DueTone tone) {
  final scheme = Theme.of(context).colorScheme;
  final famdo = famdoColors(context);
  return switch (tone) {
    DueTone.neutral => null,
    DueTone.success => (
      accent: famdo.success,
      container: famdo.successContainer,
      outline: famdo.successOutline,
      chip: famdo.successChip,
    ),
    DueTone.warning => (
      accent: famdo.warning,
      container: famdo.warningContainer,
      outline: famdo.warningOutline,
      chip: famdo.warningChip,
    ),
    DueTone.error => (
      accent: scheme.error,
      container: scheme.errorContainer,
      outline: famdo.errorOutline,
      chip: famdo.errorChip,
    ),
  };
}
