import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import '../settings/fake_auth_gateway.dart';

/// A-5 (spec `docs/feedback/2026-08-07-field-feedback.md` B1): the app-bar
/// acting-member SWITCHER is offered only while this device cannot know who
/// is holding it. Once linked AND signed in, the same slot shows a
/// non-interactive avatar of the claimed member and opens nothing.
///
/// The linked state is driven exactly as a real link flow would drive it
/// (`SettingsRepository.setSyncLinked` + the local `members.userId` mirror
/// `HouseholdLinkService.adopt` now writes), and auth through the
/// documented `authGatewayProvider` seam -- no repository or service is
/// mocked (spec `docs/specs/testing-strategy.md`).
Future<void> _pumpUntilPinned(WidgetTester tester) async {
  final button = find.bySemanticsIdentifier('chores.actingMember');
  for (var i = 0; i < 400; i++) {
    final tappable = find
        .descendant(of: button, matching: find.byType(IconButton))
        .evaluate()
        .isNotEmpty;
    if (!tappable && button.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 5));
  }
  throw StateError('the app-bar button never became non-interactive');
}

void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    'a local-only household keeps the switcher exactly as it was',
    today: today,
    (tester, database) async {
      final handle = tester.ensureSemantics();

      final button = find.bySemanticsIdentifier('chores.actingMember');
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byType(IconButton)),
        findsOneWidget,
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('actingMember.sheet'), findsOneWidget);
      expect(find.bySemanticsIdentifier('acting.manage'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'once linked AND signed in, the slot shows the claimed member and opens '
    'nothing',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u-1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final householdId = await currentHouseholdId(database);
      final me = await (database.select(
        database.members,
      )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();

      await (database.update(
        database.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('u-1')),
      );
      await SettingsRepository(
        database,
      ).setSyncLinked(householdId: householdId, linkedAt: today);

      await _pumpUntilPinned(tester);

      final button = find.bySemanticsIdentifier('chores.actingMember');
      // The id survives -- it just isn't a control any more.
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(
        tester
            .widget<MemberAvatar>(
              find.descendant(of: button, matching: find.byType(MemberAvatar)),
            )
            .member
            .name,
        'Me',
      );

      // Tapping it does nothing at all: no sheet, ever.
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('actingMember.sheet'), findsNothing);

      handle.dispose();
    },
  );
}
