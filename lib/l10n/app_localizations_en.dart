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
  String get categoryPickerManageTooltip => 'Edit categories';

  @override
  String get choresMenuMarkDoneFor => 'Mark done for…';

  @override
  String get choresMarkDoneForTitle => 'Who did this one?';

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
  String actingMemberSignedInAs(String name) {
    return 'You\'re signed in as $name';
  }

  @override
  String get actingManageMembers => 'Manage members';

  @override
  String get choresEmptyState => 'No chores pending — nice work!';

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
  String get choresProgressAllDoneToday => 'That\'s everything — nice work';

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
  String get welcomeJoinTitle => 'Join my family\'s household';

  @override
  String get welcomeJoinSubtitle =>
      'Sign in and use an invite code from a family member\'s device.';

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
  String catchUpBannerMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'We moved $count overdue chores forward to their most recent due dates, so nothing piled up.',
      one:
          'We moved 1 overdue chore forward to its most recent due date, so nothing piled up.',
    );
    return '$_temp0';
  }

  @override
  String get catchUpBannerDismissTooltip => 'Dismiss';

  @override
  String get choresSnackbarDone => 'Done';

  @override
  String choresSnackbarDoneNextDue(String dueText) {
    return 'Done — next due $dueText';
  }

  @override
  String choresSnackbarDoneBy(String name) {
    return 'Done — credited to $name';
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
  String get choreFormAddMember => 'Add member…';

  @override
  String choreFormAssigneeRemoveTooltip(String name) {
    return 'Remove $name from the rotation';
  }

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
  String get settingsDigestToggleDeniedHint =>
      'Not delivering — notifications are off';

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
  String get settingsHouseholdSectionTitle => 'Household';

  @override
  String get settingsMembersEntry => 'Members';

  @override
  String get settingsMembersInviteEntry => 'Invite';

  @override
  String get settingsMembersInviteSheetTitle => 'Invite a household member';

  @override
  String get settingsMembersInviteSheetBody =>
      'Share this code — it replaces any earlier code and expires in 7 days.';

  @override
  String get settingsMembersInviteShare => 'Share';

  @override
  String settingsMembersInviteShareText(String code) {
    return 'Join my household on Famdo — enter the code $code when you sign in.';
  }

  @override
  String get settingsMembersInviteError =>
      'Couldn\'t create an invite. Please try again.';

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
  String get memberEditDeleteBlockedClaimed =>
      'This profile is linked to an account, so it can\'t be removed here.';

  @override
  String get memberEditDeleteBlockedLastMember =>
      'A household needs at least one member, so this one can\'t be removed.';

  @override
  String memberDeleteDialogTitle(String memberName) {
    return 'Delete $memberName?';
  }

  @override
  String memberDeleteDialogBody(String memberName) {
    return 'This removes $memberName from the household. Rotation chores drop them from the turn order — converting to a fixed assignee or \"anyone\" if too few people are left. Chores fixed to $memberName open up to anyone, and anything currently assigned to them becomes unassigned. Past history — who completed what — stays unchanged.';
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
      other:
          'This deletes \'$categoryName\'. $count chores use it and will become uncategorized.',
      one:
          'This deletes \'$categoryName\'. 1 chore uses it and will become uncategorized.',
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
      other:
          'This deletes \'$categoryName\'. $count shopping items use it and will become uncategorized.',
      one:
          'This deletes \'$categoryName\'. 1 shopping item uses it and will become uncategorized.',
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
      'Sign in to sync your household across your devices.';

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
    return 'This device is still connected to $householdName, but syncing is paused. Changes you make now will be sent once you sign in again.';
  }

  @override
  String get settingsAccountDisconnect =>
      'Disconnect from the online household';

  @override
  String get settingsAccountDisconnectConfirmTitle =>
      'Disconnect from the online household?';

  @override
  String get settingsAccountDisconnectConfirmBody =>
      'The household stays on this device exactly as it is. Other members keep their household, and nothing is deleted anywhere.';

  @override
  String get settingsAccountDisconnectConfirmAction => 'Disconnect';

  @override
  String get settingsAccountSendError =>
      'Couldn\'t send the sign-in link. Please try again.';

  @override
  String get settingsAccountSignOut => 'Sign out';

  @override
  String get settingsAccountSignOutConfirmTitle => 'Sign out?';

  @override
  String get settingsAccountSignOutConfirmBody =>
      'Syncing pauses until you sign in again. Your household stays on this device, and any changes you make while signed out are kept and sent once you sign in.';

  @override
  String get settingsAccountSignOutConfirmAction => 'Sign out';

  @override
  String get syncRefreshError =>
      'Couldn\'t reach the household. Your changes are saved here and will sync later.';

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
      'Makes your household available on your other devices.';

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
  String get joinHouseholdContinue => 'Continue';

  @override
  String get joinHouseholdChooserTitle => 'Which profile is yours?';

  @override
  String joinHouseholdChooserAreYou(String name) {
    return 'Are you $name?';
  }

  @override
  String get joinHouseholdChooserNewMember => 'I\'m new here';

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
      'This permanently deletes your household, members, chores, and shopping list. There is no cloud backup -- this can\'t be undone. If you\'re signed in, this also signs you out of this phone.';

  @override
  String get settingsResetConfirm1BodyLinked =>
      'Your household stays online — this phone just disconnects from it. You can reconnect by signing in again. This still permanently deletes this phone\'s local members, chores, and shopping list.';

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
  String get exitConfirmDeleteLocalLabel => 'Also delete this phone\'s copy';

  @override
  String get exitConfirmDeleteLocalExplanation =>
      'Off: the household stays on this phone as your own local copy. On: this phone\'s members, chores and shopping list are deleted and the app starts fresh.';

  @override
  String get exitConfirmCancel => 'Cancel';

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
