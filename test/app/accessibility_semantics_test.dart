import 'dart:ui' show Tristate;

import 'package:chore_app/application/chore_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/chore_repository.dart';
import 'package:chore_app/data/repositories/shopping_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/shopping/shopping_test_utils.dart';
import '../test_utils/pump_app.dart';

/// G1 (persona review 2026-10-06): screen-reader names. A list of identical
/// "Complete" / "More actions" buttons and unnamed check rings is unusable
/// with TalkBack/VoiceOver, so each control names its row; settings group
/// headers are headers; tabs say "Tab N of 3".
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'chore tile complete and more-actions buttons name the chore',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final chore =
          await ChoreService(
            database: database,
            chores: ChoreRepository(database),
            clock: Clock.fixed(today),
          ).createChore(
            householdId: householdId,
            title: 'Take out trash',
            startDate: PlainDate(2026, 7, 24),
            assignmentMode: AssignmentMode.anyone,
          );
      await tester.pumpAndSettle();

      final complete = tester.getSemantics(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.complete'),
      );
      expect(complete.label, 'Complete: Take out trash');
      expect(complete.getSemanticsData().flagsCollection.isButton, isTrue);
      final menu = tester.getSemantics(
        find.bySemanticsIdentifier('chores.occurrence.${chore.id}.menu'),
      );
      expect(menu.label, 'More actions: Take out trash');

      handle.dispose();
    },
  );

  testChoreApp(
    'the shopping check ring carries the item name',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final item = await ShoppingRepository(
        database,
      ).addItem(householdId, name: 'Oat milk');
      await openShoppingTab(tester);
      await tester.pumpAndSettle();

      final ring = tester.getSemantics(
        find.bySemanticsIdentifier('shopping.item.${item.id}.check'),
      );
      expect(ring.label, 'Oat milk');
      expect(ring.getSemanticsData().flagsCollection.isButton, isTrue);

      handle.dispose();
    },
  );

  testChoreApp(
    'settings group headers are semantic headers, in natural case',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsIdentifier('shell.tab.settings'));
      await tester.pumpAndSettle();

      final headers = find.semantics
          .byLabel('Household')
          .evaluate()
          .where((n) => n.getSemanticsData().flagsCollection.isHeader);
      expect(headers, isNotEmpty);

      handle.dispose();
    },
  );

  testChoreApp(
    'bottom tabs announce their position and keep the selected trait',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      final chores = tester.getSemantics(
        find.bySemanticsIdentifier('shell.tab.chores'),
      );
      expect(chores.label, contains('Tab 1 of 3'));
      expect(chores.label, contains('Chores'));
      expect(
        chores.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      final settings = tester.getSemantics(
        find.bySemanticsIdentifier('shell.tab.settings'),
      );
      expect(settings.label, contains('Tab 3 of 3'));

      handle.dispose();
    },
  );
}
