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
  /// **'Chores'**
  String get appTitle;

  /// Shown full-screen when the app fails to bootstrap (e.g. the local database couldn't be opened).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong starting up: {error}'**
  String appBootstrapError(Object error);

  /// Generic 'cancel' action, used by the chore delete and shopping clear-checked confirmation dialogs.
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

  /// The settings bottom-navigation tab label, and the (placeholder) settings screen's app bar title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTabLabel;

  /// Body text of a not-yet-built tab's placeholder screen, e.g. 'Settings — coming soon'.
  ///
  /// In en, this message translates to:
  /// **'{title} — coming soon'**
  String settingsComingSoon(String title);

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

  /// Overdue chore occurrence's due-date label; {date} is already locale-formatted (e.g. 'Jul 20').
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String choresOccurrenceDueLabel(String date);

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

  /// Chores list empty-state message, shown when there are no pending occurrences to show.
  ///
  /// In en, this message translates to:
  /// **'No chores pending — nice work!'**
  String get choresEmptyState;

  /// Chores list load-error message.
  ///
  /// In en, this message translates to:
  /// **'Could not load your chores.'**
  String get choresErrorMessage;

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

  /// Button that clears every checked item, shown in the checked-items section header.
  ///
  /// In en, this message translates to:
  /// **'Clear checked'**
  String get shoppingClearButton;

  /// Title of the clear-checked-items confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear checked items?'**
  String get shoppingClearDialogTitle;

  /// Body of the clear-checked-items confirmation dialog, explaining the consequence.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{This removes 1 checked item from the list.} other{This removes {count} checked items from the list.}}'**
  String shoppingClearDialogBody(int count);

  /// Destructive confirm button of the clear-checked-items dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get shoppingClearConfirm;

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
