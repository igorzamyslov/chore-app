import 'package:chore_app/app/app.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/category_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

/// Widget-level tests for the welcome gate's root screen (spec
/// `docs/specs/onboarding-v2.md` §1/§2/§3): the gate showing on an empty
/// database, the join card's Noop-gated visibility, the create path, and
/// mid-flow-kill resuming at the gate.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testFreshChoreApp(
    'empty database: the welcome gate shows the create card and the '
    'offline small print; the join card is hidden under the default Noop '
    'auth gateway (no --dart-define in this test binary)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('welcome.create'), findsOneWidget);
      expect(find.bySemanticsIdentifier('welcome.offline'), findsOneWidget);
      expect(find.bySemanticsIdentifier('welcome.join'), findsNothing);
      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsNothing);

      expect(await database.select(database.households).get(), isEmpty);

      handle.dispose();
    },
  );

  testFreshChoreApp(
    'the join card appears once authGatewayProvider is NOT the Noop '
    'gateway',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();

      expect(find.bySemanticsIdentifier('welcome.join'), findsOneWidget);

      handle.dispose();
    },
  );

  testFreshChoreApp(
    'create path: typing a name and confirming creates the household with '
    'ONE named admin member (first seed color), seeds default categories, '
    'marks the onboarding name-prompt flag (so the banner never appears), '
    'and lands on the chores tab',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.create'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('welcome.create.name'),
        findsOneWidget,
      );
      await tester.enterText(
        _fieldFor('welcome.create.name'),
        'Jordan',
      );
      await tester.pump();
      await tester.tap(find.bySemanticsIdentifier('welcome.create.confirm'));
      await tester.pumpAndSettle();

      // Landed on the chores tab; the welcome gate is gone.
      expect(find.bySemanticsIdentifier('shell.tab.chores'), findsOneWidget);
      expect(find.bySemanticsIdentifier('welcome.create'), findsNothing);

      final households = await database.select(database.households).get();
      expect(households, hasLength(1));
      final householdId = households.single.id;

      final members = await database.select(database.members).get();
      expect(members, hasLength(1));
      expect(members.single.name, 'Jordan');
      expect(members.single.role, MemberRole.admin);
      expect(members.single.color, CategoryRepository.seedColors.first);
      expect(members.single.householdId, householdId);

      // Default categories seeded (7 chore + 8 shopping).
      final categories = await database.select(database.categories).get();
      expect(categories, hasLength(15));

      // The name-prompt flag is marked at creation (spec §1): the banner
      // is dead on arrival for this path.
      final settings = await database.select(database.settings).getSingle();
      expect(settings.onboardingNamePromptShownAt, isNotNull);
      expect(find.bySemanticsIdentifier('onboarding.name'), findsNothing);

      handle.dispose();
    },
  );

  testFreshChoreApp(
    'the create confirm button stays disabled until a non-blank name is '
    'typed (same validation as the member edit sheet)',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.create'));
      await tester.pumpAndSettle();

      FilledButton confirmButton() => tester.widget<FilledButton>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('welcome.create.confirm'),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(confirmButton().onPressed, isNull);

      await tester.enterText(_fieldFor('welcome.create.name'), '   ');
      await tester.pump();
      expect(confirmButton().onPressed, isNull, reason: 'blank after trim');

      await tester.enterText(_fieldFor('welcome.create.name'), 'Sam');
      await tester.pump();
      expect(confirmButton().onPressed, isNotNull);

      handle.dispose();
    },
  );

  testFreshChoreApp(
    'mid-flow kill (partway through the create form) resumes at the '
    'welcome gate on relaunch, since no household was ever created',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      await tester.tap(find.bySemanticsIdentifier('welcome.create'));
      await tester.pumpAndSettle();
      await tester.enterText(_fieldFor('welcome.create.name'), 'Almost');
      await tester.pump();
      expect(await database.select(database.households).get(), isEmpty);

      // Simulated kill+relaunch: pump a brand-new widget tree/ProviderScope
      // over the exact same, still-open in-memory database. A fresh `Key`
      // is load-bearing here (unlike the plain re-pump `language_and_about_
      // test.dart`/`acting_member_widget_test.dart` use for settings that
      // live in the DATABASE): without one, `tester.pumpWidget` treats this
      // as an in-place rebuild of the SAME element/State tree (matching a
      // hot-reload, not a process kill), so `WelcomeScreen`'s own ephemeral
      // `_creatingHousehold` field would survive untouched -- which would
      // make this test pass for the wrong reason. A real OS-level kill
      // discards ALL in-memory state unconditionally; the new key forces
      // that here too, leaving only the database (still empty) to resume
      // from.
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            clockProvider.overrideWithValue(Clock.fixed(today)),
          ],
          child: const ChoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('welcome.create'),
        findsOneWidget,
        reason: 'state is simply "no household yet" -- resumes at the gate',
      );
      expect(await database.select(database.households).get(), isEmpty);
      handle.dispose();
    },
  );
}
