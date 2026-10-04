/// The live-backend smoke for client error reports (spec
/// `docs/specs/client-error-reporting.md` §5.3), run against a REAL Supabase
/// stack.
///
/// The fake transport in the unit tests agrees with whatever the reporter
/// believes; this file proves the REAL [SupabaseErrorReportTransport]: that
/// `upsert(..., ignoreDuplicates: true)` is accepted under the INSERT-only
/// grant (a plain upsert would be rejected 42501 for want of UPDATE), that a
/// re-send of the same rows does not throw, and that the server stamps
/// `user_id` itself.
///
/// Lives in `test_live/`, not `test/`, for the reasons spelled out in
/// `household_exit_live_test.dart`, whose setup and fail-closed safety guard
/// this file copies. Run via `tool/live_smoke.sh` (which runs the whole
/// directory, so this file needs no registration).
library;

import 'dart:io';

import 'package:chore_app/application/error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const String _url = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const String _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

/// Service-role client used to create confirmed users and to read the table
/// back (clients have no SELECT grant).
late final SupabaseClient _admin;

/// In-memory PKCE store -- see `household_exit_live_test.dart` for why both
/// this and `EmptyLocalStorage` are needed.
class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}

void main() {
  // FAIL CLOSED -- same guard as `household_exit_live_test.dart`.
  final host = Uri.parse(_url).host;
  if (host != '127.0.0.1' && host != 'localhost') {
    throw StateError(
      'REFUSING TO RUN: SUPABASE_URL is "$_url", whose host is "$host". '
      'This suite creates accounts and writes data, so it only '
      'ever runs against a loopback stack. Start one with `supabase start` '
      'and re-run via tool/live_smoke.sh.',
    );
  }
  if (_anonKey.isEmpty || _serviceKey.isEmpty) {
    throw StateError(
      'REFUSING TO RUN: SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY must '
      'both be passed as --dart-define. `supabase status` prints both.',
    );
  }

  const transport = SupabaseErrorReportTransport();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // See `household_exit_live_test.dart`: the test binding's HttpOverrides
    // answers every request with an empty 400 until it is cleared.
    HttpOverrides.global = null;
    await Supabase.initialize(
      url: _url,
      publishableKey: _anonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
        detectSessionInUri: false,
      ),
    );
    _admin = SupabaseClient(
      _url,
      _serviceKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test(
    'insertErrors is accepted under the INSERT-only grant, is idempotent on '
    'a re-send, and the server stamps user_id',
    () async {
      final email =
          'errors.${DateTime.now().microsecondsSinceEpoch}@example.com';
      const password = 'smoke-password-123';
      final created = await _admin.auth.admin.createUser(
        AdminUserAttributes(
          email: email,
          password: password,
          emailConfirm: true,
        ),
      );
      final userId = created.user!.id;
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      final ids = [const Uuid().v4(), const Uuid().v4()];
      final rows = [
        for (final id in ids)
          {
            'id': id,
            'source': 'sync.pushDirty',
            'error_type': 'StateError',
            'message': 'Bad state: smoke',
            'stack': '#0 main (file.dart:1:1)',
            'context': {'table': 'chores'},
            'count': 2,
            'first_seen_at': now,
            'last_seen_at': now,
            'app_version': '0.13.0+20',
            'platform': 'linux smoke',
            'household_id': null,
          },
      ];

      await transport.insertErrors(rows);
      // The same rows again must not throw: proves `ignoreDuplicates` needs
      // no UPDATE grant (and `.select()` is not chained: no SELECT grant).
      await transport.insertErrors(rows);

      final stored = await _admin
          .from('client_errors')
          .select()
          .inFilter('id', ids);
      expect(stored, hasLength(2));
      for (final row in stored) {
        expect(row['user_id'], userId);
        expect(row['count'], 2);
      }
    },
  );
}
