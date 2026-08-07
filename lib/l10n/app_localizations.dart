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

  /// Tooltip for the category picker's trailing icon button (chore form and shopping item edit sheet), which pushes the manage-categories screen filtered to the picker's kind (feedback round 3: an in-context entry point alongside the existing Settings one).
  ///
  /// In en, this message translates to:
  /// **'Edit categories'**
  String get categoryPickerManageTooltip;

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

  /// Body of the chore delete-confirmation dialog. Deliberately states only what the user can verify (the chore leaves every list) -- it used to claim 'its history is kept', which is true in the DB but unobservable: every read path filters deletedAt IS NULL and no history screen exists, so the claim invited a destructive tap on a safety net that didn't exist (triage.md T1.2/D2). Not worded as permanent either, since the data genuinely is retained. TODO(F19): once the chore history view ships, restore stronger copy that also states history is kept and viewable -- see triage.md D2's two-step ordering.
  ///
  /// In en, this message translates to:
  /// **'This removes \'{choreTitle}\' from your list. You can\'t view it again yet.'**
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

  /// Button in the filtered-empty state (spec docs/feedback/2026-08-01-ux-audit.md B1) that resets both the member and category filters.
  ///
  /// In en, this message translates to:
  /// **'Show everything'**
  String get choresFilterClear;

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

  /// Final row of the acting-member switcher sheet (spec docs/feedback/2026-08-01-ux-audit.md B2), pushing the Members management screen.
  ///
  /// In en, this message translates to:
  /// **'Manage members'**
  String get actingManageMembers;

  /// Chores list empty-state message, shown when there are chores in the household but none currently pending ('all done').
  ///
  /// In en, this message translates to:
  /// **'No chores pending — nice work!'**
  String get choresEmptyState;

  /// Chores list empty-state titleLarge headline (spec docs/specs/theme-v2.md §4.1 item 6), shown above choresEmptyState when the household has chores but none are currently pending.
  ///
  /// In en, this message translates to:
  /// **'All done for today'**
  String get choresEmptyDoneHeadline;

  /// Chores list empty-state message shown instead of choresEmptyState on a fresh install (zero non-deleted chores in the household yet) — spec docs/specs/polish-round-1.md A1.
  ///
  /// In en, this message translates to:
  /// **'Add your first chore with +'**
  String get choresEmptyFresh;

  /// Chores list empty-state titleLarge headline (spec docs/specs/theme-v2.md §4.1 item 6), shown above choresEmptyFresh on a fresh install.
  ///
  /// In en, this message translates to:
  /// **'No chores yet'**
  String get choresEmptyFreshHeadline;

  /// Chores list empty-state message shown instead of choresEmptyState/choresEmptyFresh when a member/category filter hides every occurrence that would otherwise be visible (spec docs/feedback/2026-08-01-ux-audit.md B1).
  ///
  /// In en, this message translates to:
  /// **'Nothing here for this filter.'**
  String get choresEmptyFiltered;

  /// Chores list filtered-empty-state titleLarge headline (spec docs/specs/theme-v2.md §4.1 item 6), shown above choresEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get choresEmptyFilteredHeadline;

  /// Chores list load-error message.
  ///
  /// In en, this message translates to:
  /// **'Could not load your chores.'**
  String get choresErrorMessage;

  /// Day-progress card's titleLarge headline (spec docs/specs/theme-v2.md §4.1 item 1): n occurrences completed today out of m occurrences due today, overdue, or already completed today. The whole card is hidden when m is 0.
  ///
  /// In en, this message translates to:
  /// **'{n} of {m} done today'**
  String choresProgressTitle(int n, int m);

  /// Day-progress card's bodySmall sub-line shown when at least one of today's counted occurrences is still open: how many remain.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 still to go} other{{count} still to go}}'**
  String choresProgressRemainingToday(int count);

  /// Day-progress card's bodySmall sub-line shown instead of choresProgressRemainingToday once every occurrence counted for today has been completed.
  ///
  /// In en, this message translates to:
  /// **'That\'s everything — nice work'**
  String get choresProgressAllDoneToday;

  /// Day-progress card's extra bodySmall line (spec docs/specs/theme-v2.md §4.1 item 1, changed 2026-08-07 per triage T1.1/D3), shown only while a member/category filter is active on the chores list: makes explicit that the card's N-of-M counts are the filtered subset, not the whole household's day, so a narrowed '1 of 2' is never mistaken for everyone's progress.
  ///
  /// In en, this message translates to:
  /// **'Filtered — not the whole household'**
  String get choresProgressFilterActive;

  /// One-line purpose statement under the app name on the welcome screen (spec docs/specs/onboarding-v2.md §1), shown full-screen before any household exists locally.
  ///
  /// In en, this message translates to:
  /// **'Share chores and a shopping list with your household.'**
  String get welcomeTagline;

  /// Title of the welcome screen's primary card (id welcome.create): starts a brand-new local household, no account needed.
  ///
  /// In en, this message translates to:
  /// **'Set up a new household'**
  String get welcomeCreateTitle;

  /// Subtitle of the welcome screen's primary create card, stating up front that no account/network is required.
  ///
  /// In en, this message translates to:
  /// **'Keep it on this device — you can sync later.'**
  String get welcomeCreateSubtitle;

  /// Label of the inline name field (id welcome.create.name) shown after tapping the create card -- this becomes the sole admin member's name.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get welcomeCreateNameLabel;

  /// Label of the inline create form's confirm button (id welcome.create.confirm): creates the household with the typed name and lands on the chores tab.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get welcomeCreateConfirm;

  /// Inline error shown under the create form's name field if HouseholdCreateService.create throws (e.g. a local database error).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong setting up your household. Please try again.'**
  String get welcomeCreateError;

  /// Title of the welcome screen's secondary card (id welcome.join), and the app bar title of the welcome-join subpage it opens. Hidden entirely when Supabase isn't configured (offline/F-Droid builds, tests).
  ///
  /// In en, this message translates to:
  /// **'Join my family\'s household'**
  String get welcomeJoinTitle;

  /// Subtitle of the welcome screen's secondary join card.
  ///
  /// In en, this message translates to:
  /// **'Sign in and use an invite code from a family member\'s device.'**
  String get welcomeJoinSubtitle;

  /// Subtitle under the welcome-join subpage's reconnect offer (id welcome.join.reconnect, spec docs/specs/onboarding-v2.md §1/sync-backend.md §7.6), shown when findMyMembership finds the signed-in account already has a membership -- unlike the Settings Account section's equivalent copy (settingsAccountReconnectIntro), this never mentions replacing local data: nothing local exists yet on the welcome path.
  ///
  /// In en, this message translates to:
  /// **'This device isn\'t connected to it yet.'**
  String get welcomeJoinReconnectSubtitle;

  /// Small print at the bottom of the welcome screen (id welcome.offline), under both cards. Links nothing.
  ///
  /// In en, this message translates to:
  /// **'No account needed — everything stays on your device unless you sign in.'**
  String get welcomeOffline;

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

  /// Action label of the undo snackbar shown after completing, skipping, or pausing an occurrence/chore; reopens/resumes it via ChoreService.reopenOccurrence/unpauseChore.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get choresSnackbarUndo;

  /// Undo snackbar message shown after pausing a chore (T1.5, triage.md), mirroring choresSnackbarDone/choresSnackbarSkipped's one-word tone. The UNDO action (choresSnackbarUndo) resumes the chore via ChoreService.unpauseChore.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get choresSnackbarPaused;

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

  /// Title of the confirmation dialog shown when backing out of a dirty chore form (C4, docs/feedback/2026-08-06-conventions-audit.md; design-language.md interaction rule 7, 'never lose user input').
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get choreFormDiscardDialogTitle;

  /// Body of the discard-changes confirmation dialog shown when backing out of a dirty chore form.
  ///
  /// In en, this message translates to:
  /// **'Your edits to this chore won\'t be saved.'**
  String get choreFormDiscardDialogBody;

  /// Discard-changes dialog's safe action: dismisses the dialog and stays on the chore form with every entered value intact.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get choreFormDiscardKeepEditing;

  /// Discard-changes dialog's destructive action: confirms leaving the chore form, losing every unsaved change.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get choreFormDiscardConfirm;

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

  /// Chore form repeat-unit chip label for the day unit, pluralized by the current repeat interval so it reads correctly next to the interval number, e.g. 'Repeat every 2 Days'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Day} other{Days}}'**
  String choreFormUnitDayPlural(int count);

  /// Chore form repeat-unit chip label for the week unit, pluralized by the current repeat interval, e.g. 'Repeat every 2 Weeks'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Week} other{Weeks}}'**
  String choreFormUnitWeekPlural(int count);

  /// Chore form repeat-unit chip label for the month unit, pluralized by the current repeat interval, e.g. 'Repeat every 2 Months'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Month} other{Months}}'**
  String choreFormUnitMonthPlural(int count);

  /// Chore form recurrence-anchor option: due dates follow a fixed calendar schedule (specific weekday/day-of-month), rather than being relative to the last completion.
  ///
  /// In en, this message translates to:
  /// **'On fixed days'**
  String get choreFormAnchorScheduleTitle;

  /// Chore form recurrence-anchor option: due dates are relative to the last completion.
  ///
  /// In en, this message translates to:
  /// **'After last completion'**
  String get choreFormAnchorCompletionTitle;

  /// Retired 2026-08-06 (spec docs/specs/theme-v2.md §4.4 item 4): the fixed-days anchor option's subtitle now names the actual configured interval (see choreFormAnchorScheduleSubtitleDay/Week/MonthDayOfMonth/MonthNthWeekday/MonthLastWeekday) instead of this generic example. Key kept, never deleted, per that spec's §0.
  ///
  /// In en, this message translates to:
  /// **'e.g. every Tuesday'**
  String get choreFormAnchorScheduleSubtitle;

  /// Concrete hint under the fixed-days anchor option when the repeat unit is day, naming the actual current interval instead of a generic example.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Every day} other{Every {count} days}}'**
  String choreFormAnchorScheduleSubtitleDay(int count);

  /// Concrete hint under the fixed-days anchor option when the repeat unit is week, naming the actual configured weekday(s). {weekdays} is already locale-formatted via intl (comma-joined weekday names), never hardcoded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Every week on {weekdays}} other{Every {count} weeks on {weekdays}}}'**
  String choreFormAnchorScheduleSubtitleWeek(int count, String weekdays);

  /// Concrete hint under the fixed-days anchor option for a month-unit, day-of-month rule, naming the actual configured day. {ordinalDay} is the already locale-formatted ordinal day (e.g. '15th').
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Every month on the {ordinalDay}} other{Every {count} months on the {ordinalDay}}}'**
  String choreFormAnchorScheduleSubtitleMonthDayOfMonth(
    int count,
    String ordinalDay,
  );

  /// Concrete hint under the fixed-days anchor option for a month-unit, nth-weekday rule, naming the actual configured ordinal + weekday, e.g. 'Every month on the 4th Friday'. {ordinal} and {weekday} are already locale-formatted, never hardcoded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Every month on the {ordinal} {weekday}} other{Every {count} months on the {ordinal} {weekday}}}'**
  String choreFormAnchorScheduleSubtitleMonthNthWeekday(
    int count,
    String ordinal,
    String weekday,
  );

  /// Concrete hint under the fixed-days anchor option for a month-unit, last-weekday-of-month rule, naming the actual configured weekday, e.g. 'Every month on the last Friday'. {weekday} is already locale-formatted, never hardcoded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Every month on the last {weekday}} other{Every {count} months on the last {weekday}}}'**
  String choreFormAnchorScheduleSubtitleMonthLastWeekday(
    int count,
    String weekday,
  );

  /// Concrete hint under the after-last-completion anchor option when the repeat unit is day, naming the actual current interval instead of a generic example.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 day after last done} other{{count} days after last done}}'**
  String choreFormAnchorCompletionSubtitleDay(int count);

  /// Concrete hint under the after-last-completion anchor option when the repeat unit is week, naming the actual current interval instead of a generic example.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 week after last done} other{{count} weeks after last done}}'**
  String choreFormAnchorCompletionSubtitleWeek(int count);

  /// Concrete hint under the after-last-completion anchor option when the repeat unit is month, naming the actual current interval instead of a generic example.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 month after last done} other{{count} months after last done}}'**
  String choreFormAnchorCompletionSubtitleMonth(int count);

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

  /// Caption shown under the monthly pattern selector (and the weekly weekday chips when none are picked), pointing at the start date as the actual lever controlling the derived day/weekday.
  ///
  /// In en, this message translates to:
  /// **'Follows the start date — change the start date to change the day.'**
  String get choreFormPatternFollowsStartDate;

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

  /// Trailing chip in the chore form's assignee picker (spec docs/feedback/2026-08-01-ux-audit.md B2), opening the new-member sheet inline so a missing person can be added without abandoning the form.
  ///
  /// In en, this message translates to:
  /// **'Add member…'**
  String get choreFormAddMember;

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

  /// Button that unchecks every checked item immediately (no confirmation), returning them all to the main list — shown in the checked-items section header next to Clear checked.
  ///
  /// In en, this message translates to:
  /// **'Put all back'**
  String get shoppingUncheckAll;

  /// Undo snackbar message shown after tapping 'Clear checked' (T1.4): unlike every other delete-like action in the app, the bulk clear previously had no undo of its own.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Cleared 1 item} other{Cleared {count} items}}'**
  String shoppingClearedSnackbar(int count);

  /// Action label of the 'Clear checked' undo snackbar; restores exactly the items that tap cleared, via ShoppingRepository.restoreItems.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get shoppingClearedUndo;

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

  /// Settings screen list entry (spec docs/specs/polish-round-1.md B1), between the digest section and About. Tapping it shares a full JSON backup of every table via the OS share sheet.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get settingsExportEntry;

  /// Generic error snackbar shown when building or sharing the export document fails (spec docs/specs/polish-round-1.md B1).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export your data. Please try again.'**
  String get settingsExportError;

  /// Settings screen section header above the Members and Categories rows (spec docs/specs/theme-v2.md §4.2), the first group on the screen.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get settingsHouseholdSectionTitle;

  /// Settings screen list entry that opens member management (spec members-management §3), shown above the Categories entry.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get settingsMembersEntry;

  /// Title of the Members screen's 'Invite' row (spec docs/specs/sync-backend.md §7.3), shown only once this device is linked. Tapping it creates an invite code and opens the invite-code sheet.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get settingsMembersInviteEntry;

  /// Heading of the bottom sheet opened from the Invite row, showing the newly created code.
  ///
  /// In en, this message translates to:
  /// **'Invite a household member'**
  String get settingsMembersInviteSheetTitle;

  /// One-line explanatory copy in the invite-code sheet, stating the code's expiry (spec docs/specs/sync-backend.md §1: invites default to a 7-day expiry) AND that creating it revoked any previously active code (spec docs/feedback/2026-08-01-ux-audit.md A3: one live code per household).
  ///
  /// In en, this message translates to:
  /// **'Share this code — it replaces any earlier code and expires in 7 days.'**
  String get settingsMembersInviteSheetBody;

  /// Label of the invite-code sheet's share button (share_plus).
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get settingsMembersInviteShare;

  /// The message text handed to the OS share sheet when the invite-code sheet's share button is tapped.
  ///
  /// In en, this message translates to:
  /// **'Join my household on Famdo — enter the code {code} when you sign in.'**
  String settingsMembersInviteShareText(String code);

  /// Snackbar shown when creating an invite code fails; the sheet is never opened in that case.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create an invite. Please try again.'**
  String get settingsMembersInviteError;

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

  /// Subtitle of the editable household-name row at the top of the Members screen (spec docs/feedback/2026-08-01-ux-audit.md A2).
  ///
  /// In en, this message translates to:
  /// **'Household name'**
  String get manageMembersHouseholdSubtitle;

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

  /// T1.7: shown in place of the vanished Delete button when the member being edited is claimed (has a userId) -- worded as an accident prevented, not a permission (spec D1: the household is flat, this isn't about who's allowed).
  ///
  /// In en, this message translates to:
  /// **'This profile is linked to an account, so it can\'t be removed here.'**
  String get memberEditDeleteBlockedClaimed;

  /// T1.7: shown in place of the vanished Delete button when the member being edited is the household's last remaining active member.
  ///
  /// In en, this message translates to:
  /// **'A household needs at least one member, so this one can\'t be removed.'**
  String get memberEditDeleteBlockedLastMember;

  /// Title of the member delete-confirmation dialog (spec docs/feedback/2026-08-01-ux-audit.md A1), opened from the member edit sheet's delete action -- shown only when the member is deletable (unclaimed, not the last active member).
  ///
  /// In en, this message translates to:
  /// **'Delete {memberName}?'**
  String memberDeleteDialogTitle(String memberName);

  /// Body of the member delete-confirmation dialog, stating the referential consequences plainly per spec docs/feedback/2026-08-01-ux-audit.md A1 (MemberService.deleteMember's exact behavior).
  ///
  /// In en, this message translates to:
  /// **'This removes {memberName} from the household. Rotation chores drop them from the turn order — converting to a fixed assignee or \"anyone\" if too few people are left. Chores fixed to {memberName} open up to anyone, and anything currently assigned to them becomes unassigned. Past history — who completed what — stays unchanged.'**
  String memberDeleteDialogBody(String memberName);

  /// Title of the household-rename bottom sheet (spec docs/feedback/2026-08-01-ux-audit.md A2), opened from the Members screen's household-name row.
  ///
  /// In en, this message translates to:
  /// **'Rename household'**
  String get householdRenameTitle;

  /// Label of the household-rename sheet's required name text field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get householdRenameNameLabel;

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

  /// Settings screen section header above the Language, Appearance, and Daily summary rows (spec docs/specs/theme-v2.md §4.2).
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesSectionTitle;

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

  /// Settings screen list entry that opens the theme picker sheet (spec docs/feedback/2026-08-01-field-feedback.md G2), shown directly below the Language row. Its subtitle shows the current choice (System / Light / Dark).
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceEntry;

  /// Heading of the appearance picker bottom sheet opened from the settingsAppearanceEntry row.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSheetTitle;

  /// Appearance picker option (and settingsAppearanceEntry subtitle) meaning 'follow the OS theme' -- a stored settings.themeMode of NULL.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsAppearanceSystem;

  /// Appearance picker option (and settingsAppearanceEntry subtitle) for the light theme -- a stored settings.themeMode of 'light'.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceLight;

  /// Appearance picker option (and settingsAppearanceEntry subtitle) for the dark theme -- a stored settings.themeMode of 'dark'.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceDark;

  /// Intro line shown above the email field in the Account section's signed-out state.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your household across your devices.'**
  String get settingsAccountIntro;

  /// Label of the Account section's signed-out email TextField.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get settingsAccountEmailLabel;

  /// Label of the Account section's signed-out submit button, before it has been tapped.
  ///
  /// In en, this message translates to:
  /// **'Send sign-in link'**
  String get settingsAccountSendLink;

  /// Label the Account section's submit button switches to after a magic-link email has been sent at least once.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get settingsAccountSendAgain;

  /// Inline confirmation shown after a magic-link email is sent, naming the address it was sent to.
  ///
  /// In en, this message translates to:
  /// **'Check your email at {email} for your sign-in link.'**
  String settingsAccountCheckEmail(String email);

  /// One-line hint shown under the signed-out sign-in form when this device is linked but no user is currently signed in (spec docs/feedback/2026-08-01-ux-audit.md A5) -- explains why syncing has silently stopped. Still shown as-is (spec A1.1 adds settingsAccountPausedNotice ABOVE the form instead of replacing this).
  ///
  /// In en, this message translates to:
  /// **'This phone is linked to {householdName} — sign in to keep syncing.'**
  String settingsAccountSignedOutLinked(String householdName);

  /// Notice shown ABOVE the reused sign-in form in the Account section's honest signed-out-but-linked state (spec docs/feedback/2026-08-07-field-feedback.md A1.1) -- names the still-connected household and states plainly that syncing is paused, replacing what used to render as a bare, indistinguishable-from-never-linked sign-in form.
  ///
  /// In en, this message translates to:
  /// **'This device is still connected to {householdName}, but syncing is paused. Changes you make now will be sent once you sign in again.'**
  String settingsAccountPausedNotice(String householdName);

  /// Label of the Account section's A1.2 disconnect row -- a secondary, clearly non-primary action shown below the reused sign-in form in the signed-out-but-linked state, and below the Invite row in the normal signed-in linked state.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from the online household'**
  String get settingsAccountDisconnect;

  /// Title of the A1.2 disconnect confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from the online household?'**
  String get settingsAccountDisconnectConfirmTitle;

  /// Body of the A1.2 disconnect confirmation dialog -- states plainly that this is a local exit from sync, not a deletion: nothing local or remote is removed.
  ///
  /// In en, this message translates to:
  /// **'The household stays on this device exactly as it is. Other members keep their household, and nothing is deleted anywhere.'**
  String get settingsAccountDisconnectConfirmBody;

  /// Confirm button of the A1.2 disconnect confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get settingsAccountDisconnectConfirmAction;

  /// Snackbar shown when sending the magic-link email fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the sign-in link. Please try again.'**
  String get settingsAccountSendError;

  /// Label of the Account section's signed-in sign-out button.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsAccountSignOut;

  /// Title of the sign-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsAccountSignOutConfirmTitle;

  /// Body of the sign-out confirmation dialog (spec docs/feedback/2026-08-07-field-feedback.md A1.3): states plainly what signing out actually does -- syncing pauses, the household stays on this device, and changes made while signed out are kept and sent on the next sign-in -- replacing the old, less complete 'sign in again anytime' copy.
  ///
  /// In en, this message translates to:
  /// **'Syncing pauses until you sign in again. Your household stays on this device, and any changes you make while signed out are kept and sent once you sign in.'**
  String get settingsAccountSignOutConfirmBody;

  /// Confirm button of the sign-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsAccountSignOutConfirmAction;

  /// Snackbar shown when a USER-INITIATED pull-to-refresh fails (spec docs/specs/sync-freshness.md 2.3). Reassures rather than alarms: a local-first app has not lost anything, it just could not reach the server. The background triggers stay silent by design; only this explicit user action reports failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the household. Your changes are saved here and will sync later.'**
  String get syncRefreshError;

  /// Snackbar shown when signing out fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign out. Please try again.'**
  String get settingsAccountSignOutError;

  /// Label of the Account section's single disabled row shown when Supabase isn't configured (NoopAuthGateway) -- e.g. tests, E2E, and F-Droid builds without sync wired up.
  ///
  /// In en, this message translates to:
  /// **'Sync — coming soon'**
  String get settingsAccountComingSoonTitle;

  /// Title of the Account section's P2d reconnect row (spec docs/specs/sync-backend.md §7.6), shown FIRST -- above the adopt/join rows -- whenever this device is signed in, unlinked, and the signed-in account is already a claimed member of a household elsewhere (a returning device: phone reset, new phone).
  ///
  /// In en, this message translates to:
  /// **'Reconnect to {householdName}'**
  String settingsAccountReconnectTitle(String householdName);

  /// One-line explanatory copy under the reconnect row's title, stating plainly up front that local data gets replaced (spec §4/§7.6: same backup-file guarantee as join). Wording adjusted (spec docs/feedback/2026-08-01-ux-audit.md A4) to drop 'kept only in an archive file', which implied an in-app restore that doesn't exist yet -- 'saved to a backup file' makes no such promise.
  ///
  /// In en, this message translates to:
  /// **'Replaces your local data — it\'s saved to a backup file on this device.'**
  String get settingsAccountReconnectIntro;

  /// Title of the Account section's P2b adopt row (spec docs/specs/sync-backend.md §7.3), shown while signed in and unlinked.
  ///
  /// In en, this message translates to:
  /// **'Put my household online'**
  String get settingsAccountAdoptTitle;

  /// One-line explanatory copy under the adopt row's title, in its normal (non-error) state.
  ///
  /// In en, this message translates to:
  /// **'Makes your household available on your other devices.'**
  String get settingsAccountAdoptIntro;

  /// Title the adopt row switches to after a failed attempt; tapping it retries -- rerunning the adopt flow is always safe.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get settingsAccountAdoptRetry;

  /// Inline error shown as the adopt row's subtitle after a failed attempt.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t put your household online. Please try again.'**
  String get settingsAccountAdoptError;

  /// Subtitle the signed-in tile gains once this device is linked (spec docs/specs/sync-backend.md §7.3 last paragraph), naming the household.
  ///
  /// In en, this message translates to:
  /// **'Synced with {householdName}'**
  String settingsAccountLinkedSubtitle(String householdName);

  /// Settings -> Account: relative last-sync line under the linked-household subtitle (spec docs/specs/sync-freshness.md §2.4), shown when the last successful pull was under a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Last synced just now'**
  String get settingsAccountLastSyncedJustNow;

  /// Settings -> Account: relative last-sync line shown when the last successful pull was under an hour ago. {count} is whole minutes elapsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Last synced 1 minute ago} other{Last synced {count} minutes ago}}'**
  String settingsAccountLastSyncedMinutes(int count);

  /// Settings -> Account: relative last-sync line shown when the last successful pull was under 24 hours ago. {count} is whole hours elapsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Last synced 1 hour ago} other{Last synced {count} hours ago}}'**
  String settingsAccountLastSyncedHours(int count);

  /// Settings -> Account: relative last-sync line shown when the last successful pull was 24+ hours ago. {date} is a locale-formatted weekday+month+day string (package:intl DateFormat.MMMEd), e.g. 'Fri, Jul 31'.
  ///
  /// In en, this message translates to:
  /// **'Last synced {date}'**
  String settingsAccountLastSyncedOn(String date);

  /// Title of the Account section's 'Invite a member' row (spec docs/feedback/2026-08-01-ux-audit.md B3), shown below the signed-in tile once linked -- runs the same create-invite flow as the Members screen's Invite row.
  ///
  /// In en, this message translates to:
  /// **'Invite a member'**
  String get settingsAccountInvite;

  /// Title of the Account section's P2c join row (spec docs/specs/sync-backend.md §7.4), shown below the adopt row while signed in and unlinked.
  ///
  /// In en, this message translates to:
  /// **'Join an existing household'**
  String get settingsAccountJoinTitle;

  /// One-line explanatory copy under the join row's title, stating plainly up front that local data gets replaced (spec §4: reversible only via the archive file).
  ///
  /// In en, this message translates to:
  /// **'Use an invite code from another device — this replaces your local data.'**
  String get settingsAccountJoinIntro;

  /// Snackbar shown after a successful join, naming the archive file the old household was saved to (spec §4/§7.4).
  ///
  /// In en, this message translates to:
  /// **'Your old data was saved to {fileName}.'**
  String settingsAccountJoinSuccessSnackbar(String fileName);

  /// Title of the join sheet's first step: the invite-code entry.
  ///
  /// In en, this message translates to:
  /// **'Enter your invite code'**
  String get joinHouseholdCodeTitle;

  /// One-line explanatory copy on the join sheet's code-entry step.
  ///
  /// In en, this message translates to:
  /// **'Ask a household member for the code from their Members screen.'**
  String get joinHouseholdCodeBody;

  /// Label of the join sheet's code TextField (id settings.account.join.code).
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get joinHouseholdCodeLabel;

  /// Inline error shown on the code-entry step when the server rejects the code itself (a PostgrestException from listClaimableMembers). T1.6 finding: the server's _valid_invite check (supabase/migrations/20260731120000_initial_schema.sql) collapses 'no such code', 'expired', and 'revoked' into one identical query/exception with no distinguishing signal, so this message deliberately covers all three rather than guessing which one happened.
  ///
  /// In en, this message translates to:
  /// **'That code doesn\'t work. Double-check it for typos, or ask them to send you a new one.'**
  String get joinHouseholdCodeError;

  /// Inline error shown on the code-entry step when listClaimableMembers fails for a reason OTHER than the server rejecting the code (e.g. no network, a timeout) -- distinguished from joinHouseholdCodeError (T1.6) because the server never got to evaluate the code itself, so blaming the code would be misleading.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check that code. Check your connection and try again.'**
  String get joinHouseholdCodeUnknownError;

  /// Label of the join sheet's 'Continue' buttons (code entry and the new-member name step).
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get joinHouseholdContinue;

  /// Title of the join sheet's chooser step, listing unclaimed member profiles plus 'I'm new here'.
  ///
  /// In en, this message translates to:
  /// **'Which profile is yours?'**
  String get joinHouseholdChooserTitle;

  /// Label of one claimable-member row in the chooser step, naming the unclaimed profile.
  ///
  /// In en, this message translates to:
  /// **'Are you {name}?'**
  String joinHouseholdChooserAreYou(String name);

  /// Label of the chooser step's 'join as a new member' option, below the claimable-member rows.
  ///
  /// In en, this message translates to:
  /// **'I\'m new here'**
  String get joinHouseholdChooserNewMember;

  /// Title of the join sheet's new-member name step (after picking 'I'm new here').
  ///
  /// In en, this message translates to:
  /// **'What\'s your name?'**
  String get joinHouseholdNewMemberTitle;

  /// Label of the new-member name TextField (id settings.account.join.newMember.name).
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get joinHouseholdNewMemberNameLabel;

  /// Title of the in-flow import-offer step (spec docs/specs/sync-backend.md §7.4 step 2, amended 2026-08-01).
  ///
  /// In en, this message translates to:
  /// **'Bring over your open chores?'**
  String get joinHouseholdImportTitle;

  /// Body copy of the import-offer step -- states plainly that the old local data is replaced and saved to a backup file (spec §4). Wording adjusted (spec docs/feedback/2026-08-01-ux-audit.md A4) to drop 'kept only in an archive file', which implied an in-app restore that doesn't exist yet -- 'saved to a backup file' makes no such promise.
  ///
  /// In en, this message translates to:
  /// **'Your open chores and unchecked shopping items can come with you as new items — without their history. Everything else is replaced: your current household is saved to a backup file on this device.'**
  String get joinHouseholdImportBody;

  /// Accept button of the import-offer step.
  ///
  /// In en, this message translates to:
  /// **'Bring them over'**
  String get joinHouseholdImportAccept;

  /// Decline button of the import-offer step.
  ///
  /// In en, this message translates to:
  /// **'Start fresh'**
  String get joinHouseholdImportDecline;

  /// Inline error shown on the join sheet's working step if downloading/replacing the household fails; retrying re-runs the remaining flow, which is safe (the archive was already written and the old data is untouched until the replace transaction commits).
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while joining the household. Please try again.'**
  String get joinHouseholdWorkingError;

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

  /// Title of the About section's donation/tip-jar row; tapping opens the donate sheet (settingsAboutDonateSheetTitle).
  ///
  /// In en, this message translates to:
  /// **'Support the app'**
  String get settingsAboutDonateTitle;

  /// Subtitle of the About section's donation/tip-jar row, naming the two options offered in the donate sheet.
  ///
  /// In en, this message translates to:
  /// **'Ko-fi or PayPal — thank you!'**
  String get settingsAboutDonateSubtitle;

  /// Title of the donate sheet opened from the About section's donate row, listing the Ko-fi and PayPal link rows.
  ///
  /// In en, this message translates to:
  /// **'Support Famdo'**
  String get settingsAboutDonateSheetTitle;

  /// Label of the donate sheet's Ko-fi row; brand name, deliberately identical across locales.
  ///
  /// In en, this message translates to:
  /// **'Ko-fi'**
  String get settingsAboutDonateKofiLabel;

  /// Label of the donate sheet's PayPal row; brand name, deliberately identical across locales.
  ///
  /// In en, this message translates to:
  /// **'PayPal'**
  String get settingsAboutDonatePaypalLabel;

  /// Settings screen section header above the export row and the destructive reset row (spec docs/feedback/2026-08-01-field-feedback.md B4/F7), grouping both at the very bottom of Settings.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsDataSectionTitle;

  /// The destructive Settings row (spec docs/specs/polish-round-1.md B2) that starts the double-confirm reset flow.
  ///
  /// In en, this message translates to:
  /// **'Reset app data'**
  String get settingsResetEntry;

  /// Title of the first reset confirmation dialog (spec docs/specs/polish-round-1.md B2).
  ///
  /// In en, this message translates to:
  /// **'Reset app data?'**
  String get settingsResetConfirm1Title;

  /// Body of the first reset confirmation dialog on an UNLINKED device, stating the deletion is permanent and there is no cloud copy (spec docs/specs/polish-round-1.md B2).
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your household, members, chores, and shopping list. There is no cloud backup -- this can\'t be undone.'**
  String get settingsResetConfirm1Body;

  /// Body of the first reset confirmation dialog on a LINKED device (spec docs/feedback/2026-08-01-ux-audit.md A6): replaces the false 'no cloud backup' claim -- the household lives on the server and reconnecting restores it -- while keeping the local-deletion warning, adapted to make clear it's only this phone's local copy.
  ///
  /// In en, this message translates to:
  /// **'Your household stays online — this phone just disconnects from it. You can reconnect by signing in again. This still permanently deletes this phone\'s local members, chores, and shopping list.'**
  String get settingsResetConfirm1BodyLinked;

  /// Confirm button of the first reset dialog; advances to the second, final confirmation rather than deleting anything yet.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get settingsResetConfirm1Action;

  /// Title of the second (final) reset confirmation dialog (spec docs/specs/polish-round-1.md B2).
  ///
  /// In en, this message translates to:
  /// **'Delete everything?'**
  String get settingsResetConfirm2Title;

  /// Body of the second (final) reset confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'This is the last step. Once you confirm, everything is gone immediately.'**
  String get settingsResetConfirm2Body;

  /// The final destructive confirm button; tapping it wipes every table and re-bootstraps the app to the fresh-install state.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get settingsResetConfirm2Action;
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
