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
  String get actingMemberButtonTooltip => 'Switch who\'s acting';

  @override
  String get actingMemberSheetTitle => 'Who\'s doing chores right now?';

  @override
  String get choresEmptyState => 'No chores pending — nice work!';

  @override
  String get choresEmptyFresh => 'Add your first chore with +';

  @override
  String get choresErrorMessage => 'Could not load your chores.';

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
  String get shoppingAddHint => 'Add item…';

  @override
  String get shoppingAddTooltip => 'Add item';

  @override
  String get shoppingAddAlreadyOnList => 'Already on the list';

  @override
  String get shoppingAddMovedBack => 'Moved back to the list';

  @override
  String get settingsDigestSectionTitle => 'Daily summary';

  @override
  String get settingsDigestToggleTitle => 'Daily summary';

  @override
  String get settingsDigestTimeLabel => 'Notification time';

  @override
  String get settingsDigestPermissionHint =>
      'Notifications are turned off in system settings.';

  @override
  String get settingsDigestPermissionAction => 'Open settings';

  @override
  String get settingsExportEntry => 'Export data';

  @override
  String get settingsExportError =>
      'Couldn\'t export your data. Please try again.';

  @override
  String get settingsMembersEntry => 'Members';

  @override
  String get manageMembersTitle => 'Members';

  @override
  String get manageMembersErrorMessage => 'Could not load your members.';

  @override
  String get memberEditNewTitle => 'New member';

  @override
  String get memberEditEditTitle => 'Edit member';

  @override
  String get memberEditNameLabel => 'Name';

  @override
  String get memberEditColorLabel => 'Color';

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
  String get categoryDeleteDialogTitle => 'Delete category?';

  @override
  String categoryDeleteDialogBody(String categoryName) {
    return 'This deletes \'$categoryName\'. Chores and items using it become uncategorized.';
  }

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
  String get settingsAboutSectionTitle => 'About';

  @override
  String settingsAboutVersionLabel(String version, String buildNumber) {
    return 'Version $version ($buildNumber)';
  }

  @override
  String get settingsAboutLicensesEntry => 'Open source licenses';

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
  String get settingsResetSectionTitle => 'Danger zone';

  @override
  String get settingsResetEntry => 'Reset app data';

  @override
  String get settingsResetConfirm1Title => 'Reset app data?';

  @override
  String get settingsResetConfirm1Body =>
      'This permanently deletes your household, members, chores, and shopping list. There is no cloud backup -- this can\'t be undone.';

  @override
  String get settingsResetConfirm1Action => 'Continue';

  @override
  String get settingsResetConfirm2Title => 'Delete everything?';

  @override
  String get settingsResetConfirm2Body =>
      'This is the last step. Once you confirm, everything is gone immediately.';

  @override
  String get settingsResetConfirm2Action => 'Delete everything';
}
