import 'package:chore_app/app/providers.dart';
import 'package:chore_app/application/auth_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';
import 'fake_auth_gateway.dart';
import 'settings_test_utils.dart';

/// Finds the [TextField] wrapped by the semantic id [identifier].
Finder _fieldFor(String identifier) {
  return find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(TextField),
  );
}

/// Finds the [FilledButton] wrapped by the semantic id [identifier].
Finder _filledButtonFor(String identifier) {
  return find
      .descendant(
        of: find.bySemanticsIdentifier(identifier),
        matching: find.byType(FilledButton),
      )
      .first;
}

/// Widget-level tests for the Settings tab's Account section (spec
/// `docs/specs/sync-backend.md` §5): the disabled 'coming soon' row under
/// the built-in `NoopAuthGateway`, and -- via [FakeAuthGateway] -- the
/// signed-out magic-link form (email validation, send, confirmation state,
/// send failure) and the signed-in display/sign-out confirm flow.
void main() {
  final today = DateTime(2026, 7, 24, 9);

  testChoreApp(
    "Noop gateway: shows the disabled 'coming soon' row, no interactive "
    'account UI',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(const NoopAuthGateway()),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.comingSoon'),
        findsOneWidget,
      );
      expect(find.text('Sync — coming soon'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsNothing,
      );

      final tile = tester.widget<ListTile>(
        find
            .descendant(
              of: find.bySemanticsIdentifier('settings.account.comingSoon'),
              matching: find.byType(ListTile),
            )
            .first,
      );
      expect(tile.enabled, isFalse);

      // The rest of the screen still renders fine alongside it.
      expect(
        find.bySemanticsIdentifier('settings.digest.toggle'),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('settings.reset'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out: the send button stays disabled until the email looks '
    'plausible, then sends and shows the confirmation state',
    today: today,
    overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.text('Sign in to sync your household across your devices.'),
        findsOneWidget,
      );

      FilledButton sendButtonWidget() => tester.widget<FilledButton>(
        _filledButtonFor('settings.account.sendLink'),
      );

      expect(sendButtonWidget().onPressed, isNull, reason: 'empty field');

      await tester.enterText(
        _fieldFor('settings.account.email'),
        'not-an-email',
      );
      await tester.pump();
      expect(
        sendButtonWidget().onPressed,
        isNull,
        reason: 'missing @ and domain',
      );

      await tester.enterText(
        _fieldFor('settings.account.email'),
        'me@example.com',
      );
      await tester.pump();
      expect(sendButtonWidget().onPressed, isNotNull);
      expect(find.text('Send sign-in link'), findsOneWidget);

      await tester.tap(_filledButtonFor('settings.account.sendLink'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Check your email at me@example.com for your sign-in link.',
        ),
        findsOneWidget,
      );
      expect(find.text('Send again'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-out: a magic-link send failure shows the generic error '
    'snackbar and stays in the signed-out (non-confirmation) state',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway()..sendMagicLinkError = Exception('network down'),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.enterText(
        _fieldFor('settings.account.email'),
        'me@example.com',
      );
      await tester.pump();
      await tester.tap(_filledButtonFor('settings.account.sendLink'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't send the sign-in link. Please try again."),
        findsOneWidget,
      );
      expect(find.text('Send sign-in link'), findsOneWidget);
      expect(find.text('Send again'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in: shows the account email; cancelling the sign-out confirm '
    'dialog is a no-op',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsOneWidget,
      );
      expect(find.text('me@example.com'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsNothing,
      );

      await tester.tap(find.bySemanticsIdentifier('settings.account.signOut'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier('settings.account.signOut.confirm'),
        findsOneWidget,
      );

      await tester.tap(
        find.bySemanticsIdentifier('settings.account.signOut.cancel'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsOneWidget,
      );
      expect(find.text('me@example.com'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'signed-in: confirming the sign-out dialog signs out and returns to '
    'the signed-out form',
    today: today,
    overrides: [
      authGatewayProvider.overrideWithValue(
        FakeAuthGateway(
          currentUser: const AuthUser(id: 'u1', email: 'me@example.com'),
        ),
      ),
    ],
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openSettingsTab(tester);

      await tester.tap(find.bySemanticsIdentifier('settings.account.signOut'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('settings.account.signOut.confirm'),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('settings.account.signedIn'),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier('settings.account.email'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );
}
