// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Famdo';

  @override
  String appBootstrapError(Object error) {
    return 'Beim Start ist etwas schiefgelaufen: $error';
  }

  @override
  String notificationDigestDueOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufgaben heute',
      one: '1 Aufgabe heute',
    );
    return '$_temp0';
  }

  @override
  String notificationDigestOverdueOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count überfällige Aufgaben',
      one: '1 überfällige Aufgabe',
    );
    return '$_temp0';
  }

  @override
  String notificationDigestBoth(int dueCount, int overdueCount) {
    String _temp0 = intl.Intl.pluralLogic(
      dueCount,
      locale: localeName,
      other: '$dueCount Aufgaben heute',
      one: '1 Aufgabe heute',
    );
    String _temp1 = intl.Intl.pluralLogic(
      overdueCount,
      locale: localeName,
      other: '$overdueCount überfällig',
      one: '1 überfällig',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get choresTabLabel => 'Aufgaben';

  @override
  String get shoppingTabLabel => 'Einkaufsliste';

  @override
  String get settingsTabLabel => 'Einstellungen';

  @override
  String get categoryPickerNone => 'Keine';

  @override
  String get categoryPickerManageTooltip => 'Kategorien bearbeiten';

  @override
  String get choresMenuSkip => 'Überspringen';

  @override
  String get choresMenuEdit => 'Bearbeiten';

  @override
  String get choresMenuPause => 'Pausieren';

  @override
  String get choresDeleteDialogTitle => 'Aufgabe löschen?';

  @override
  String choresDeleteDialogBody(String choreTitle) {
    return 'Damit entfernst du \'$choreTitle\' aus deiner Liste. Wieder ansehen kannst du es noch nicht.';
  }

  @override
  String get choresOccurrenceCompleteTooltip => 'Erledigen';

  @override
  String get choresOccurrenceMoreActionsTooltip => 'Weitere Aktionen';

  @override
  String get choresDueToday => 'Heute';

  @override
  String get choresDueTomorrow => 'Morgen';

  @override
  String choresDueInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count Tagen',
      one: 'In 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String choresDueOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Überfällig · $count Tage',
      one: 'Überfällig · 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get choresSectionOverdue => 'Überfällig';

  @override
  String get choresSectionToday => 'Heute';

  @override
  String get choresSectionTomorrow => 'Morgen';

  @override
  String get choresSectionThisWeek => 'Diese Woche';

  @override
  String get choresSectionThisMonth => 'Diesen Monat';

  @override
  String get choresSectionLater => 'Später';

  @override
  String get choresFilterMemberTooltip => 'Nach Mitglied filtern';

  @override
  String get choresFilterMemberAll => 'Alle Mitglieder';

  @override
  String get choresFilterCategoryTooltip => 'Nach Kategorie filtern';

  @override
  String get choresFilterCategoryAll => 'Alle Kategorien';

  @override
  String get choresFilterClear => 'Alles anzeigen';

  @override
  String get actingMemberButtonTooltip => 'Aktives Mitglied wechseln';

  @override
  String get actingMemberSheetTitle => 'Wer ist gerade dran?';

  @override
  String get actingManageMembers => 'Mitglieder verwalten';

  @override
  String get choresEmptyState => 'Keine Aufgaben offen — gut gemacht!';

  @override
  String get choresEmptyDoneHeadline => 'Für heute alles erledigt';

  @override
  String get choresEmptyFresh => 'Füge mit + deine erste Aufgabe hinzu';

  @override
  String get choresEmptyFreshHeadline => 'Noch keine Aufgaben';

  @override
  String get choresEmptyFiltered => 'Für diesen Filter gibt es nichts.';

  @override
  String get choresEmptyFilteredHeadline => 'Keine Treffer';

  @override
  String get choresErrorMessage =>
      'Deine Aufgaben konnten nicht geladen werden.';

  @override
  String choresProgressTitle(int n, int m) {
    return '$n von $m heute erledigt';
  }

  @override
  String choresProgressRemainingToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Noch $count übrig',
      one: 'Noch 1 übrig',
    );
    return '$_temp0';
  }

  @override
  String get choresProgressAllDoneToday => 'Alles erledigt — gut gemacht!';

  @override
  String get choresProgressFilterActive =>
      'Gefiltert – nicht der ganze Haushalt';

  @override
  String get welcomeTagline =>
      'Teile Aufgaben und eine Einkaufsliste mit deinem Haushalt.';

  @override
  String get welcomeCreateTitle => 'Neuen Haushalt einrichten';

  @override
  String get welcomeCreateSubtitle =>
      'Bleibt erst mal auf diesem Gerät — du kannst später synchronisieren.';

  @override
  String get welcomeCreateNameLabel => 'Dein Name';

  @override
  String get welcomeCreateConfirm => 'Los geht\'s';

  @override
  String get welcomeCreateError =>
      'Beim Einrichten deines Haushalts ist etwas schiefgelaufen. Versuch es noch mal.';

  @override
  String get welcomeJoinTitle => 'Dem Haushalt meiner Familie beitreten';

  @override
  String get welcomeJoinSubtitle =>
      'Melde dich an und nutze einen Einladungscode vom Gerät eines Familienmitglieds.';

  @override
  String get welcomeJoinReconnectSubtitle =>
      'Dieses Gerät ist noch nicht damit verbunden.';

  @override
  String get welcomeOffline =>
      'Kein Konto nötig — alles bleibt auf deinem Gerät, außer du meldest dich an.';

  @override
  String get onboardingNameBannerMessage => 'Wer erledigt hier die Aufgaben?';

  @override
  String get onboardingNameBannerSetAction => 'Meinen Namen festlegen';

  @override
  String get onboardingNameBannerDismissTooltip => 'Schließen';

  @override
  String get digestPrepromptMessage =>
      'Möchtest du eine tägliche Zusammenfassung deiner fälligen Aufgaben?';

  @override
  String get digestPrepromptEnableAction => 'Aktivieren';

  @override
  String get digestPrepromptDismissAction => 'Nicht jetzt';

  @override
  String get choresSnackbarDone => 'Erledigt';

  @override
  String choresSnackbarDoneNextDue(String dueText) {
    return 'Erledigt — nächste Fälligkeit $dueText';
  }

  @override
  String get choresSnackbarSkipped => 'Übersprungen';

  @override
  String choresSnackbarSkippedNextDue(String dueText) {
    return 'Übersprungen — nächste Fälligkeit $dueText';
  }

  @override
  String get choresSnackbarUndo => 'Rückgängig';

  @override
  String get choresSnackbarPaused => 'Pausiert';

  @override
  String choresDoneHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Heute erledigt ($count)',
      one: 'Heute erledigt (1)',
    );
    return '$_temp0';
  }

  @override
  String get choresDoneStatusDone => 'Erledigt';

  @override
  String get choresDoneStatusSkipped => 'Übersprungen';

  @override
  String choresDoneClosedByLabel(String name) {
    return 'von $name';
  }

  @override
  String get choresDoneReopen => 'Wieder öffnen';

  @override
  String choresPausedHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pausiert ($count)',
      one: 'Pausiert (1)',
    );
    return '$_temp0';
  }

  @override
  String get choresPausedBadge => 'Pausiert';

  @override
  String get choresPausedResume => 'Fortsetzen';

  @override
  String get choreFormEditTitle => 'Aufgabe bearbeiten';

  @override
  String get choreFormNewTitle => 'Neue Aufgabe';

  @override
  String get choreFormTitleLabel => 'Titel';

  @override
  String get choreFormNotesLabel => 'Notizen';

  @override
  String get choreFormTitleRequiredError => 'Titel ist erforderlich';

  @override
  String get choreFormDiscardDialogTitle => 'Änderungen verwerfen?';

  @override
  String get choreFormDiscardDialogBody =>
      'Deine Änderungen an dieser Aufgabe werden nicht gespeichert.';

  @override
  String get choreFormDiscardKeepEditing => 'Weiter bearbeiten';

  @override
  String get choreFormDiscardConfirm => 'Verwerfen';

  @override
  String get choreFormRepeatToggleLabel => 'Wiederholen';

  @override
  String get choreFormRepeatEveryLabel => 'Wiederholen alle';

  @override
  String get choreFormIntervalTooSmallError => 'Muss mindestens 1 sein';

  @override
  String get choreFormUnitDay => 'Tag';

  @override
  String get choreFormUnitWeek => 'Woche';

  @override
  String get choreFormUnitMonth => 'Monat';

  @override
  String choreFormUnitDayPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tage',
      one: 'Tag',
    );
    return '$_temp0';
  }

  @override
  String choreFormUnitWeekPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wochen',
      one: 'Woche',
    );
    return '$_temp0';
  }

  @override
  String choreFormUnitMonthPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Monate',
      one: 'Monat',
    );
    return '$_temp0';
  }

  @override
  String get choreFormAnchorScheduleTitle => 'An festen Tagen';

  @override
  String get choreFormAnchorCompletionTitle => 'Nach letzter Erledigung';

  @override
  String get choreFormAnchorScheduleSubtitle => 'z. B. jeden Dienstag';

  @override
  String choreFormAnchorScheduleSubtitleDay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Tage',
      one: 'Jeden Tag',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorScheduleSubtitleWeek(int count, String weekdays) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Wochen am $weekdays',
      one: 'Jede Woche am $weekdays',
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
      other: 'Alle $count Monate am $ordinalDay',
      one: 'Jeden Monat am $ordinalDay',
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
      other: 'Alle $count Monate am $ordinal $weekday',
      one: 'Jeden Monat am $ordinal $weekday',
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
      other: 'Alle $count Monate am letzten $weekday',
      one: 'Jeden Monat am letzten $weekday',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorCompletionSubtitleDay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage nach der letzten Erledigung',
      one: '1 Tag nach der letzten Erledigung',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorCompletionSubtitleWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wochen nach der letzten Erledigung',
      one: '1 Woche nach der letzten Erledigung',
    );
    return '$_temp0';
  }

  @override
  String choreFormAnchorCompletionSubtitleMonth(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Monate nach der letzten Erledigung',
      one: '1 Monat nach der letzten Erledigung',
    );
    return '$_temp0';
  }

  @override
  String monthlyDayOfMonthLabel(String ordinalDay) {
    return 'Am $ordinalDay';
  }

  @override
  String monthlyNthWeekdayLabel(String ordinal, String weekday) {
    return 'Am $ordinal $weekday';
  }

  @override
  String monthlyLastWeekdayLabel(String weekday) {
    return 'Am letzten $weekday';
  }

  @override
  String get choreFormPatternFollowsStartDate =>
      'Richtet sich nach dem Startdatum — ändere das Startdatum, um den Tag zu ändern.';

  @override
  String get choreFormAssignmentFixed => 'Fest';

  @override
  String get choreFormAssignmentRotation => 'Rotation';

  @override
  String get choreFormAssignmentAnyone => 'Beliebig';

  @override
  String choreFormAssigneeOrderLabel(int order, String name) {
    return '$order. $name';
  }

  @override
  String get choreFormAssignmentNeedsOneError => 'Wähle ein Mitglied aus';

  @override
  String get choreFormAssignmentNeedsTwoError => 'Wähle mindestens zwei aus';

  @override
  String get choreFormAddMember => 'Mitglied hinzufügen…';

  @override
  String get choreFormStartDateLabel => 'Startdatum';

  @override
  String get shoppingEmptyState => 'Die Einkaufsliste ist leer';

  @override
  String get shoppingErrorMessage =>
      'Deine Einkaufsliste konnte nicht geladen werden.';

  @override
  String get shoppingDeletedSnackbar => 'Entfernt';

  @override
  String get shoppingDeletedUndo => 'Rückgängig';

  @override
  String get shoppingEditNameLabel => 'Name';

  @override
  String get shoppingEditQuantityLabel => 'Menge / Notiz';

  @override
  String get shoppingEditNameRequiredError => 'Name ist erforderlich';

  @override
  String get shoppingUncategorized => 'Ohne Kategorie';

  @override
  String shoppingCartHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Im Einkaufswagen ($count)',
      one: 'Im Einkaufswagen (1)',
    );
    return '$_temp0';
  }

  @override
  String get shoppingClearButton => 'Erledigte leeren';

  @override
  String get shoppingUncheckAll => 'Alles zurücklegen';

  @override
  String shoppingClearedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel entfernt',
      one: '1 Artikel entfernt',
    );
    return '$_temp0';
  }

  @override
  String get shoppingClearedUndo => 'Rückgängig';

  @override
  String get shoppingAddHint => 'Artikel hinzufügen…';

  @override
  String get shoppingAddTooltip => 'Artikel hinzufügen';

  @override
  String get shoppingAddAlreadyOnList => 'Schon auf der Liste';

  @override
  String get shoppingAddMovedBack => 'Zurück auf die Liste verschoben';

  @override
  String get settingsDigestSectionTitle => 'Tägliche Zusammenfassung';

  @override
  String get settingsDigestToggleTitle => 'Tägliche Zusammenfassung';

  @override
  String get settingsDigestTimeLabel => 'Benachrichtigungszeit';

  @override
  String get settingsDigestPermissionHint =>
      'Erlaube Benachrichtigungen in den Systemeinstellungen.';

  @override
  String get settingsDigestPermissionAction => 'Einstellungen öffnen';

  @override
  String get settingsExportEntry => 'Daten exportieren';

  @override
  String get settingsExportError =>
      'Deine Daten konnten nicht exportiert werden. Versuch es noch mal.';

  @override
  String get settingsHouseholdSectionTitle => 'Haushalt';

  @override
  String get settingsMembersEntry => 'Mitglieder';

  @override
  String get settingsMembersInviteEntry => 'Einladen';

  @override
  String get settingsMembersInviteSheetTitle => 'Haushaltsmitglied einladen';

  @override
  String get settingsMembersInviteSheetBody =>
      'Teile diesen Code — er ersetzt jeden früheren Code und ist 7 Tage gültig.';

  @override
  String get settingsMembersInviteShare => 'Teilen';

  @override
  String settingsMembersInviteShareText(String code) {
    return 'Tritt meinem Haushalt auf Famdo bei — gib beim Anmelden den Code $code ein.';
  }

  @override
  String get settingsMembersInviteError =>
      'Die Einladung konnte nicht erstellt werden. Versuch es noch mal.';

  @override
  String get manageMembersTitle => 'Mitglieder';

  @override
  String get manageMembersErrorMessage =>
      'Deine Mitglieder konnten nicht geladen werden.';

  @override
  String get manageMembersHouseholdSubtitle => 'Haushaltsname';

  @override
  String get memberEditNewTitle => 'Neues Mitglied';

  @override
  String get memberEditEditTitle => 'Mitglied bearbeiten';

  @override
  String get memberEditNameLabel => 'Name';

  @override
  String get memberEditColorLabel => 'Farbe';

  @override
  String get memberEditDeleteBlockedClaimed =>
      'Dieses Profil ist mit einem Konto verknüpft und kann hier nicht entfernt werden.';

  @override
  String get memberEditDeleteBlockedLastMember =>
      'Ein Haushalt braucht mindestens ein Mitglied, deshalb kann dieses nicht entfernt werden.';

  @override
  String memberDeleteDialogTitle(String memberName) {
    return '$memberName löschen?';
  }

  @override
  String memberDeleteDialogBody(String memberName) {
    return 'Damit entfernst du $memberName aus dem Haushalt. Bei Aufgaben im Wechsel fällt $memberName aus der Reihenfolge — wenn zu wenige Personen übrig bleiben, wird die Aufgabe auf eine feste Person oder \"jeden\" umgestellt. Aufgaben, die fest $memberName zugewiesen sind, stehen danach allen offen, und alles, was $memberName gerade zugewiesen ist, wird nicht mehr zugewiesen. Der bisherige Verlauf — wer was erledigt hat — bleibt unverändert.';
  }

  @override
  String get householdRenameTitle => 'Haushalt umbenennen';

  @override
  String get householdRenameNameLabel => 'Name';

  @override
  String get settingsCategoriesEntry => 'Kategorien';

  @override
  String get manageCategoriesTitle => 'Kategorien verwalten';

  @override
  String get manageCategoriesKindChore => 'Aufgaben';

  @override
  String get manageCategoriesKindShopping => 'Einkaufsliste';

  @override
  String get manageCategoriesEmptyState => 'Noch keine Kategorien';

  @override
  String get manageCategoriesErrorMessage =>
      'Deine Kategorien konnten nicht geladen werden.';

  @override
  String get categoryEditNewTitle => 'Neue Kategorie';

  @override
  String get categoryEditEditTitle => 'Kategorie bearbeiten';

  @override
  String get categoryEditNameLabel => 'Name';

  @override
  String get categoryEditNameRequiredError => 'Name ist erforderlich';

  @override
  String get categoryEditIconLabel => 'Symbol';

  @override
  String get categoryEditColorLabel => 'Farbe';

  @override
  String get categoryDeleteDialogTitle => 'Kategorie löschen?';

  @override
  String categoryDeleteDialogBody(String categoryName) {
    return 'Damit löschst du \'$categoryName\'. Aufgaben und Artikel mit dieser Kategorie verlieren sie.';
  }

  @override
  String get settingsPreferencesSectionTitle => 'Präferenzen';

  @override
  String get settingsLanguageEntry => 'Sprache';

  @override
  String get settingsLanguageSheetTitle => 'Sprache wählen';

  @override
  String get settingsLanguageSystem => 'Systemsprache';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageDeutsch => 'Deutsch';

  @override
  String get settingsAppearanceEntry => 'Erscheinungsbild';

  @override
  String get settingsAppearanceSheetTitle => 'Erscheinungsbild';

  @override
  String get settingsAppearanceSystem => 'System';

  @override
  String get settingsAppearanceLight => 'Hell';

  @override
  String get settingsAppearanceDark => 'Dunkel';

  @override
  String get settingsAccountIntro =>
      'Melde dich an, um deinen Haushalt geräteübergreifend zu synchronisieren.';

  @override
  String get settingsAccountEmailLabel => 'E-Mail-Adresse';

  @override
  String get settingsAccountSendLink => 'Anmeldelink senden';

  @override
  String get settingsAccountSendAgain => 'Erneut senden';

  @override
  String settingsAccountCheckEmail(String email) {
    return 'Sieh in deinem Postfach unter $email nach deinem Anmeldelink.';
  }

  @override
  String settingsAccountSignedOutLinked(String householdName) {
    return 'Dieses Gerät ist mit $householdName verbunden — melde dich an, um weiter zu synchronisieren.';
  }

  @override
  String settingsAccountPausedNotice(String householdName) {
    return 'Dieses Gerät ist weiterhin mit $householdName verbunden, aber die Synchronisierung ist pausiert. Änderungen, die du jetzt vornimmst, werden gesendet, sobald du dich wieder anmeldest.';
  }

  @override
  String get settingsAccountDisconnect =>
      'Verbindung zum Online-Haushalt trennen';

  @override
  String get settingsAccountDisconnectConfirmTitle =>
      'Verbindung zum Online-Haushalt trennen?';

  @override
  String get settingsAccountDisconnectConfirmBody =>
      'Der Haushalt bleibt genau so auf diesem Gerät erhalten. Andere Mitglieder behalten ihren Haushalt, und nirgendwo wird etwas gelöscht.';

  @override
  String get settingsAccountDisconnectConfirmAction => 'Trennen';

  @override
  String get settingsAccountSendError =>
      'Der Anmeldelink konnte nicht gesendet werden. Versuch es noch mal.';

  @override
  String get settingsAccountSignOut => 'Abmelden';

  @override
  String get settingsAccountSignOutConfirmTitle => 'Abmelden?';

  @override
  String get settingsAccountSignOutConfirmBody =>
      'Die Synchronisierung pausiert, bis du dich wieder anmeldest. Dein Haushalt bleibt auf diesem Gerät, und Änderungen, die du in der Zwischenzeit vornimmst, werden gespeichert und beim nächsten Anmelden gesendet.';

  @override
  String get settingsAccountSignOutConfirmAction => 'Abmelden';

  @override
  String get syncRefreshError =>
      'Haushalt nicht erreichbar. Deine Änderungen sind hier gespeichert und werden später synchronisiert.';

  @override
  String get settingsAccountSignOutError =>
      'Abmelden hat nicht geklappt. Versuch es noch mal.';

  @override
  String get settingsAccountComingSoonTitle =>
      'Synchronisierung — bald verfügbar';

  @override
  String settingsAccountReconnectTitle(String householdName) {
    return 'Mit $householdName neu verbinden';
  }

  @override
  String get settingsAccountReconnectIntro =>
      'Ersetzt deine lokalen Daten — sie werden in einer Sicherungsdatei auf diesem Gerät gespeichert.';

  @override
  String get settingsAccountAdoptTitle => 'Meinen Haushalt online stellen';

  @override
  String get settingsAccountAdoptIntro =>
      'Macht deinen Haushalt auf deinen anderen Geräten verfügbar.';

  @override
  String get settingsAccountAdoptRetry => 'Erneut versuchen';

  @override
  String get settingsAccountAdoptError =>
      'Dein Haushalt konnte nicht online gestellt werden. Versuch es noch mal.';

  @override
  String settingsAccountLinkedSubtitle(String householdName) {
    return 'Synchronisiert mit $householdName';
  }

  @override
  String get settingsAccountLastSyncedJustNow =>
      'Zuletzt synchronisiert: gerade eben';

  @override
  String settingsAccountLastSyncedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zuletzt synchronisiert: vor $count Minuten',
      one: 'Zuletzt synchronisiert: vor 1 Minute',
    );
    return '$_temp0';
  }

  @override
  String settingsAccountLastSyncedHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zuletzt synchronisiert: vor $count Stunden',
      one: 'Zuletzt synchronisiert: vor 1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String settingsAccountLastSyncedOn(String date) {
    return 'Zuletzt synchronisiert: $date';
  }

  @override
  String get settingsAccountInvite => 'Mitglied einladen';

  @override
  String get settingsAccountJoinTitle => 'Einem bestehenden Haushalt beitreten';

  @override
  String get settingsAccountJoinIntro =>
      'Nutze einen Einladungscode von einem anderen Gerät — das ersetzt deine lokalen Daten.';

  @override
  String settingsAccountJoinSuccessSnackbar(String fileName) {
    return 'Deine alten Daten wurden in $fileName gespeichert.';
  }

  @override
  String get joinHouseholdCodeTitle => 'Gib deinen Einladungscode ein';

  @override
  String get joinHouseholdCodeBody =>
      'Frag ein Haushaltsmitglied nach dem Code aus seinem Mitglieder-Bildschirm.';

  @override
  String get joinHouseholdCodeLabel => 'Einladungscode';

  @override
  String get joinHouseholdCodeError =>
      'Der Code funktioniert nicht. Prüf ihn auf Tippfehler oder lass dir einen neuen schicken.';

  @override
  String get joinHouseholdCodeUnknownError =>
      'Der Code konnte nicht geprüft werden. Prüf deine Verbindung und versuch es noch mal.';

  @override
  String get joinHouseholdContinue => 'Weiter';

  @override
  String get joinHouseholdChooserTitle => 'Welches Profil gehört dir?';

  @override
  String joinHouseholdChooserAreYou(String name) {
    return 'Bist du $name?';
  }

  @override
  String get joinHouseholdChooserNewMember => 'Ich bin neu hier';

  @override
  String get joinHouseholdNewMemberTitle => 'Wie heißt du?';

  @override
  String get joinHouseholdNewMemberNameLabel => 'Name';

  @override
  String get joinHouseholdImportTitle => 'Deine offenen Aufgaben mitnehmen?';

  @override
  String get joinHouseholdImportBody =>
      'Deine offenen Aufgaben und nicht abgehakten Einkaufsartikel können als neue Einträge mitkommen — ohne ihren Verlauf. Alles andere wird ersetzt: dein bisheriger Haushalt wird in einer Sicherungsdatei auf diesem Gerät gespeichert.';

  @override
  String get joinHouseholdImportAccept => 'Mitnehmen';

  @override
  String get joinHouseholdImportDecline => 'Neu anfangen';

  @override
  String get joinHouseholdWorkingError =>
      'Beim Beitreten ist etwas schiefgelaufen. Versuch es noch mal.';

  @override
  String get settingsAboutSectionTitle => 'Über die App';

  @override
  String settingsAboutVersionLabel(String version, String buildNumber) {
    return 'Version $version ($buildNumber)';
  }

  @override
  String get settingsAboutLicensesEntry => 'Open-Source-Lizenzen';

  @override
  String get settingsAboutDonateTitle => 'Unterstütze die App';

  @override
  String get settingsAboutDonateSubtitle => 'Ko-fi oder PayPal — danke dir!';

  @override
  String get settingsAboutDonateSheetTitle => 'Unterstütze Famdo';

  @override
  String get settingsAboutDonateKofiLabel => 'Ko-fi';

  @override
  String get settingsAboutDonatePaypalLabel => 'PayPal';

  @override
  String get settingsDataSectionTitle => 'Daten';

  @override
  String get settingsResetEntry => 'App-Daten zurücksetzen';

  @override
  String get settingsResetConfirm1Title => 'App-Daten zurücksetzen?';

  @override
  String get settingsResetConfirm1Body =>
      'Damit löschst du deinen Haushalt, alle Mitglieder, Aufgaben und die Einkaufsliste endgültig. Es gibt keine Cloud-Sicherung – das lässt sich nicht rückgängig machen.';

  @override
  String get settingsResetConfirm1BodyLinked =>
      'Dein Haushalt bleibt online — dieses Gerät trennt sich nur davon. Du kannst dich einfach wieder anmelden, um die Verbindung wiederherzustellen. Das löscht trotzdem endgültig die Mitglieder, Aufgaben und die Einkaufsliste auf diesem Gerät.';

  @override
  String get settingsResetConfirm1Action => 'Weiter';

  @override
  String get settingsResetConfirm2Title => 'Wirklich alles löschen?';

  @override
  String get settingsResetConfirm2Body =>
      'Das ist der letzte Schritt. Sobald du bestätigst, ist sofort alles weg.';

  @override
  String get settingsResetConfirm2Action => 'Alles löschen';

  @override
  String get exitConfirmDeleteLocalLabel =>
      'Kopie auf diesem Gerät auch löschen';

  @override
  String get exitConfirmDeleteLocalExplanation =>
      'Aus: Der Haushalt bleibt als deine eigene lokale Kopie auf diesem Gerät. An: Mitglieder, Aufgaben und Einkaufsliste auf diesem Gerät werden gelöscht und die App startet neu.';

  @override
  String get exitConfirmCancel => 'Abbrechen';
}
