/// Persona review 2026-10-06 E10 (chores half): the "waiting to send" clock
/// on a dirty occurrence row while the household is linked, the same 14 dp
/// glyph and tooltip the shopping rows use.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// A linked, signed-in stand-in: anything that is not [NoopSyncEngine] makes
/// the screens treat the household as linked (`syncEngineProvider`'s own
/// contract), without any network or timer.
class _LinkedEngine implements SyncEngine {
  @override
  Future<void> pushDirty() async {}

  @override
  Future<void> pullSince() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<RefreshOutcome> refreshNow() async => RefreshOutcome.ok;

  @override
  void pauseBackgroundWork() {}

  @override
  void resumeBackgroundWork() {}
}

Override get _linked => syncEngineProvider.overrideWithValue(_LinkedEngine());

void main() {
  final today = DateTime(2026, 7, 24, 9);

  Future<ChoreOccurrence> addChore(
    AppDatabase database,
    String title, {
    required bool dirty,
  }) async {
    final householdId = await currentHouseholdId(database);
    final repo = ChoreRepository(database);
    final chore =
        await ChoreService(
          database: database,
          chores: repo,
          clock: Clock.fixed(today),
        ).createChore(
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 7, 24),
          assignmentMode: AssignmentMode.anyone,
        );
    final occurrence = (await repo.pendingOccurrenceOf(chore.id))!;
    await (database.update(
      database.choreOccurrences,
    )..where((tbl) => tbl.id.equals(occurrence.id))).write(
      ChoreOccurrencesCompanion(syncDirty: Value(dirty)),
    );
    return occurrence;
  }

  testChoreApp(
    'linked: a dirty occurrence tile shows the 14 dp clock with a tooltip; '
    'a clean one does not',
    today: today,
    overrides: [_linked],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final dirtyOccurrence = await addChore(database, 'Dirty', dirty: true);
      final cleanOccurrence = await addChore(database, 'Clean', dirty: false);
      await tester.pumpAndSettle();

      Finder glyphIn(ChoreOccurrence occurrence) => find.descendant(
        of: find.ancestor(
          of: find.text(occurrence == dirtyOccurrence ? 'Dirty' : 'Clean'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(Icons.schedule),
      );

      expect(glyphIn(dirtyOccurrence), findsOneWidget);
      expect(glyphIn(cleanOccurrence), findsNothing);
      expect(find.byTooltip('Waiting to send'), findsOneWidget);
      expect(tester.getSize(glyphIn(dirtyOccurrence)), const Size(14, 14));

      handle.dispose();
    },
  );

  testChoreApp(
    'unlinked: a dirty occurrence tile shows no clock (nothing is ever sent)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await addChore(database, 'Dirty', dirty: true);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.schedule), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'linked: a dirty done row shows the clock too, so "did they see it" has '
    'an answer',
    today: today,
    overrides: [_linked],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await database.select(database.members).getSingle();
      final occurrence = await addChore(database, 'Ticked', dirty: false);
      await ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      ).completeOccurrence(occurrence.id, completedBy: me.id);
      await (database.update(
        database.choreOccurrences,
      )..where((tbl) => tbl.id.equals(occurrence.id))).write(
        const ChoreOccurrencesCompanion(syncDirty: Value(true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Ticked'),
            matching: find.byType(ListTile),
          ),
          matching: find.byIcon(Icons.schedule),
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
