import 'package:chore_app/app/theme.dart';
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/stats/stats_share_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/settings_test_utils.dart';

Member _member(String id, String name) => Member(
  id: id,
  householdId: 'hh',
  name: name,
  color: 0xFF6D9F71,
  role: MemberRole.member,
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
  syncDirty: false,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required List<MemberShare> shares,
  required int totalDone,
  required bool clamped,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appLightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatsShareCard(
          shares: shares,
          totalDone: totalDone,
          windowStart: PlainDate(2026, 8, 9),
          clampedToHouseholdStart: clamped,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Seeds one chore with exactly one `done` occurrence closed on [closedOn],
/// credited to the bootstrap member. Returns the chore id.
///
/// Also backdates the household's `created_at`. `testChoreApp` seeds the
/// household through `HouseholdRepository`'s DEFAULT `nowUtc`, i.e. the real
/// wall clock, while the app under test runs on a clock fixed in 2026 -- so
/// on any machine whose real date is later than the fixed clock, the
/// household would look younger than the chore completions it supposedly
/// recorded. That is incoherent data, not a scenario worth testing: the
/// share window would clamp to the household's start and count nothing.
Future<String> seedDoneChore(
  AppDatabase database, {
  required String title,
  required String closedOn,
  bool deleted = false,
}) async {
  final householdId = await currentHouseholdId(database);
  await (database.update(
    database.households,
  )..where((tbl) => tbl.id.equals(householdId))).write(
    const HouseholdsCompanion(createdAt: Value('2026-01-01T00:00:00.000Z')),
  );
  final member = await (database.select(
    database.members,
  )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  final choreId = 'chore-$title';
  await database
      .into(database.chores)
      .insert(
        ChoresCompanion.insert(
          id: choreId,
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deleted ? '2026-08-10T00:00:00.000Z' : null),
        ),
      );
  await database
      .into(database.choreOccurrences)
      .insert(
        ChoreOccurrencesCompanion.insert(
          id: 'occ-$title',
          choreId: choreId,
          dueDate: PlainDate.parse(closedOn),
          status: const Value(OccurrenceStatus.done),
          completedBy: Value(member.id),
          closedOn: Value(PlainDate.parse(closedOn)),
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  return choreId;
}

void main() {
  testWidgets(
    'share card names the window, the total, and every entry including a zero',
    (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpCard(
        tester,
        shares: [
          MemberShare(member: _member('anna', 'Anna'), doneCount: 3),
          MemberShare(member: _member('ben', 'Ben'), doneCount: 0),
        ],
        totalDone: 3,
        clamped: false,
      );

      expect(find.bySemanticsIdentifier('stats.share'), findsOneWidget);
      expect(find.text('In the last 30 days'), findsOneWidget);
      expect(find.text('3 chores done'), findsOneWidget);
      expect(find.text('Anna'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);

      handle.dispose();
    },
  );

  testWidgets('a clamped window says "since you started" instead', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      shares: [
        MemberShare(member: _member('anna', 'Anna'), doneCount: 1),
        MemberShare(member: _member('ben', 'Ben'), doneCount: 1),
      ],
      totalDone: 2,
      clamped: true,
    );

    expect(find.text('In the last 30 days'), findsNothing);
    expect(find.textContaining('Since you started'), findsOneWidget);
  });

  testWidgets('the unattributed bucket renders as "Someone else"', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      shares: [
        MemberShare(member: _member('anna', 'Anna'), doneCount: 1),
        const MemberShare(member: null, doneCount: 1),
      ],
      totalDone: 2,
      clamped: false,
    );

    expect(find.text('Someone else'), findsOneWidget);
  });

  testWidgets(
    'the share card renders entries in the order given and never re-sorts '
    'them by count -- the anti-leaderboard rule (spec §0 rule 2)',
    (tester) async {
      // Roster order here is Anna(1), Ben(5), Cara(2): deliberately NOT
      // count-descending, which would read Ben, Cara, Anna. Asserting on the
      // vertical positions catches a re-sort inside the widget even though
      // the service is what guarantees the incoming order.
      await _pumpCard(
        tester,
        shares: [
          MemberShare(member: _member('anna', 'Anna'), doneCount: 1),
          MemberShare(member: _member('ben', 'Ben'), doneCount: 5),
          MemberShare(member: _member('cara', 'Cara'), doneCount: 2),
        ],
        totalDone: 8,
        clamped: false,
      );

      final anna = tester.getTopLeft(find.text('Anna')).dy;
      final ben = tester.getTopLeft(find.text('Ben')).dy;
      final cara = tester.getTopLeft(find.text('Cara')).dy;

      expect(anna, lessThan(ben));
      expect(ben, lessThan(cara));
    },
  );

  testChoreApp(
    'a household with no completions shows the teaching empty state',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openChoreHistory(tester);

      expect(find.bySemanticsIdentifier('stats.empty'), findsOneWidget);
      expect(find.text('No completed chores yet'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.share'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a single-member household gets the total line, not the share card',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedDoneChore(database, title: 'Bathroom', closedOn: '2026-08-10');

      await openChoreHistory(tester);

      expect(find.bySemanticsIdentifier('stats.total'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.share'), findsNothing);
      expect(find.text('1 chore done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a chore row shows all-time count and last date, and opens the log',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await seedDoneChore(
        database,
        title: 'Bathroom',
        closedOn: '2026-08-10',
      );

      await openChoreHistory(tester);
      expect(find.textContaining('Done once'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('stats.chore.$choreId'));
      await tester.pumpAndSettle();
      expect(find.text('1 chore done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a deleted chore with history appears under the deleted section, not '
    'the main list',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await seedDoneChore(
        database,
        title: 'Attic',
        closedOn: '2026-08-01',
        deleted: true,
      );

      await openChoreHistory(tester);

      expect(find.bySemanticsIdentifier('stats.deleted'), findsOneWidget);
      expect(find.text('Deleted chores (1)'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.chore.$choreId'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('stats.deleted'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('stats.chore.$choreId'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'chore-history overview lays out at text scale 2.0 without overflow',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedDoneChore(database, title: 'Bathroom', closedOn: '2026-08-10');

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openChoreHistory(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      handle.dispose();
    },
  );
}
