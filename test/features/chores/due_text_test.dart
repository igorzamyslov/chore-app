// Pure unit tests for the per-tile due-text formatting (see
// `docs/specs/ux-round-2.md` A1): fast and exhaustive, per
// `docs/specs/testing-strategy.md` §1. Loads AppLocalizations directly (no
// widget pump needed) via its generated delegate.
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/chore_occurrence_tile.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations de;

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
    en = await AppLocalizations.delegate.load(const Locale('en'));
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  group('futureDueText', () {
    final today = PlainDate(2026, 7, 22);

    test('today reads "Today"', () {
      expect(futureDueText(en, 'en', today: today, dueDate: today), 'Today');
    });

    test('tomorrow reads "Tomorrow"', () {
      expect(
        futureDueText(en, 'en', today: today, dueDate: today.addDays(1)),
        'Tomorrow',
      );
    });

    test('2 days out reads "In 2 days" (plural)', () {
      expect(
        futureDueText(en, 'en', today: today, dueDate: today.addDays(2)),
        'In 2 days',
      );
    });

    test('the 7-day boundary still reads "In 7 days"', () {
      expect(
        futureDueText(en, 'en', today: today, dueDate: today.addDays(7)),
        'In 7 days',
      );
    });

    test('the 8-day boundary switches to the locale-formatted date, not '
        '"In 8 days"', () {
      final dueDate = today.addDays(8); // 2026-07-30, a Thursday.
      expect(
        futureDueText(en, 'en', today: today, dueDate: dueDate),
        'Thu, Jul 30',
      );
    });

    test('a date far beyond a week uses the locale-formatted weekday+date', () {
      // 2026-07-31 is a Friday: matches the spec's own example verbatim.
      final dueDate = PlainDate(2026, 7, 31);
      expect(
        futureDueText(en, 'en', today: today, dueDate: dueDate),
        'Fri, Jul 31',
      );
    });

    test('German plural: 1 day uses the singular form', () {
      // Not reachable via the day-diff branch (diff == 1 is "tomorrow"),
      // but choresDueInDays itself must still carry a correct ICU plural
      // rule for every locale.
      expect(de.choresDueInDays(1), 'In 1 Tag');
    });

    test('German plural: multiple days uses the plural form', () {
      expect(
        futureDueText(de, 'de', today: today, dueDate: today.addDays(3)),
        'In 3 Tagen',
      );
    });

    test('German locale-formatted date beyond a week', () {
      final dueDate = PlainDate(2026, 7, 31);
      expect(
        futureDueText(de, 'de', today: today, dueDate: dueDate),
        'Fr., 31. Juli',
      );
    });
  });

  group('overdueDueText', () {
    final today = PlainDate(2026, 7, 22);

    test('1 day overdue uses the singular form', () {
      expect(
        overdueDueText(en, today: today, dueDate: today.addDays(-1)),
        'Overdue · 1 day',
      );
    });

    test('multiple days overdue uses the plural form', () {
      expect(
        overdueDueText(en, today: today, dueDate: today.addDays(-3)),
        'Overdue · 3 days',
      );
    });

    test('German: 1 day overdue uses the singular form', () {
      expect(
        overdueDueText(de, today: today, dueDate: today.addDays(-1)),
        'Überfällig · 1 Tag',
      );
    });

    test('German: multiple days overdue uses the plural form', () {
      expect(
        overdueDueText(de, today: today, dueDate: today.addDays(-3)),
        'Überfällig · 3 Tage',
      );
    });
  });
}
