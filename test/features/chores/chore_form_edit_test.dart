import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'edit round-trip: open prefilled, change the title, save, list shows it',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final service = ChoreService(
        database: database,
        chores: ChoreRepository(database),
        clock: Clock.fixed(today),
      );
      final chore = await service.createChore(
        householdId: householdId,
        title: 'Original title',
        startDate: PlainDate(2026, 7, 24),
        assignmentMode: AssignmentMode.anyone,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('chores.menu.edit'));
      await tester.pumpAndSettle();

      // Prefilled from the existing chore.
      expect(find.text('Original title'), findsOneWidget);

      final titleField = find.descendant(
        of: find.bySemanticsIdentifier('chore_form.title'),
        matching: find.byType(TextField),
      );
      await tester.enterText(titleField, 'Updated title');
      await tester.tap(find.bySemanticsIdentifier('chore_form.save'));
      await tester.pumpAndSettle();

      // Back on the list, showing the updated title.
      expect(find.bySemanticsIdentifier('chore_form.save'), findsNothing);
      expect(find.text('Updated title'), findsOneWidget);
      expect(find.text('Original title'), findsNothing);

      handle.dispose();
    },
  );
}
