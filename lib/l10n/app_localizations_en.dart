// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Famdo';

  @override
  String appBootstrapError(Object error) {
    return 'Something went wrong starting up: $error';
  }

  @override
  String get appBootstrapErrorTitle => 'We couldn\'t open your data';

  @override
  String get notificationChannelDigestName => 'Daily summary';

  @override
  String get notificationChannelDigestDescription =>
      'The once-a-day chores digest notification.';

  @override
  String get notificationChannelRemindersName => 'Chore reminders';

  @override
  String get notificationChannelRemindersDescription =>
      'Reminders for individual chores at the time you chose.';

  @override
  String get notificationChannelEveningName => 'Evening reminder';

  @override
  String get notificationChannelEveningDescription =>
      'An evening nudge when chores are still open today.';

  @override
  String get reminderBodyDueToday => 'Due today';

  @override
  String get reminderBodyStillOpen => 'Still open';

  @override
  String eveningReminderBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chores still open today',
      one: '1 chore still open today',
    );
    return '$_temp0';
  }

  @override
  String notificationDigestDueOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chores today',
      one: '1 chore today',
    );
    return '$_temp0';
  }

  @override
  String notificationDigestOverdueOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overdue chores',
      one: '1 overdue chore',
    );
    return '$_temp0';
  }

  @override
  String notificationDigestBoth(int dueCount, int overdueCount) {
    String _temp0 = intl.Intl.pluralLogic(
      dueCount,
      locale: localeName,
      other: '$dueCount chores today',
      one: '1 chore today',
    );
    String _temp1 = intl.Intl.pluralLogic(
      overdueCount,
      locale: localeName,
      other: '$overdueCount overdue',
      one: '1 overdue',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get notificationActionDone => 'Done';

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
  String get categoryPickerNone => 'None';

  @override
  String get categoryPickerManageTooltip => 'Edit categories';

  @override
  String get choresMenuMarkDoneFor => 'Mark done for…';

  @override
  String get choresMenuReassign => 'Reassign this turn…';

  @override
  String get choresReassignTitle => 'Who takes this turn?';

  @override
  String choresReassignedSnackbar(String name) {
    return 'Reassigned to $name';
  }

  @override
  String get choresMarkDoneForTitle => 'Who did this one?';

  @override
  String get choresMenuSkip => 'Skip';

  @override
  String get choresMenuEdit => 'Edit';

  @override
  String get choresMenuDuplicate => 'Duplicate';

  @override
  String get choresMenuPause => 'Pause';

  @override
  String get choresDeleteDialogShared =>
      'Everyone in the household will see this.';

  @override
  String get choresDeleteDialogTitle => 'Delete chore?';

  @override
  String choresDeleteDialogBody(String choreTitle) {
    return 'This removes \'$choreTitle\' from your lists. Its history is kept — you\'ll find it under Settings › Chore history.';
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
  String choresFilterYou(String name) {
    return '$name (you)';
  }

  @override
  String get choresAssigneeAnyone => 'Anyone';

  @override
  String get choresFilterCategoryTooltip => 'Filter by category';

  @override
  String get choresFilterCategoryAll => 'All categories';

  @override
  String get choresFilterClear => 'Show everything';

  @override
  String get actingMemberButtonTooltip => 'Switch who\'s acting';

  @override
  String get actingMemberSheetTitle => 'Who\'s doing chores right now?';

  @override
  String get choresActingMemberHint =>
      'Credit and your daily summary follow this person.';

  @override
  String actingMemberSignedInAs(String name) {
    return 'You\'re signed in as $name';
  }

  @override
  String get actingManageMembers => 'Manage members';

  @override
  String get choresEmptyState => 'Nothing left for today.';

  @override
  String get choresEmptyDoneHeadline => 'All done for today';

  @override
  String get choresEmptyFresh => 'Add your first chore with +';

  @override
  String get choresEmptyFreshHeadline => 'No chores yet';

  @override
  String get choresEmptyFiltered => 'Nothing here for this filter.';

  @override
  String get choresEmptyFilteredHeadline => 'No matches';

  @override
  String get choresErrorMessage => 'Could not load your chores.';

  @override
  String choresProgressTitle(int n, int m) {
    return '$n of $m done today';
  }

  @override
  String choresProgressRemainingToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count still to go',
      one: '1 still to go',
    );
    return '$_temp0';
  }

  @override
  String get choresProgressAllDoneToday => 'That\'s everything for today.';

  @override
  String choresProgressCatchUp(int count) {
    return '$count to catch up';
  }

  @override
  String get choresProgressFilterActive => 'Filtered — not the whole household';

  @override
  String get welcomeTagline =>
      'Share chores and a shopping list with your household.';

  @override
  String get welcomeCreateTitle => 'Set up a new household';

  @override
  String get welcomeCreateSubtitle =>
      'Keep it on this device — you can sync later.';

  @override
  String get welcomeCreateNameLabel => 'Your name';

  @override
  String get welcomeCreateConfirm => 'Get started';

  @override
  String get welcomeCreateError =>
      'Something went wrong setting up your household. Please try again.';

  @override
  String get householdDefaultName => 'My household';

  @override
  String get welcomeJoinTitle => 'Join my family\'s household';

  @override
  String get welcomeJoinSubtitle =>
      'Got an invite code? Sign in and enter it here.';

  @override
  String get welcomeJoinReconnectSubtitle =>
      'This device isn\'t connected to it yet.';

  @override
  String get welcomeOffline =>
      'No account needed — everything stays on your device unless you sign in.';

  @override
  String get onboardingNameBannerMessage => 'Who\'s doing the chores here?';

  @override
  String get onboardingNameBannerSetAction => 'Set my name';

  @override
  String get onboardingNameBannerDismissTooltip => 'Dismiss';

  @override
  String get digestPrepromptMessage => 'Want a daily summary of what\'s due?';

  @override
  String get digestPrepromptEnableAction => 'Turn on';

  @override
  String get digestPrepromptDismissAction => 'Not now';

  @override
  String get catchUpBannerMessage =>
      'Your repeating chores jumped ahead to their latest due date — you didn\'t miss anything extra.';

  @override
  String get catchUpBannerDismissTooltip => 'Dismiss';

  @override
  String get choresSnackbarDone => 'Done';

  @override
  String choresSnackbarDoneNextDue(String dueText) {
    return 'Done — next due $dueText';
  }

  @override
  String choresDoneCredited(String name) {
    return 'Done — credited to $name';
  }

  @override
  String choresDoneCreditedNextDue(String name, String date) {
    return 'Done — credited to $name, next due $date';
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
  String get choresSnackbarPaused => 'Paused';

  @override
  String get choresSnackbarNoActingMember =>
      'This device doesn\'t know who you are yet. Sign in again or reopen the app.';

  @override
  String choresDoneRecently(int count) {
    return 'Done recently ($count)';
  }

  @override
  String get choresDoneDayToday => 'Today';

  @override
  String get choresDoneDayYesterday => 'Yesterday';

  @override
  String get choresDoneStatusDone => 'Done';

  @override
  String get choresDoneStatusSkipped => 'Skipped';

  @override
  String get choresDoneEarly => 'Done early';

  @override
  String choresDoneClosedByLabel(String name) {
    return 'by $name';
  }

  @override
  String get choresDoneReopen => 'Reopen';

  @override
  String get choresReopenedSnackbar => 'Reopened';

  @override
  String choresReopenOthersTitle(String name) {
    return 'Reopen $name\'s completion?';
  }

  @override
  String get choresReopenOthersBody => 'This removes it from their history.';

  @override
  String get choresReopenOthersConfirm => 'Reopen';

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
  String choresPausedUntil(String date) {
    return 'Paused until $date';
  }

  @override
  String get choresPauseSheetTitle => 'Pause this chore';

  @override
  String get choresPauseUntilResumed => 'Until I resume it';

  @override
  String get choresPauseUntilDate => 'Until a date…';

  @override
  String get choresPausedResume => 'Resume';

  @override
  String get choreFormEditTitle => 'Edit chore';

  @override
  String get choreSavedSnackbar => 'Saved';

  @override
  String choreSavedNextDue(String date) {
    return 'Saved — next due $date';
  }

  @override
  String choreSavedReassigned(String name) {
    return 'Saved — today\'s turn is now $name\'s';
  }

  @override
  String get choreFormNewTitle => 'New chore';

  @override
  String get choreFormTitleLabel => 'Title';

  @override
  String get choreFormNotesLabel => 'Notes';

  @override
  String get choreFormTitleRequiredError => 'Title is required';

  @override
  String get choreFormDiscardDialogTitle => 'Discard changes?';

  @override
  String get choreFormDiscardDialogBody =>
      'Your edits to this chore won\'t be saved.';

  @override
  String get choreFormDiscardKeepEditing => 'Keep editing';

  @override
  String get choreFormDiscardConfirm => 'Discard';

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
  String choreFormUnitDayPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Days',
      one: 'Day',
    );
    return '$_temp0';
  }

  @override
  String choreFormUnitWeekPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Weeks',
      one: 'Week',
    );
    return '$_temp0';
  }

  @override
  String choreFormUnitMonthPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Months',
      one: 'Month',
    );
    return '$_temp0';
  }

  @override
  String get choreFormAnchorScheduleTitle => 'On fixed days';

  @override
  String get choreFormAnchorCompletionTitle => 'After last completion';

  @override
  String get choreFormAnchorScheduleSubtitle => 'e.g. every Tuesday';

  @override
  String choreFormAnchorScheduleSubtitleDay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count days',
      one: 'Every day',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorScheduleSubtitleWeek(int count, String weekdays) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count weeks on $weekdays',
      one: 'Every week on $weekdays',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorScheduleSubtitleMonthDayOfMonth(
    int count,
    String ordinalDay,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count months on the $ordinalDay',
      one: 'Every month on the $ordinalDay',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorScheduleSubtitleMonthNthWeekday(
    int count,
    String ordinal,
    String weekday,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count months on the $ordinal $weekday',
      one: 'Every month on the $ordinal $weekday',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorScheduleSubtitleMonthLastWeekday(
    int count,
    String weekday,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count months on the last $weekday',
      one: 'Every month on the last $weekday',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorCompletionSubtitleDay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days after last done',
      one: '1 day after last done',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorCompletionSubtitleWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks after last done',
      one: '1 week after last done',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorCompletionSubtitleMonth(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months after last done',
      one: '1 month after last done',
    );
    return '$_temp0';
  }

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
  String get choreFormPatternFollowsStartDate =>
      'Follows the start date — change the start date to change the day.';

  @override
  String choreFormSentenceDay(String interval, String unit) {
    return 'Repeat every $interval $unit';
  }

  @override
  String choreFormSentenceWeek(String interval, String unit) {
    return 'Repeat every $interval $unit on';
  }

  @override
  String choreFormSentenceMonthDayOfMonth(
    String interval,
    String unit,
    String day,
  ) {
    return 'Repeat every $interval $unit on the $day';
  }

  @override
  String choreFormSentenceMonthWeekday(
    String interval,
    String unit,
    String ordinal,
    String weekday,
  ) {
    return 'Repeat every $interval $unit on the $ordinal $weekday';
  }

  @override
  String get choreFormDayOfMonthLast => 'last day';

  @override
  String get choreFormOrdinalLast => 'last';

  @override
  String get choreFormMonthlyModeDayOfMonth => 'A day of the month';

  @override
  String get choreFormMonthlyModeWeekday => 'A weekday';

  @override
  String get choreFormCountingFromLabel => 'Counting from';

  @override
  String get choreFormCountingFromWeekdayOnly =>
      'A weekday pattern is a position in the calendar, so there is nothing for a completion date to count from.';

  @override
  String choreFormPreviewNextThree(
    String pattern,
    String first,
    String second,
    String third,
  ) {
    return '$pattern. Next $first, then $second and $third.';
  }

  @override
  String choreFormPreviewCompletionRolledForward(String base, String weekdays) {
    return '$base, rolled forward to the next $weekdays.';
  }

  @override
  String choreFormPreviewCompletionDependsOnDay(String base) {
    return '$base — the next due date depends on the day you do it.';
  }

  @override
  String get choreFormSentenceIntervalA11y => 'Repeat interval';

  @override
  String get choreFormSentenceUnitA11y => 'Repeat unit';

  @override
  String get choreFormSentenceMonthlyDayA11y => 'Day of the month';

  @override
  String get choreFormSentenceMonthlyOrdinalA11y => 'Which one in the month';

  @override
  String get choreFormSentenceMonthlyWeekdayA11y => 'Weekday';

  @override
  String get choreFormAssignmentFixed => 'Fixed';

  @override
  String get choreFormAssignmentRotation => 'Rotation';

  @override
  String get choreFormAssignmentAnyone => 'Anyone';

  @override
  String get choreFormAssignmentHelpFixed => 'Always the same person.';

  @override
  String get choreFormAssignmentHelpRotation =>
      'Takes turns in this order, starting at 1.';

  @override
  String get choreFormAssignmentHelpAnyone => 'Whoever gets to it.';

  @override
  String choreFormAssigneeOrderLabel(int order, String name) {
    return '$order. $name';
  }

  @override
  String get choreFormAssignmentNeedsOneError => 'Pick one member';

  @override
  String get choreFormAssignmentNeedsTwoError => 'Pick at least two';

  @override
  String get choreFormAddMember => 'Add member…';

  @override
  String choreFormAssigneeRemoveTooltip(String name) {
    return 'Remove $name from the rotation';
  }

  @override
  String get choreFormStartDateLabel => 'Start date';

  @override
  String get choreFormReminderToggle => 'Remind me about this chore';

  @override
  String get choreFormReminderTime => 'Reminder time';

  @override
  String get choreFormReminderHint =>
      'This chore won\'t be counted in the daily summary';

  @override
  String get shoppingEmptyState => 'Shopping list is empty';

  @override
  String get shoppingErrorMessage => 'Could not load your shopping list.';

  @override
  String get shoppingDeletedSnackbar => 'Removed';

  @override
  String get shoppingDeletedUndo => 'Undo';

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
  String get shoppingUncheckAll => 'Put all back';

  @override
  String shoppingClearedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cleared $count items',
      one: 'Cleared 1 item',
    );
    return '$_temp0';
  }

  @override
  String get shoppingClearedUndo => 'Undo';

  @override
  String shoppingPutBackSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Put $count items back',
      one: 'Put 1 item back',
    );
    return '$_temp0';
  }

  @override
  String get shoppingCheckedSnackbar => 'In the cart';

  @override
  String get shoppingAddHint => 'Add item…';

  @override
  String get shoppingAddTooltip => 'Add item';

  @override
  String get shoppingAddAlreadyOnList => 'Already on the list';

  @override
  String shoppingRemainingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count left',
      zero: 'Nothing left',
    );
    return '$_temp0';
  }

  @override
  String shoppingSyncedAgo(String relative) {
    return 'synced $relative';
  }

  @override
  String get relativeTimeJustNow => 'just now';

  @override
  String relativeTimeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String relativeTimeOn(String date) {
    return 'on $date';
  }

  @override
  String get syncPendingItemTooltip => 'Waiting to send';

  @override
  String get shoppingSuggestionForget => 'Forget this suggestion';

  @override
  String shoppingAddedCount(int count) {
    return '$count items added';
  }

  @override
  String get shoppingAddMovedBack => 'Moved back to the list';

  @override
  String get settingsDigestSectionTitle => 'Daily summary';

  @override
  String get settingsDigestToggleTitle => 'Daily summary';

  @override
  String get settingsDigestToggleDeniedHint =>
      'Not delivering — notifications are off';

  @override
  String settingsRemindersCeilingHint(int count, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count chores stay in the daily summary — this device can hold $limit reminders at once.',
      one:
          '1 chore stays in the daily summary — this device can hold $limit reminders at once.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDigestTimeLabel => 'Notification time';

  @override
  String get settingsDigestPermissionHint =>
      'Notifications are turned off in system settings.';

  @override
  String get settingsDigestPermissionAction => 'Open settings';

  @override
  String get settingsEveningToggle => 'Remind me again in the evening';

  @override
  String get settingsEveningToggleSubtitle =>
      'Only if something is still open today';

  @override
  String get settingsEveningTime => 'Evening time';

  @override
  String get settingsEveningInQuietHoursHint =>
      'Inside your quiet hours — not delivering';

  @override
  String get settingsQuietHoursToggle => 'Quiet hours';

  @override
  String get settingsQuietHoursFrom => 'From';

  @override
  String get settingsQuietHoursTo => 'To';

  @override
  String get settingsQuietHoursEmptyWindowHint =>
      'Start and end are the same — no quiet time';

  @override
  String get settingsExportEntry => 'Export data';

  @override
  String get settingsExportSubtitle =>
      'JSON file with your members, chores, history and shopping list. The app can\'t import it yet.';

  @override
  String get settingsExportError =>
      'Couldn\'t export your data. Please try again.';

  @override
  String get settingsHouseholdSectionTitle => 'Household';

  @override
  String get settingsHouseholdNameRow => 'Household name';

  @override
  String get settingsMembersEntry => 'Members';

  @override
  String get settingsMembersInviteEntry => 'Invite';

  @override
  String get settingsMembersInviteLocalTitle => 'Invite';

  @override
  String get settingsMembersInviteLocalSubtitle =>
      'Sign in first to invite your family';

  @override
  String get settingsMembersInviteSheetTitle => 'Invite a household member';

  @override
  String get settingsMembersInviteSheetBody =>
      'Share this code — it replaces any earlier code and expires in 7 days.';

  @override
  String get settingsMembersInviteHint =>
      'Add everyone under Members first — they\'ll pick their own name when they join.';

  @override
  String settingsMembersInviteValidUntil(String date) {
    return 'Valid until $date';
  }

  @override
  String get settingsMembersInviteNewCode => 'New code';

  @override
  String get settingsMembersInviteReplaceTitle => 'Replace the shared code?';

  @override
  String get settingsMembersInviteReplaceBody =>
      'Anyone still joining with the old code will need this new one.';

  @override
  String get settingsMembersInviteReplaceConfirm => 'Replace';

  @override
  String get settingsMembersInviteShare => 'Share';

  @override
  String settingsMembersInviteShareText(String code) {
    return 'Join my household on Famdo — enter the code $code when you sign in. Get the app: https://github.com/igorzamyslov/chore-app/releases/latest';
  }

  @override
  String get settingsMembersInviteError =>
      'Couldn\'t create an invite. Please try again.';

  @override
  String get memberStatusYou => 'You';

  @override
  String get memberStatusLinked => 'Uses Famdo on their own phone';

  @override
  String get memberStatusUnclaimed =>
      'No phone yet — you can mark their chores';

  @override
  String get manageMembersTitle => 'Members';

  @override
  String get manageMembersErrorMessage => 'Could not load your members.';

  @override
  String get manageMembersHouseholdSubtitle => 'Household name';

  @override
  String get memberEditNewTitle => 'New member';

  @override
  String get memberEditEditTitle => 'Edit member';

  @override
  String get memberEditNameLabel => 'Name';

  @override
  String get memberEditColorLabel => 'Color';

  @override
  String get memberEditColorUniqueHint =>
      'Your color is how you show up on every chore, in the digest and in Chore history. Two people can\'t take the same one.';

  @override
  String memberEditColorTakenBy(String memberName) {
    return 'Taken by $memberName';
  }

  @override
  String get memberEditDeleteBlockedLastMember =>
      'A household needs at least one member, so this one can\'t be removed.';

  @override
  String get memberEditDeleteBlockedSelf =>
      'This is your own profile. To leave the household yourself, use “Leave the household” in Settings → Household.';

  @override
  String get memberEditDeleteBlockedOffline =>
      'This profile is used on someone else\'s phone. Sign in and connect to the online household to remove it.';

  @override
  String memberDeleteDialogTitle(String memberName) {
    return 'Delete $memberName?';
  }

  @override
  String memberDeleteDialogBody(String memberName) {
    return 'This removes $memberName from the household. Rotation chores drop them from the turn order — converting to a fixed assignee or \"anyone\" if too few people are left. Chores fixed to $memberName open up to anyone, and anything currently assigned to them becomes unassigned. Past history — who completed what — stays unchanged.';
  }

  @override
  String memberRemoveDialogBodyClaimed(String memberName) {
    return '$memberName uses this household on their own phone. Removing them stops that phone from syncing — it keeps everything it already has, as its own local copy. Their profile and history stay here with the household: rotation chores drop them from the turn order, chores fixed to them open up to anyone, and anything currently assigned to them becomes unassigned. Past history — who completed what — stays unchanged.';
  }

  @override
  String memberRemoveError(String memberName) {
    return 'Couldn\'t remove $memberName. This needs a connection to the online household — nothing was changed. Try again.';
  }

  @override
  String get householdRenameTitle => 'Rename household';

  @override
  String get householdRenameNameLabel => 'Name';

  @override
  String get settingsCategoriesEntry => 'Categories';

  @override
  String get manageCategoriesTitle => 'Manage categories';

  @override
  String get manageCategoriesKindChore => 'Chores';

  @override
  String get manageCategoriesKindShopping => 'Shopping';

  @override
  String get manageCategoriesEmptyState => 'No categories yet';

  @override
  String get manageCategoriesErrorMessage => 'Could not load your categories.';

  @override
  String get categoryEditNewTitle => 'New category';

  @override
  String get categoryEditEditTitle => 'Edit category';

  @override
  String get categoryEditNameLabel => 'Name';

  @override
  String get categoryEditNameRequiredError => 'Name is required';

  @override
  String get categoryEditIconLabel => 'Icon';

  @override
  String get categoryEditColorLabel => 'Color';

  @override
  String categoryUsageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Used by $count chores',
      one: 'Used by 1 chore',
      zero: 'Not used yet',
    );
    return '$_temp0';
  }

  @override
  String categoryUsageCountShopping(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Used by $count items',
      one: 'Used by 1 item',
      zero: 'Not used yet',
    );
    return '$_temp0';
  }

  @override
  String get categoryDeleteMoveTo => 'Move them to';

  @override
  String get categoryDeleteMoveToNone => 'Uncategorized';

  @override
  String get categoryDeleteDialogTitle => 'Delete category?';

  @override
  String categoryDeleteDialogBodyChoresZero(String categoryName) {
    return 'This deletes \'$categoryName\'. No chores use it right now.';
  }

  @override
  String categoryDeleteDialogBodyChoresCount(String categoryName, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This deletes \'$categoryName\'. $count chores use it.',
      one: 'This deletes \'$categoryName\'. 1 chore uses it.',
    );
    return '$_temp0';
  }

  @override
  String categoryDeleteDialogBodyShoppingZero(String categoryName) {
    return 'This deletes \'$categoryName\'. No shopping items use it right now.';
  }

  @override
  String categoryDeleteDialogBodyShoppingCount(String categoryName, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This deletes \'$categoryName\'. $count shopping items use it.',
      one: 'This deletes \'$categoryName\'. 1 shopping item uses it.',
    );
    return '$_temp0';
  }

  @override
  String get settingsPreferencesSectionTitle => 'Preferences';

  @override
  String get settingsLanguageEntry => 'Language';

  @override
  String get settingsLanguageSheetTitle => 'Choose language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageDeutsch => 'Deutsch';

  @override
  String get settingsAppearanceEntry => 'Appearance';

  @override
  String get settingsAppearanceSheetTitle => 'Appearance';

  @override
  String get settingsAppearanceSystem => 'System';

  @override
  String get settingsAppearanceLight => 'Light';

  @override
  String get settingsAppearanceDark => 'Dark';

  @override
  String get settingsAccountIntro =>
      'Signing in stores your email and your household\'s data — chores, shopping list, members — on the sync server, so your devices stay in step. Without an account, everything stays on this device. Technical error reports are sent too — you can switch them off under About.';

  @override
  String get settingsAccountHowItWorks => 'How accounts work';

  @override
  String get settingsAccountHowItWorksAccountTitle => 'Account';

  @override
  String get settingsAccountHowItWorksAccountBody =>
      'Your email login on the sync server. You only need one to share a household or keep several phones in step.';

  @override
  String get settingsAccountHowItWorksMemberTitle => 'Member';

  @override
  String get settingsAccountHowItWorksMemberBody =>
      'A person in the household. A member may have their own account and phone, or not — anyone can mark their chores.';

  @override
  String get settingsAccountHowItWorksHouseholdTitle => 'Household';

  @override
  String get settingsAccountHowItWorksHouseholdBody =>
      'The shared chores and shopping list. It lives on your phone, and on the sync server too once you put it online.';

  @override
  String get settingsAccountEmailLabel => 'Email address';

  @override
  String get settingsAccountSendLink => 'Send sign-in link';

  @override
  String get settingsAccountSendAgain => 'Send again';

  @override
  String settingsAccountCheckEmail(String email) {
    return 'Check your email at $email for your sign-in link.';
  }

  @override
  String settingsAccountSignedOutLinked(String householdName) {
    return 'This phone is linked to $householdName — sign in to keep syncing.';
  }

  @override
  String settingsAccountPausedNotice(String householdName) {
    return 'This phone is still connected to $householdName, but syncing is paused. Changes you make now will be sent once you sign in again. If someone else edits the same item meanwhile, your version replaces theirs when you sign back in.';
  }

  @override
  String get settingsAccountDisconnect =>
      'Disconnect from the online household';

  @override
  String get settingsAccountDisconnectSubtitle =>
      'Stops syncing on this phone only — the household stays online for everyone else.';

  @override
  String get settingsAccountDisconnectConfirmTitle =>
      'Disconnect from the online household?';

  @override
  String get settingsAccountDisconnectConfirmBody =>
      'The household stays on this device exactly as it is. Other members keep their household, and nothing is deleted anywhere.';

  @override
  String get settingsAccountDisconnectConfirmAction => 'Disconnect';

  @override
  String get settingsAccountLeave => 'Leave the household';

  @override
  String get settingsAccountLeaveSubtitle =>
      'Removes you from the household. Your chores and history stay with them.';

  @override
  String householdLeaveConfirmTitle(String householdName) {
    return 'Leave $householdName?';
  }

  @override
  String get householdLeaveConfirmBody =>
      'Your profile stays with the household, so the others keep seeing you and everything you\'ve done. This phone stops syncing. You can come back later with a new invite code.';

  @override
  String get householdLeaveConfirmBodyLastMember =>
      'You\'re the last person here with an account. Leaving takes the online household with you: the shared copy and its history are removed from the server and any invite codes stop working. Everything on this phone is unaffected unless you tick the box below.';

  @override
  String get householdLeaveConfirmAction => 'Leave';

  @override
  String get householdLeaveError =>
      'Couldn\'t leave the household. This needs a connection — nothing was changed. Try again.';

  @override
  String get settingsAccountDeleteAccount => 'Delete my account';

  @override
  String get accountDeleteConfirmTitle => 'Delete your account?';

  @override
  String get accountDeleteConfirmBody =>
      'Your account and your email address are deleted from the server. This can\'t be undone. Your profile stays with each household you\'re part of, so the others keep their history — you\'re just no longer linked to it.';

  @override
  String get accountDeleteConfirmBodyLastMember =>
      'Your account and your email address are deleted from the server. This can\'t be undone. You\'re the last person here with an account, so the online household goes with it: the shared copy and its history are removed from the server and any invite codes stop working. Everything on this phone is unaffected unless you tick the box below.';

  @override
  String get accountDeleteConfirmAction => 'Delete account';

  @override
  String get accountDeleteFinalTitle => 'Delete your account now?';

  @override
  String get accountDeleteFinalBodyKeepPhone =>
      'Your account and your email address are erased from the server. That can\'t be undone. This phone keeps everything it has, as its own local copy. To keep a copy of your data somewhere else first, use Export data under Settings → Data.';

  @override
  String get accountDeleteFinalBodyDeletePhone =>
      'Your account and your email address are erased from the server, and this phone\'s copy — members, chores and shopping list — is deleted too, so the app starts fresh. Neither can be undone. To keep a copy of your data first, use Export data under Settings → Data.';

  @override
  String get accountDeleteFinalAction => 'Delete account';

  @override
  String get accountDeleteError =>
      'Couldn\'t delete your account. This needs a connection — nothing was changed. Try again.';

  @override
  String get settingsAccountSendError =>
      'Couldn\'t send the sign-in link. Please try again.';

  @override
  String get settingsAccountSignOut => 'Sign out';

  @override
  String get settingsAccountSignOutConfirmTitle => 'Sign out?';

  @override
  String get settingsAccountSignOutConfirmBody =>
      'Syncing pauses until you sign in again. Your household stays on this device, and any changes you make while signed out are kept and sent once you sign in. If someone else edits the same item meanwhile, your version replaces theirs when you sign back in.';

  @override
  String get settingsAccountSignOutConfirmAction => 'Sign out';

  @override
  String get syncRefreshError =>
      'Couldn\'t reach the household. Your changes are saved here and will sync later.';

  @override
  String get syncRefreshErrorRevoked =>
      'This phone was removed from the household, so nothing will sync. Nothing is lost — see Settings → Household to reconnect.';

  @override
  String get syncRefreshErrorRejected =>
      'The household server rejected a change from this phone, so it hasn\'t gone through. Check for an app update; your other changes keep syncing.';

  @override
  String syncPendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to send',
      one: '1 change waiting to send',
    );
    return '$_temp0';
  }

  @override
  String get syncHealthBannerMessage =>
      'This device hasn\'t reached the rest of the household in a while. Your changes are saved — try pulling down to refresh.';

  @override
  String get settingsAccountSignOutError =>
      'Couldn\'t sign out. Please try again.';

  @override
  String get settingsAccountComingSoonTitle => 'Sync — coming soon';

  @override
  String settingsAccountReconnectTitle(String householdName) {
    return 'Reconnect to $householdName';
  }

  @override
  String get settingsAccountReconnectIntro =>
      'Replaces your local data — it\'s saved to a backup file on this device.';

  @override
  String get settingsAccountAdoptTitle => 'Put my household online';

  @override
  String get settingsAccountAdoptIntro =>
      'Put it online so your family can join with an invite code. Also keeps your other phones in step.';

  @override
  String settingsAccountAdoptConfirmTitle(String household) {
    return 'Put \'$household\' online?';
  }

  @override
  String get settingsAccountAdoptConfirmBody =>
      'This uploads your members, chores, completion history, notes and shopping list to the sync server, under your account. You can take it down again with Delete my account or Leave the household.';

  @override
  String get settingsAccountAdoptConfirmAction => 'Put online';

  @override
  String get settingsAccountLeftNotice =>
      'You left this household\'s online copy. What\'s on this phone stays yours; to share it again, start a new household from it later.';

  @override
  String get settingsAccountAdoptRetry => 'Try again';

  @override
  String get settingsAccountAdoptBlockedTitle =>
      'This household is already online';

  @override
  String get settingsAccountAdoptBlockedBody =>
      'It is already on the server, and this device is no longer part of it. Ask someone in the household for an invite code, then use \"Join an existing household\" below.';

  @override
  String get settingsAccountAdoptError =>
      'Couldn\'t put your household online. Please try again.';

  @override
  String settingsAccountLinkedSubtitle(String householdName) {
    return 'Synced with $householdName';
  }

  @override
  String get settingsAccountLastSyncedJustNow => 'Last synced just now';

  @override
  String settingsAccountLastSyncedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Last synced $count minutes ago',
      one: 'Last synced 1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String settingsAccountLastSyncedHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Last synced $count hours ago',
      one: 'Last synced 1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String settingsAccountLastSyncedOn(String date) {
    return 'Last synced $date';
  }

  @override
  String get settingsAccountInvite => 'Invite a member';

  @override
  String get settingsAccountJoinTitle => 'Join an existing household';

  @override
  String get settingsAccountJoinIntro =>
      'Use an invite code from another device — this replaces your local data.';

  @override
  String settingsAccountJoinSuccessSnackbar(String fileName) {
    return 'Your old data was saved to $fileName.';
  }

  @override
  String get joinHouseholdCodeTitle => 'Enter your invite code';

  @override
  String get joinHouseholdCodeBody =>
      'Ask a household member for the code from their Members screen.';

  @override
  String get joinHouseholdCodeLabel => 'Invite code';

  @override
  String get joinHouseholdCodeError =>
      'That code doesn\'t work. Double-check it for typos, or ask them to send you a new one.';

  @override
  String get joinHouseholdCodeUnknownError =>
      'Couldn\'t check that code. Check your connection and try again.';

  @override
  String get joinCodeErrorServer =>
      'Couldn\'t check the code right now — try again in a moment.';

  @override
  String get joinHouseholdContinue => 'Continue';

  @override
  String joinHouseholdChooserTitle(String household) {
    return 'Which one is you in $household?';
  }

  @override
  String joinHouseholdChooserAreYou(String name) {
    return 'Are you $name?';
  }

  @override
  String get joinHouseholdChooserNewMember => 'I\'m new here';

  @override
  String joinClaimConfirmTitle(String household, String name) {
    return 'Join $household as $name?';
  }

  @override
  String joinClaimConfirmBody(String name) {
    return 'You\'ll see and mark the chores assigned to $name. Pick another name if this isn\'t you.';
  }

  @override
  String get joinClaimConfirmJoin => 'Join';

  @override
  String get joinHouseholdNewMemberTitle => 'What\'s your name?';

  @override
  String get joinHouseholdNewMemberNameLabel => 'Name';

  @override
  String get joinHouseholdImportTitle => 'Bring over your open chores?';

  @override
  String get joinHouseholdImportBody =>
      'Your open chores and unchecked shopping items can come with you as new items — without their history. Everything else is replaced: your current household is saved to a backup file on this device.';

  @override
  String get joinHouseholdImportAccept => 'Bring them over';

  @override
  String get joinHouseholdImportDecline => 'Start fresh';

  @override
  String get joinHouseholdWorkingError =>
      'Something went wrong while joining the household. Please try again.';

  @override
  String get joinHouseholdNoLongerMemberError =>
      'This household is no longer available to your account. Nothing on this device was changed. Ask someone in the household for a new invite code.';

  @override
  String get statsSettingsEntry => 'Chore history';

  @override
  String get statsTitle => 'Chore history';

  @override
  String get statsWindowLast30Days => 'In the last 30 days';

  @override
  String statsWindowSinceStart(String date) {
    return 'Since you started, $date';
  }

  @override
  String statsTotalDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chores done',
      one: '1 chore done',
    );
    return '$_temp0';
  }

  @override
  String get statsShareUnknownMember => 'Someone else';

  @override
  String get statsChoresSectionTitle => 'Chores';

  @override
  String statsChoreTimesDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Done $count times',
      one: 'Done once',
    );
    return '$_temp0';
  }

  @override
  String statsChoreLastDone(String date) {
    return 'last $date';
  }

  @override
  String statsDeletedSectionHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted chores ($count)',
      one: 'Deleted chores (1)',
    );
    return '$_temp0';
  }

  @override
  String get statsDeletedNotice =>
      'This chore was deleted. Its history is kept here.';

  @override
  String statsHistoryTruncated(int shown, int total) {
    return 'Showing the $shown most recent of $total';
  }

  @override
  String get statsEmptyTitle => 'No completed chores yet';

  @override
  String get statsEmptyBody =>
      'As your household ticks chores off, this is where you\'ll see who did what.';

  @override
  String get statsErrorMessage => 'Couldn\'t load the history.';

  @override
  String get settingsAboutSectionTitle => 'About';

  @override
  String settingsAboutVersionLabel(String version, String buildNumber) {
    return 'Version $version ($buildNumber)';
  }

  @override
  String get settingsAboutLicensesEntry => 'Open source licenses';

  @override
  String get settingsAboutPrivacy => 'Privacy notes';

  @override
  String get settingsAboutSource => 'Source code';

  @override
  String get settingsAboutSyncServer => 'Sync server';

  @override
  String get settingsErrorReportsTitle => 'Send error reports';

  @override
  String get settingsErrorReportsSubtitle =>
      'Sends technical error details (no chore or member data) to the sync server to help fix bugs. Only when signed in.';

  @override
  String get settingsAboutDonateTitle => 'Support the app';

  @override
  String get settingsAboutDonateSubtitle => 'Ko-fi or PayPal — thank you!';

  @override
  String get settingsAboutDonateSheetTitle => 'Support Famdo';

  @override
  String get settingsAboutDonateKofiLabel => 'Ko-fi';

  @override
  String get settingsAboutDonatePaypalLabel => 'PayPal';

  @override
  String get settingsDataSectionTitle => 'Data';

  @override
  String get settingsResetEntry => 'Reset app data';

  @override
  String get settingsResetConfirm1Title => 'Reset app data?';

  @override
  String get settingsResetConfirm1Body =>
      'Export your data first if you want a copy. This permanently deletes your household, members, chores, and shopping list. There is no cloud backup — this can\'t be undone. If you\'re signed in, this also signs you out of this phone.';

  @override
  String get settingsResetConfirm1BodyLinked =>
      'Export your data first if you want a copy. Your household stays online — this phone just disconnects from it. You can reconnect by signing in again. This still permanently deletes this phone\'s local members, chores, and shopping list. Your account and email stay on the server — Delete my account removes them.';

  @override
  String get settingsResetConfirm1Action => 'Continue';

  @override
  String get settingsResetConfirm2Title => 'Delete everything?';

  @override
  String get settingsResetConfirm2Body =>
      'This is the last step. Once you confirm, everything is gone immediately.';

  @override
  String get settingsResetConfirm2Action => 'Delete everything';

  @override
  String get settingsResetError =>
      'Couldn\'t reset your data. Please try again.';

  @override
  String get exitConfirmDeleteLocalLabel => 'Also delete this phone\'s copy';

  @override
  String get exitConfirmDeleteLocalExplanation =>
      'Off: the household stays on this phone as your own local copy. On: this phone\'s members, chores and shopping list are deleted and the app starts fresh.';

  @override
  String get exitConfirmCancel => 'Cancel';

  @override
  String get householdExitNameLabel => 'Your name in the household\'s history';

  @override
  String get membershipRevokedTitle =>
      'You\'re no longer part of this household';

  @override
  String get membershipRevokedBody =>
      'This phone has stopped syncing: either the profile was removed from the online household, or the household itself is gone. Nothing is lost — everything you see here is still on this phone.';

  @override
  String get membershipRevokedAction => 'Got it';

  @override
  String get membershipRevokedConfirm => 'Done';
}
