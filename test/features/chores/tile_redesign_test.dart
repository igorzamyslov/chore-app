import 'package:chore_app/app/famdo_colors.dart';
import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/chores/chore_occurrence_tile.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Widget coverage for the A1 tile redesign (see
/// `docs/specs/ux-round-2.md`): avatar + first name when assigned, nothing
/// extra when unassigned, note line only when a note exists, and the
/// status tones (success today, warning under 7 days overdue, error from 7
/// days on). The relative/locale-date
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
      // token shows next to a single avatar. Scoped to the tiles: the app
      // bar's acting-member button is a MemberAvatar too.
      //
      // Asserted on MemberAvatar rather than CircleAvatar since G-4: the
      // avatar is now a ring (a Container with a circular BoxDecoration)
      // and there is no CircleAvatar under the tile at all. The widget
      // TYPE is what this test is about -- the ring's colour and initials
      // are covered by test/features/members/member_avatar_test.dart, in
      // both themes.
      expect(find.text('Me'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChoreOccurrenceTile),
          matching: find.byType(MemberAvatar),
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
    'a tile overdue by 7+ days shows "Overdue · N days" in the error color',
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
        startDate: PlainDate(2026, 7, 12), // 10 days before `today`.
        assignmentMode: AssignmentMode.anyone,
      );

      await tester.pumpAndSettle();

      final dueText = tester.widget<Text>(find.text('Overdue · 10 days'));
      final context = tester.element(find.text('Overdue · 10 days'));
      expect(
        dueText.style?.color,
        Theme.of(context).colorScheme.error,
      );
    },
  );

  testChoreApp(
    'a tile overdue by under 7 days shows "Overdue · N days" in the warning '
    'color',
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
      expect(dueText.style?.color, famdoColors(context).warning);
    },
  );

  testChoreApp(
    'status tile treatment (design option C, spec docs/specs/theme-v2.md '
    '§4.1 item 4): a tone container ground, outline border and 3dp accent '
    'left edge -- error from 7 days overdue, warning below that, success '
    'today -- and a future tile stays on the default surface with no edge',
    today: today,
    (tester, database) async {
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );

      Future<String> tileIdFor(String title, PlainDate startDate) async {
        final chore = await service.createChore(
          householdId: householdId,
          title: title,
          startDate: startDate,
          assignmentMode: AssignmentMode.anyone,
        );
        return 'chores.occurrence.${chore.id}';
      }

      // 7 days before `today` -- exactly on the error threshold.
      final errorTileId = await tileIdFor('Late chore', PlainDate(2026, 7, 15));
      // 6 days before `today` -- the last warning day.
      final warningTileId = await tileIdFor(
        'Slipping chore',
        PlainDate(2026, 7, 16),
      );
      final successTileId = await tileIdFor(
        'Today chore',
        PlainDate(2026, 7, 22),
      );
      final neutralTileId = await tileIdFor(
        'Tomorrow chore',
        PlainDate(2026, 7, 23),
      );

      await tester.pumpAndSettle();

      final context = tester.element(find.text('Today chore'));
      final colorScheme = Theme.of(context).colorScheme;
      final famdo = famdoColors(context);

      Card cardOf(String tileId) => tester.widget<Card>(
        find.ancestor(
          of: find.bySemanticsIdentifier(tileId),
          matching: find.byType(Card),
        ),
      );

      Finder leftEdgeIn(String tileId, Color color) => find.descendant(
        of: find.bySemanticsIdentifier(tileId),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.color == color &&
              widget.constraints?.minWidth == 3 &&
              widget.constraints?.maxWidth == 3,
        ),
      );

      Finder chipIn(String tileId, Color ground) => find.descendant(
        of: find.bySemanticsIdentifier(tileId),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color == ground,
        ),
      );

      void expectToned(
        String tileId, {
        required Color container,
        required Color outline,
        required Color accent,
      }) {
        final card = cardOf(tileId);
        expect(card.color, container);
        expect((card.shape! as RoundedRectangleBorder).side.color, outline);
        expect(leftEdgeIn(tileId, accent), findsOneWidget);
      }

      expectToned(
        errorTileId,
        container: colorScheme.errorContainer,
        outline: famdo.errorOutline,
        accent: colorScheme.error,
      );
      expect(chipIn(errorTileId, famdo.errorChip), findsOneWidget);

      expectToned(
        warningTileId,
        container: famdo.warningContainer,
        outline: famdo.warningOutline,
        accent: famdo.warning,
      );
      expect(chipIn(warningTileId, famdo.warningChip), findsOneWidget);

      // Under Today the header already names the day, so there is no chip.
      expectToned(
        successTileId,
        container: famdo.successContainer,
        outline: famdo.successOutline,
        accent: famdo.success,
      );

      // A future tile stays on the default surface: no tint, no left edge.
      final neutralCard = cardOf(neutralTileId);
      expect(neutralCard.color, colorScheme.surfaceContainerLow);
      expect(
        (neutralCard.shape! as RoundedRectangleBorder).side.color,
        colorScheme.outlineVariant,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(neutralTileId),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints?.minWidth == 3 &&
                widget.constraints?.maxWidth == 3,
          ),
        ),
        findsNothing,
      );
    },
  );
}
