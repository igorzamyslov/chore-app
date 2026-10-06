import 'package:chore_app/features/settings/join_flow_steps.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Unit tests for [joinCodeErrorMessage] (persona review D5): a rejected
/// code, any other server error, and a failure before the server answered
/// each get their own copy.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('a PostgrestException naming an invalid or expired code reads as '
      '"check the code"', () {
    for (final message in ['invalid or expired invite', 'invalid code']) {
      expect(
        joinCodeErrorMessage(l10n, PostgrestException(message: message)),
        l10n.joinHouseholdCodeError,
        reason: message,
      );
    }
  });

  test('any other PostgrestException is a server problem, not a typo', () {
    expect(
      joinCodeErrorMessage(
        l10n,
        const PostgrestException(
          message: 'permission denied for function peek_invite',
          code: '42501',
        ),
      ),
      l10n.joinCodeErrorServer,
    );
    expect(
      l10n.joinCodeErrorServer,
      "Couldn't check the code right now — try again in a moment.",
    );
  });

  test('a non-Postgrest failure keeps the connection copy', () {
    expect(
      joinCodeErrorMessage(l10n, Exception('SocketException: no route')),
      l10n.joinHouseholdCodeUnknownError,
    );
  });
}
