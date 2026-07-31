import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/chore_occurrence_tile.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the A1 tile redesign (see
/// `docs/specs/ux-round-2.md`): avatar + first name when assigned, nothing
/// extra when unassigned, note line only when a note exists, and the
/// overdue due text in the theme's error color. The relative/locale-date
/// due-text branches themselves are exhaustively covered, faster, by
/// `test/features/chores/due_text_test.dart`; this file confirms the
/// redesigned tile actually wires that logic up end to end.
void main() {
  final today = DateTime(2026, 7, 22, 9);

  testChoreApp(
    'assigned occurrence shows an avatar and first name; unassigned shows '
    'neither',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final meMember = await database.select(database.members).getSingle();
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      await service.createChore(
        householdId: householdId,
        title: 'Assigned chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.fixed,
        assigneeMemberIds: [meMember.id],
      );
      await service.createChore(
        householdId: householdId,
        title: 'Unassigned chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );

      await tester.pumpAndSettle();

      // The bootstrap member is named 'Me'; its first (and only) name
      // token shows next to a single avatar circle. Scoped to the tiles:
      // the app bar's acting-member button is a CircleAvatar too.
      expect(find.text('Me'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChoreOccurrenceTile),
          matching: find.byType(CircleAvatar),
        ),
        findsOneWidget,
      );
    },
  );

  testChoreApp(
    'the note line appears only for a chore that has a note',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      await service.createChore(
        householdId: householdId,
        title: 'Noted chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
        notes: 'Use the blue filters',
      );
      await service.createChore(
        householdId: householdId,
        title: 'Plain chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );

      await tester.pumpAndSettle();

      expect(find.text('Use the blue filters'), findsOneWidget);
      expect(find.byIcon(Icons.notes_outlined), findsOneWidget);
    },
  );

  testChoreApp(
    'an overdue tile shows "Overdue · N days" in the error color',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      await service.createChore(
        householdId: householdId,
        title: 'Overdue chore',
        startDate: PlainDate(2026, 7, 19), // 3 days before `today`.
        assignmentMode: AssignmentMode.anyone,
      );

      await tester.pumpAndSettle();

      final dueText = tester.widget<Text>(find.text('Overdue · 3 days'));
      final context = tester.element(find.text('Overdue · 3 days'));
      expect(
        dueText.style?.color,
        Theme.of(context).colorScheme.error,
      );
    },
  );
}
