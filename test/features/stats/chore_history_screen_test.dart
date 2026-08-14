import 'dart:async';

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/stats/chore_history_screen.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Seeds one chore and [count] `done` occurrences of it, closed on
/// consecutive days ending on [lastClosedOn].
Future<String> _seedChoreWithHistory(
  AppDatabase database, {
  required String title,
  required int count,
  required PlainDate lastClosedOn,
  bool deleted = false,
}) async {
  final householdId = await currentHouseholdId(database);
  final member = await (database.select(
    database.members,
  )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  const choreId = 'chore-history-test';
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
  for (var i = 0; i < count; i++) {
    final closedOn = lastClosedOn.addDays(-i);
    await database
        .into(database.choreOccurrences)
        .insert(
          ChoreOccurrencesCompanion.insert(
            id: 'occ-$i',
            choreId: choreId,
            dueDate: closedOn,
            status: const Value(OccurrenceStatus.done),
            completedBy: Value(member.id),
            closedOn: Value(closedOn),
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        );
  }
  return choreId;
}

Future<void> _openHistory(WidgetTester tester, String choreId) async {
  final context = tester.element(find.byType(Navigator).first);
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChoreHistoryScreen(choreId: choreId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime(2026, 8, 11, 9);

  testChoreApp(
    'a chore log lists its completions newest first with the total',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await _seedChoreWithHistory(
        database,
        title: 'Bathroom',
        count: 3,
        lastClosedOn: PlainDate(2026, 8, 10),
      );

      await _openHistory(tester, choreId);

      expect(find.text('Bathroom'), findsOneWidget);
      expect(find.text('3 chores done'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('stats.history.row.occ-0'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('stats.history.truncated'),
        findsNothing,
      );

      // occ-0 is the newest (closed 2026-08-10), occ-2 the oldest: the log
      // is newest-first, so the newest row must sit above the oldest.
      final newest = tester
          .getTopLeft(find.bySemanticsIdentifier('stats.history.row.occ-0'))
          .dy;
      final oldest = tester
          .getTopLeft(find.bySemanticsIdentifier('stats.history.row.occ-2'))
          .dy;
      expect(newest, lessThan(oldest));

      handle.dispose();
    },
  );

  testChoreApp(
    'a deleted chore still shows its history, with the deleted notice',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await _seedChoreWithHistory(
        database,
        title: 'Attic',
        count: 2,
        lastClosedOn: PlainDate(2026, 8, 1),
        deleted: true,
      );

      await _openHistory(tester, choreId);

      expect(
        find.bySemanticsIdentifier('stats.history.deletedNotice'),
        findsOneWidget,
      );
      expect(find.text('2 chores done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'more completions than the cap shows the truncation line',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await _seedChoreWithHistory(
        database,
        title: 'Dishes',
        count: 52,
        lastClosedOn: PlainDate(2026, 8, 10),
      );

      await _openHistory(tester, choreId);

      expect(find.text('52 chores done'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('stats.history.truncated'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
