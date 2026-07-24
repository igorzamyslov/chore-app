// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Chores';

  @override
  String appBootstrapError(Object error) {
    return 'Something went wrong starting up: $error';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get choresTabLabel => 'Chores';

  @override
  String get shoppingTabLabel => 'Shopping';

  @override
  String get settingsTabLabel => 'Settings';

  @override
  String settingsComingSoon(String title) {
    return '$title — coming soon';
  }

  @override
  String get categoryPickerNone => 'None';

  @override
  String get choresMenuSkip => 'Skip';

  @override
  String get choresMenuEdit => 'Edit';

  @override
  String get choresMenuPause => 'Pause';

  @override
  String get choresDeleteDialogTitle => 'Delete chore?';

  @override
  String choresDeleteDialogBody(String choreTitle) {
    return 'This deletes \'$choreTitle\'. Its history is kept, but its pending occurrence is removed.';
  }

  @override
  String get choresOccurrenceCompleteTooltip => 'Complete';

  @override
  String get choresOccurrenceMoreActionsTooltip => 'More actions';

  @override
  String get choresDueToday => 'Today';

  @override
  String get choresDueTomorrow => 'Tomorrow';

  @override
  String choresDueInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count days',
      one: 'In 1 day',
    );
    return '$_temp0';
  }

  @override
  String choresDueOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Overdue · $count days',
      one: 'Overdue · 1 day',
    );
    return '$_temp0';
  }

  @override
  String get choresSectionOverdue => 'Overdue';

  @override
  String get choresSectionToday => 'Today';

  @override
  String get choresSectionTomorrow => 'Tomorrow';

  @override
  String get choresSectionThisWeek => 'This week';

  @override
  String get choresSectionThisMonth => 'This month';

  @override
  String get choresSectionLater => 'Later';

  @override
  String get choresFilterMemberTooltip => 'Filter by member';

  @override
  String get choresFilterMemberAll => 'All members';

  @override
  String get choresFilterCategoryTooltip => 'Filter by category';

  @override
  String get choresFilterCategoryAll => 'All categories';

  @override
  String get choresEmptyState => 'No chores pending — nice work!';

  @override
  String get choresErrorMessage => 'Could not load your chores.';

  @override
  String get choresSnackbarDone => 'Done';

  @override
  String choresSnackbarDoneNextDue(String dueText) {
    return 'Done — next due $dueText';
  }

  @override
  String get choresSnackbarSkipped => 'Skipped';

  @override
  String choresSnackbarSkippedNextDue(String dueText) {
    return 'Skipped — next due $dueText';
  }

  @override
  String get choresSnackbarUndo => 'Undo';

  @override
  String choresDoneHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Done today ($count)',
      one: 'Done today (1)',
    );
    return '$_temp0';
  }

  @override
  String get choresDoneStatusDone => 'Done';

  @override
  String get choresDoneStatusSkipped => 'Skipped';

  @override
  String choresDoneClosedByLabel(String name) {
    return 'by $name';
  }

  @override
  String get choresDoneReopen => 'Reopen';

  @override
  String choresPausedHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Paused ($count)',
      one: 'Paused (1)',
    );
    return '$_temp0';
  }

  @override
  String get choresPausedBadge => 'Paused';

  @override
  String get choresPausedResume => 'Resume';

  @override
  String get choreFormEditTitle => 'Edit chore';

  @override
  String get choreFormNewTitle => 'New chore';

  @override
  String get choreFormTitleLabel => 'Title';

  @override
  String get choreFormNotesLabel => 'Notes';

  @override
  String get choreFormTitleRequiredError => 'Title is required';

  @override
  String get choreFormRepeatToggleLabel => 'Repeat';

  @override
  String get choreFormRepeatEveryLabel => 'Repeat every';

  @override
  String get choreFormIntervalTooSmallError => 'Must be at least 1';

  @override
  String get choreFormUnitDay => 'Day';

  @override
  String get choreFormUnitWeek => 'Week';

  @override
  String get choreFormUnitMonth => 'Month';

  @override
  String get choreFormAnchorScheduleTitle => 'On a fixed schedule';

  @override
  String get choreFormAnchorCompletionTitle => 'After last completion';

  @override
  String get choreFormAnchorScheduleSubtitle => 'e.g. every Tuesday';

  @override
  String get choreFormAnchorCompletionSubtitle => 'e.g. 4 days after last done';

  @override
  String monthlyDayOfMonthLabel(String ordinalDay) {
    return 'On the $ordinalDay';
  }

  @override
  String monthlyNthWeekdayLabel(String ordinal, String weekday) {
    return 'On the $ordinal $weekday';
  }

  @override
  String monthlyLastWeekdayLabel(String weekday) {
    return 'On the last $weekday';
  }

  @override
  String get choreFormAssignmentFixed => 'Fixed';

  @override
  String get choreFormAssignmentRotation => 'Rotation';

  @override
  String get choreFormAssignmentAnyone => 'Anyone';

  @override
  String choreFormAssigneeOrderLabel(int order, String name) {
    return '$order. $name';
  }

  @override
  String get choreFormAssignmentNeedsOneError => 'Pick one member';

  @override
  String get choreFormAssignmentNeedsTwoError => 'Pick at least two';

  @override
  String get choreFormStartDateLabel => 'Start date';

  @override
  String get shoppingEmptyState => 'Shopping list is empty';

  @override
  String get shoppingErrorMessage => 'Could not load your shopping list.';

  @override
  String get shoppingEditNameLabel => 'Name';

  @override
  String get shoppingEditQuantityLabel => 'Quantity / note';

  @override
  String get shoppingEditNameRequiredError => 'Name is required';

  @override
  String get shoppingUncategorized => 'Uncategorized';

  @override
  String shoppingCartHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In the cart ($count)',
      one: 'In the cart (1)',
    );
    return '$_temp0';
  }

  @override
  String get shoppingClearButton => 'Clear checked';

  @override
  String get shoppingClearDialogTitle => 'Clear checked items?';

  @override
  String shoppingClearDialogBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This removes $count checked items from the list.',
      one: 'This removes 1 checked item from the list.',
    );
    return '$_temp0';
  }

  @override
  String get shoppingClearConfirm => 'Clear';

  @override
  String get shoppingAddHint => 'Add item…';

  @override
  String get shoppingAddTooltip => 'Add item';
}
