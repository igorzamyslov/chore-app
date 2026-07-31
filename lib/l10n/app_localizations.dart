import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// The application title shown in the task switcher.
  ///
  /// In en, this message translates to:
  /// **'Famdo'**
  String get appTitle;

  /// Shown full-screen when the app fails to bootstrap (e.g. the local database couldn't be opened).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong starting up: {error}'**
  String appBootstrapError(Object error);

  /// Daily digest notification body when there are due-today occurrences but nothing overdue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 chore today} other{{count} chores today}}'**
  String notificationDigestDueOnly(int count);

  /// Daily digest notification body when there are overdue occurrences but nothing due today (an overdue-only day still notifies).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 overdue chore} other{{count} overdue chores}}'**
  String notificationDigestOverdueOnly(int count);

  /// Daily digest notification body when there are both due-today and overdue occurrences, e.g. '2 chores today · 1 overdue'.
  ///
  /// In en, this message translates to:
  /// **'{dueCount, plural, one{1 chore today} other{{dueCount} chores today}} · {overdueCount, plural, one{1 overdue} other{{overdueCount} overdue}}'**
  String notificationDigestBoth(int dueCount, int overdueCount);

  /// Generic 'cancel' action, used by the chore delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic 'delete' action, used by the chore action sheet's delete entry, the chore delete confirmation dialog's destructive button, and the shopping item edit sheet's delete button.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Generic 'save' action, used by the chore form's and the shopping item edit sheet's primary buttons.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic 'retry' action shown under a load-error message, on both the chores and shopping list screens.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// The chores bottom-navigation tab label, and the chores list screen's app bar title.
  ///
  /// In en, this message translates to:
  /// **'Chores'**
  String get choresTabLabel;

  /// The shopping bottom-navigation tab label, and the shopping list screen's app bar title.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get shoppingTabLabel;

  /// The settings bottom-navigation tab label, and the settings screen's app bar title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTabLabel;

  /// The category picker's chip for 'no category selected', shown in both the chore form and the shopping item edit sheet.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get categoryPickerNone;

  /// Chore occurrence action-sheet entry: skip the pending occurrence.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get choresMenuSkip;

  /// Chore occurrence action-sheet entry: open the chore in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get choresMenuEdit;

  /// Chore occurrence action-sheet entry: pause the chore.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get choresMenuPause;

  /// Title of the chore delete-confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete chore?'**
  String get choresDeleteDialogTitle;

  /// Body of the chore delete-confirmation dialog, explaining the consequence.
  ///
  /// In en, this message translates to:
  /// **'This deletes \'{choreTitle}\'. Its history is kept, but its pending occurrence is removed.'**
  String choresDeleteDialogBody(String choreTitle);

  /// Tooltip for a chore occurrence tile's leading complete button.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get choresOccurrenceCompleteTooltip;

  /// Tooltip for a chore occurrence tile's trailing overflow-menu button.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get choresOccurrenceMoreActionsTooltip;

  /// Chore occurrence tile's per-tile due text when the occurrence is due today. Shown on every tile regardless of which section it's in, independent of the 'Today' section header.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get choresDueToday;

  /// Chore occurrence tile's per-tile due text when the occurrence is due tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get choresDueTomorrow;

  /// Chore occurrence tile's per-tile due text for an occurrence due 2-7 days from now.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{In 1 day} other{In {count} days}}'**
  String choresDueInDays(int count);

  /// Chore occurrence tile's per-tile due text for an overdue occurrence, shown in the theme's error color. {count} is the number of days since the due date.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Overdue · 1 day} other{Overdue · {count} days}}'**
  String choresDueOverdue(int count);

  /// Chores list section header: occurrences due before today.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get choresSectionOverdue;

  /// Chores list section header: occurrences due today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get choresSectionToday;

  /// Chores list section header: occurrences due tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get choresSectionTomorrow;

  /// Chores list section header: occurrences due later this week.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get choresSectionThisWeek;

  /// Chores list section header: occurrences due after the coming Sunday, but still within the current calendar month.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get choresSectionThisMonth;

  /// Chores list section header: occurrences due after this week.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get choresSectionLater;

  /// Tooltip for the chores list's member-filter button.
  ///
  /// In en, this message translates to:
  /// **'Filter by member'**
  String get choresFilterMemberTooltip;

  /// Member-filter menu entry that resets the filter to show every member's chores.
  ///
  /// In en, this message translates to:
  /// **'All members'**
  String get choresFilterMemberAll;

  /// Tooltip for the chores list's category-filter button.
  ///
  /// In en, this message translates to:
  /// **'Filter by category'**
  String get choresFilterCategoryTooltip;

  /// Category-filter menu entry that resets the filter to show every category's chores.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get choresFilterCategoryAll;

  /// Tooltip for the chores app bar's leading acting-member avatar button (spec members-management §4).
  ///
  /// In en, this message translates to:
  /// **'Switch who\'s acting'**
  String get actingMemberButtonTooltip;

  /// Title of the acting-member switcher bottom sheet opened from the chores app bar.
  ///
  /// In en, this message translates to:
  /// **'Who\'s doing chores right now?'**
  String get actingMemberSheetTitle;

  /// Chores list empty-state message, shown when there are chores in the household but none currently pending ('all done').
  ///
  /// In en, this message translates to:
  /// **'No chores pending — nice work!'**
  String get choresEmptyState;

  /// Chores list empty-state message shown instead of choresEmptyState on a fresh install (zero non-deleted chores in the household yet) — spec docs/specs/polish-round-1.md A1.
  ///
  /// In en, this message translates to:
  /// **'Add your first chore with +'**
  String get choresEmptyFresh;

  /// Chores list load-error message.
  ///
  /// In en, this message translates to:
  /// **'Could not load your chores.'**
  String get choresErrorMessage;

  /// First-run name-prompt banner copy at the top of the chores list (spec docs/specs/polish-round-1.md A2), shown while the household still consists of just the bootstrap 'Me' member.
  ///
  /// In en, this message translates to:
  /// **'Who\'s doing the chores here?'**
  String get onboardingNameBannerMessage;

  /// Action button on the name-prompt banner opening the member edit sheet, prefilled for the bootstrap member.
  ///
  /// In en, this message translates to:
  /// **'Set my name'**
  String get onboardingNameBannerSetAction;

  /// Tooltip for the name-prompt banner's X dismiss button.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get onboardingNameBannerDismissTooltip;

  /// Digest pre-prompt banner copy at the top of the chores list (spec docs/specs/polish-round-1.md A3), shown before the one-shot OS notification-permission dialog.
  ///
  /// In en, this message translates to:
  /// **'Want a daily summary of what\'s due?'**
  String get digestPrepromptMessage;

  /// Digest pre-prompt banner's action that marks it shown, requests the OS notification permission, then triggers a digest recompute.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get digestPrepromptEnableAction;

  /// Digest pre-prompt banner's dismiss action: marks it shown without requesting the OS permission (the digest stays enabled but silent until permission arrives via Settings).
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get digestPrepromptDismissAction;

  /// Undo snackbar message after completing a one-off occurrence (no next occurrence is created).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get choresSnackbarDone;

  /// Undo snackbar message after completing a recurring occurrence. {dueText} is the next occurrence's already-localized due text (e.g. 'Tomorrow', 'In 3 days', 'Fri, Jul 31').
  ///
  /// In en, this message translates to:
  /// **'Done — next due {dueText}'**
  String choresSnackbarDoneNextDue(String dueText);

  /// Undo snackbar message after skipping a one-off occurrence (no next occurrence is created).
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get choresSnackbarSkipped;

  /// Undo snackbar message after skipping a recurring occurrence. {dueText} is the next occurrence's already-localized due text (e.g. 'Tomorrow', 'In 3 days', 'Fri, Jul 31').
  ///
  /// In en, this message translates to:
  /// **'Skipped — next due {dueText}'**
  String choresSnackbarSkippedNextDue(String dueText);

  /// Action label of the undo snackbar shown after completing or skipping an occurrence; reopens it via ChoreService.reopenOccurrence.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get choresSnackbarUndo;

  /// Header of the collapsed-by-default 'Done today' section, showing how many occurrences were closed (done or skipped) today.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Done today (1)} other{Done today ({count})}}'**
  String choresDoneHeader(int count);

  /// Done-today section row marker for an occurrence that was completed, as opposed to skipped.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get choresDoneStatusDone;

  /// Done-today section row marker for an occurrence that was skipped, as opposed to completed.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get choresDoneStatusSkipped;

  /// Done-today section row: who closed the occurrence. The completing member's name for a done row, or the assigned member's name for a skipped row (skipping doesn't record a dedicated closer).
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String choresDoneClosedByLabel(String name);

  /// Done-today section row action: undoes the close and restores the occurrence to pending, via ChoreService.reopenOccurrence.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get choresDoneReopen;

  /// Header of the collapsed-by-default 'Paused' section, showing how many chores are paused.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Paused (1)} other{Paused ({count})}}'**
  String choresPausedHeader(int count);

  /// Paused-section row badge marking a chore as paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get choresPausedBadge;

  /// Paused-section row action: unpauses the chore via ChoreService.unpauseChore.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get choresPausedResume;

  /// Chore form app bar title when editing an existing chore.
  ///
  /// In en, this message translates to:
  /// **'Edit chore'**
  String get choreFormEditTitle;

  /// Chore form app bar title when creating a new chore.
  ///
  /// In en, this message translates to:
  /// **'New chore'**
  String get choreFormNewTitle;

  /// Label of the chore form's required title text field.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get choreFormTitleLabel;

  /// Label of the chore form's optional notes text field.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get choreFormNotesLabel;

  /// Inline validation error shown under the chore title field when it's left empty.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get choreFormTitleRequiredError;

  /// Label of the chore form's repeat on/off switch.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get choreFormRepeatToggleLabel;

  /// Label of the chore form's repeat-interval number field, e.g. 'Repeat every' [2] weeks.
  ///
  /// In en, this message translates to:
  /// **'Repeat every'**
  String get choreFormRepeatEveryLabel;

  /// Inline validation error shown under the repeat-interval field when it's not a positive integer.
  ///
  /// In en, this message translates to:
  /// **'Must be at least 1'**
  String get choreFormIntervalTooSmallError;

  /// Chore form repeat-unit chip: day.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get choreFormUnitDay;

  /// Chore form repeat-unit chip: week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get choreFormUnitWeek;

  /// Chore form repeat-unit chip: month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get choreFormUnitMonth;

  /// Chore form recurrence-anchor option: due dates follow a fixed calendar schedule.
  ///
  /// In en, this message translates to:
  /// **'On a fixed schedule'**
  String get choreFormAnchorScheduleTitle;

  /// Chore form recurrence-anchor option: due dates are relative to the last completion.
  ///
  /// In en, this message translates to:
  /// **'After last completion'**
  String get choreFormAnchorCompletionTitle;

  /// Example hint under the fixed-schedule anchor option.
  ///
  /// In en, this message translates to:
  /// **'e.g. every Tuesday'**
  String get choreFormAnchorScheduleSubtitle;

  /// Example hint under the after-last-completion anchor option.
  ///
  /// In en, this message translates to:
  /// **'e.g. 4 days after last done'**
  String get choreFormAnchorCompletionSubtitle;

  /// Monthly repeat chip label for 'day of month' mode; {ordinalDay} is the already locale-formatted ordinal day (e.g. '15th').
  ///
  /// In en, this message translates to:
  /// **'On the {ordinalDay}'**
  String monthlyDayOfMonthLabel(String ordinalDay);

  /// Monthly repeat chip label for 'nth weekday of month' mode, e.g. 'On the 3rd Tuesday'. {ordinal} is already locale-formatted (e.g. '3rd'); {weekday} comes from intl's date formatting (e.g. 'Tuesday'), never hardcoded.
  ///
  /// In en, this message translates to:
  /// **'On the {ordinal} {weekday}'**
  String monthlyNthWeekdayLabel(String ordinal, String weekday);

  /// Monthly repeat chip label for the last occurrence of a weekday in the month, e.g. 'On the last Tuesday'. {weekday} comes from intl's date formatting, never hardcoded.
  ///
  /// In en, this message translates to:
  /// **'On the last {weekday}'**
  String monthlyLastWeekdayLabel(String weekday);

  /// Chore form assignment-mode chip: a fixed single assignee.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get choreFormAssignmentFixed;

  /// Chore form assignment-mode chip: rotates between several assignees.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get choreFormAssignmentRotation;

  /// Chore form assignment-mode chip: no specific assignee.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get choreFormAssignmentAnyone;

  /// Rotation-mode assignee chip label showing the member's tap order before their name, e.g. '1. Alex'.
  ///
  /// In en, this message translates to:
  /// **'{order}. {name}'**
  String choreFormAssigneeOrderLabel(int order, String name);

  /// Inline validation error shown when 'fixed' assignment mode has no member picked.
  ///
  /// In en, this message translates to:
  /// **'Pick one member'**
  String get choreFormAssignmentNeedsOneError;

  /// Inline validation error shown when 'rotation' assignment mode has fewer than two members picked.
  ///
  /// In en, this message translates to:
  /// **'Pick at least two'**
  String get choreFormAssignmentNeedsTwoError;

  /// Label of the chore form's start-date field.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get choreFormStartDateLabel;

  /// Shopping list empty-state message, shown when there are no items at all.
  ///
  /// In en, this message translates to:
  /// **'Shopping list is empty'**
  String get shoppingEmptyState;

  /// Shopping list load-error message.
  ///
  /// In en, this message translates to:
  /// **'Could not load your shopping list.'**
  String get shoppingErrorMessage;

  /// Undo snackbar message shown after deleting a shopping item from its edit sheet (spec docs/specs/polish-round-1.md C3), mirroring the chores undo tone.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get shoppingDeletedSnackbar;

  /// Action label of the shopping-delete undo snackbar; restores the item by clearing its deleted_at (soft delete).
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get shoppingDeletedUndo;

  /// Label of the shopping item edit sheet's required name text field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get shoppingEditNameLabel;

  /// Label of the shopping item edit sheet's optional quantity/note text field.
  ///
  /// In en, this message translates to:
  /// **'Quantity / note'**
  String get shoppingEditQuantityLabel;

  /// Inline validation error shown under the shopping item name field when it's left empty.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get shoppingEditNameRequiredError;

  /// Shopping list category-run header shown above items that have no category.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get shoppingUncategorized;

  /// Header of the collapsed-by-default checked-items section, showing how many items are checked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{In the cart (1)} other{In the cart ({count})}}'**
  String shoppingCartHeader(int count);

  /// Button that clears every checked item immediately (no confirmation), shown in the checked-items section header.
  ///
  /// In en, this message translates to:
  /// **'Clear checked'**
  String get shoppingClearButton;

  /// Placeholder hint text of the shopping list's quick-add text field.
  ///
  /// In en, this message translates to:
  /// **'Add item…'**
  String get shoppingAddHint;

  /// Tooltip of the shopping list's quick-add submit button.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get shoppingAddTooltip;

  /// Snackbar shown on quick-add submit or suggestion tap when an unchecked active item with the same normalized name already exists; no new row is added.
  ///
  /// In en, this message translates to:
  /// **'Already on the list'**
  String get shoppingAddAlreadyOnList;

  /// Snackbar shown on quick-add submit or suggestion tap when a checked active item with the same normalized name already exists; it's unchecked (restored) instead of adding a new row.
  ///
  /// In en, this message translates to:
  /// **'Moved back to the list'**
  String get shoppingAddMovedBack;

  /// Settings screen section header above the digest toggle/time rows (spec notifications.md).
  ///
  /// In en, this message translates to:
  /// **'Daily summary'**
  String get settingsDigestSectionTitle;

  /// Title of the settings screen's digest on/off switch row.
  ///
  /// In en, this message translates to:
  /// **'Daily summary'**
  String get settingsDigestToggleTitle;

  /// Title of the settings screen's digest time row, which shows the chosen time as trailing text and opens a time picker on tap.
  ///
  /// In en, this message translates to:
  /// **'Notification time'**
  String get settingsDigestTimeLabel;

  /// Inline hint shown on the settings screen when the digest is enabled but the OS notification permission is denied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off in system settings.'**
  String get settingsDigestPermissionHint;

  /// Button label in the digest permission hint row; opens the OS app settings screen.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get settingsDigestPermissionAction;

  /// Settings screen list entry that opens member management (spec members-management §3), shown above the Categories entry.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get settingsMembersEntry;

  /// App bar title of the manage-members screen.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get manageMembersTitle;

  /// Manage-members screen load-error message.
  ///
  /// In en, this message translates to:
  /// **'Could not load your members.'**
  String get manageMembersErrorMessage;

  /// Member edit sheet heading when adding a new member.
  ///
  /// In en, this message translates to:
  /// **'New member'**
  String get memberEditNewTitle;

  /// Member edit sheet heading when editing an existing member.
  ///
  /// In en, this message translates to:
  /// **'Edit member'**
  String get memberEditEditTitle;

  /// Label of the member edit sheet's required name text field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get memberEditNameLabel;

  /// Section label above the member edit sheet's color swatch picker.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get memberEditColorLabel;

  /// Settings screen list entry that opens category management (spec ux-round-2 B1).
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get settingsCategoriesEntry;

  /// App bar title of the manage-categories screen.
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get manageCategoriesTitle;

  /// Manage-categories screen's kind-switcher segment label for chore categories.
  ///
  /// In en, this message translates to:
  /// **'Chores'**
  String get manageCategoriesKindChore;

  /// Manage-categories screen's kind-switcher segment label for shopping categories.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get manageCategoriesKindShopping;

  /// Manage-categories screen empty-state message, shown when the selected kind has no active categories left.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get manageCategoriesEmptyState;

  /// Manage-categories screen load-error message.
  ///
  /// In en, this message translates to:
  /// **'Could not load your categories.'**
  String get manageCategoriesErrorMessage;

  /// Category edit sheet heading when adding a new category.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryEditNewTitle;

  /// Category edit sheet heading when editing an existing category.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get categoryEditEditTitle;

  /// Label of the category edit sheet's required name text field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get categoryEditNameLabel;

  /// Inline validation error shown under the category name field when it's left empty.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get categoryEditNameRequiredError;

  /// Section label above the category edit sheet's icon picker grid.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get categoryEditIconLabel;

  /// Section label above the category edit sheet's color swatch picker.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get categoryEditColorLabel;

  /// Title of the category delete-confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete category?'**
  String get categoryDeleteDialogTitle;

  /// Body of the category delete-confirmation dialog, explaining the consequence.
  ///
  /// In en, this message translates to:
  /// **'This deletes \'{categoryName}\'. Chores and items using it become uncategorized.'**
  String categoryDeleteDialogBody(String categoryName);

  /// Settings screen list entry that opens the language picker sheet (spec docs/next-session-plan.md #5), shown below the Categories entry. Its subtitle shows the current choice (System default / English / Deutsch).
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageEntry;

  /// Heading of the language picker bottom sheet opened from the settingsLanguageEntry row.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get settingsLanguageSheetTitle;

  /// Language picker option (and settingsLanguageEntry subtitle) meaning 'follow the OS locale' -- a stored settings.locale of NULL.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// Language picker option for English. A proper name: shown as 'English' regardless of the app's current UI locale, so this value is identical in every arb file.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Language picker option for German. A proper name: shown as 'Deutsch' regardless of the app's current UI locale, so this value is identical in every arb file.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get settingsLanguageDeutsch;

  /// Settings screen section header above the About rows (app version, licenses, donate placeholder), matching the digest section header's style.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSectionTitle;

  /// Subtitle of the About section's non-tappable version row, under the app's name. version/buildNumber are an em dash ('—') while packageInfoProvider is still loading.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({buildNumber})'**
  String settingsAboutVersionLabel(String version, String buildNumber);

  /// About section row that opens Flutter's built-in showLicensePage.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get settingsAboutLicensesEntry;

  /// Title of the About section's disabled donation/tip-jar placeholder row (no action wired yet).
  ///
  /// In en, this message translates to:
  /// **'Support the app'**
  String get settingsAboutDonateTitle;

  /// Subtitle of the About section's disabled donation/tip-jar placeholder row.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get settingsAboutDonateSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
