import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget-level tests for the chores app bar's acting-member button and
/// switcher sheet (spec `docs/specs/members-management.md` §4, §6): the
/// button reflects the current acting member, the sheet checks the right
/// row, switching re-attributes the next unassigned completion, and the
/// choice persists across a simulated app restart.
void main() {
  final today = DateTime(2026, 7, 24, 9);
  final todayPlain = PlainDate(2026, 7, 24);

  Future<Member> soleBootstrapMember(AppDatabase database) async {
    final householdId = await currentHouseholdId(database);
    return (database.select(
      database.members,
    )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  }

  String memberNameIn(WidgetTester tester, Finder buttonOrRow) {
    return tester
        .widget<MemberAvatar>(
          find.descendant(of: buttonOrRow, matching: find.byType(MemberAvatar)),
        )
        .member
        .name;
  }

  testChoreApp(
    "the app bar button shows the acting member's avatar; tapping opens "
    'the sheet listing every member with a check on the current one',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final me = await soleBootstrapMember(database);

      final button = find.bySemanticsIdentifier('chores.actingMember');
      expect(button, findsOneWidget);
      expect(memberNameIn(tester, button), 'Me');

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('actingMember.sheet'), findsOneWidget);
      expect(find.text("Who's doing chores right now?"), findsOneWidget);

      final meRow = find.bySemanticsIdentifier(
        'actingMember.sheet.row.${me.id}',
      );
      expect(meRow, findsOneWidget);
      expect(
        find.descendant(of: meRow, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testChoreApp(
    'switching to a second member via the sheet closes it and the next '
    'completion of an unassigned chore attributes that member',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );
      // "anyone" mode, no assignee — the acting member is the completer
      // for EVERY UI completion (assigned or not; see the fixed-assignee
      // sibling test below), this test covers the unassigned path.
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.actingMember'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('actingMember.sheet.row.${anna.id}'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('actingMember.sheet'), findsNothing);
      expect(
        memberNameIn(
          tester,
          find.bySemanticsIdentifier('chores.actingMember'),
        ),
        'Anna',
      );

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('chores.done.header'), findsOneWidget);
      expect(find.text('Done today (1)'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      // Scoped to the Done section rather than a bare text lookup: a
      // completion also pops an undo snackbar that may still be on-screen
      // here (see duplicate_names_widget_test.dart's note on this exact
      // pitfall). The snackbar's own text is the bare 'Done' with no
      // 'by <name>' suffix, so there's no literal collision, but scoping
      // keeps the assertion robust regardless.
      expect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text('by Anna'),
        ),
        findsOneWidget,
      );

      final closed = await repo.latestClosedOccurrence(chore.id);
      expect(closed!.completedBy, anna.id);

      handle.dispose();
    },
  );

  testChoreApp(
    'completing a chore FIXED to another member still credits the acting '
    'member — attribution records who actually did the work (user '
    'decision 2026-07-31), while rotation keeps reading the assignee',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final repo = ChoreRepository(database);
      final me = await soleBootstrapMember(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      final service = ChoreService(
        database: database,
        chores: repo,
        clock: Clock.fixed(today),
      );
      // The chore is Me's on paper; Anna is the one acting.
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Water plants',
        startDate: todayPlain,
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [me.id],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.actingMember'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('actingMember.sheet.row.${anna.id}'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.done.header'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text('by Anna'),
        ),
        findsOneWidget,
      );
      final closed = await repo.latestClosedOccurrence(chore.id);
      // Credit: Anna (who did it). Assignment record: still Me — rotation
      // and the assignee field are untouched by who completed.
      expect(closed!.completedBy, anna.id);
      expect(closed.assignedMemberId, me.id);

      handle.dispose();
    },
  );

  testChoreApp(
    'the acting member persists across a simulated app restart (a fresh '
    'ProviderScope pumped over the same database)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final anna = await HouseholdRepository(
        database,
      ).addMember(householdId, name: 'Anna', color: 0xFF8C7BC9);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('chores.actingMember'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('actingMember.sheet.row.${anna.id}'),
      );
      await tester.pumpAndSettle();

      // Simulated restart: pump a brand-new widget tree/ProviderScope over
      // the exact same, still-open in-memory database. appDatabaseProvider
      // is overridden with `overrideWithValue`, which never runs the
      // original provider body's `ref.onDispose(database.close)`, so
      // disposing the first tree (implicit in swapping the pumped widget)
      // does not close the database out from under this second tree.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock.fixed(today)),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        memberNameIn(
          tester,
          find.bySemanticsIdentifier('chores.actingMember'),
        ),
        'Anna',
      );

      handle.dispose();
    },
  );
}
