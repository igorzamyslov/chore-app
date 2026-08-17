import 'package:chore_app/app/famdo_colors.dart';
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
      expect(dueText.style?.color, Theme.of(context).colorScheme.error);
    },
  );

  testChoreApp(
    'overdue tile treatment (design option C, spec docs/specs/theme-v2.md '
    '§4.1 item 4): errorContainer ground, errorOutline border, a 3dp error '
    'left edge, and the due chip in errorChip -- a same-day tile stays on '
    'the default surface with no left edge',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      final overdueChore = await service.createChore(
        householdId: householdId,
        title: 'Overdue chore',
        startDate: PlainDate(2026, 7, 19), // 3 days before `today`.
        assignmentMode: AssignmentMode.anyone,
      );
      final todayChore = await service.createChore(
        householdId: householdId,
        title: 'Today chore',
        startDate: PlainDate(2026, 7, 22),
        assignmentMode: AssignmentMode.anyone,
      );

      await tester.pumpAndSettle();

      final context = tester.element(find.text('Overdue chore'));
      final colorScheme = Theme.of(context).colorScheme;
      final famdo = famdoColors(context);
      final overdueTileId = 'chores.occurrence.${overdueChore.id}';
      final todayTileId = 'chores.occurrence.${todayChore.id}';

      // The overdue tile's card: errorContainer ground, errorOutline border.
      final overdueCard = tester.widget<Card>(
        find.ancestor(
          of: find.bySemanticsIdentifier(overdueTileId),
          matching: find.byType(Card),
        ),
      );
      expect(overdueCard.color, colorScheme.errorContainer);
      final overdueShape = overdueCard.shape! as RoundedRectangleBorder;
      expect(overdueShape.side.color, famdo.errorOutline);

      // A 3dp error-colored left edge is present.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(overdueTileId),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.color == colorScheme.error &&
                widget.constraints?.minWidth == 3 &&
                widget.constraints?.maxWidth == 3,
          ),
        ),
        findsOneWidget,
      );

      // The due chip's ground is errorChip (its ink color is already
      // covered by the sibling test above).
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(overdueTileId),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color == famdo.errorChip,
          ),
        ),
        findsOneWidget,
      );

      // A same-day tile stays on the default surface: no error tint, no
      // left edge.
      final todayCard = tester.widget<Card>(
        find.ancestor(
          of: find.bySemanticsIdentifier(todayTileId),
          matching: find.byType(Card),
        ),
      );
      expect(todayCard.color, colorScheme.surfaceContainerLow);
      final todayShape = todayCard.shape! as RoundedRectangleBorder;
      expect(todayShape.side.color, colorScheme.outlineVariant);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(todayTileId),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.color == colorScheme.error,
          ),
        ),
        findsNothing,
      );
    },
  );
}
