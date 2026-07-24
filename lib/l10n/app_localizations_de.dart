// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Aufgaben';

  @override
  String appBootstrapError(Object error) {
    return 'Beim Start ist etwas schiefgelaufen: $error';
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
  String settingsComingSoon(String title) {
    return '$title — kommt bald';
  }

  @override
  String get categoryPickerNone => 'Keine';

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
    return 'Damit löschst du \'$choreTitle\'. Der Verlauf bleibt erhalten, aber die anstehende Erledigung wird entfernt.';
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
  String get choresEmptyState => 'Keine Aufgaben offen — gut gemacht!';

  @override
  String get choresErrorMessage =>
      'Deine Aufgaben konnten nicht geladen werden.';

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
  String get choreFormAnchorScheduleTitle => 'Nach festem Zeitplan';

  @override
  String get choreFormAnchorCompletionTitle => 'Nach letzter Erledigung';

  @override
  String get choreFormAnchorScheduleSubtitle => 'z. B. jeden Dienstag';

  @override
  String get choreFormAnchorCompletionSubtitle =>
      'z. B. 4 Tage nach der letzten Erledigung';

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
  String get choreFormStartDateLabel => 'Startdatum';

  @override
  String get shoppingEmptyState => 'Die Einkaufsliste ist leer';

  @override
  String get shoppingErrorMessage =>
      'Deine Einkaufsliste konnte nicht geladen werden.';

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
  String get shoppingAddHint => 'Artikel hinzufügen…';

  @override
  String get shoppingAddTooltip => 'Artikel hinzufügen';

  @override
  String get shoppingAddAlreadyOnList => 'Schon auf der Liste';

  @override
  String get shoppingAddMovedBack => 'Zurück auf die Liste verschoben';
}
