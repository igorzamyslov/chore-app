/// The live-backend smoke for hard-delete tombstones (spec
/// `docs/specs/sync-backend.md` §8.6), run against a REAL Supabase stack.
///
/// The fake transport's `markDeleted` agrees with whatever the engine
/// believes; this file proves the REAL one: that a PostgREST UPDATE of
/// `deleted_at` is actually permitted by RLS and the column grants on
/// `chore_occurrences`/`chore_assignees`, that the `set_updated_at()` trigger
/// advances `updated_at` (which is what lets other devices' pull cursor see
/// the tombstone), and that a second household member's `pullTable` returns
/// it.
///
/// Lives in `test_live/`, not `test/`, for the reasons spelled out in
/// `household_exit_live_test.dart`, whose setup and fail-closed safety guard
/// this file copies. Run via `tool/live_smoke.sh` (which runs the whole
/// directory, so this file needs no registration).
library;

import 'dart:io';

import 'package:chore_app/application/household_gateway.dart';
import 'package:chore_app/application/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const String _url = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);
const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const String _serviceKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

/// Service-role client used ONLY to create confirmed users.
late final SupabaseClient _admin;

int _uniqueSuffix = 0;

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

Future<({String email, String password})> _createUser() async {
  _uniqueSuffix++;
  final email =
      'tombstone$_uniqueSuffix.${DateTime.now().microsecondsSinceEpoch}'
      '@example.com';
  const password = 'smoke-password-123';
  await _admin.auth.admin.createUser(
    AdminUserAttributes(
      email: email,
      password: password,
      emailConfirm: true,
    ),
  );
  return (email: email, password: password);
}

Future<void> _signInAs(({String email, String password}) user) async {
  final client = Supabase.instance.client;
  if (client.auth.currentSession != null) {
    await client.auth.signOut();
  }
  await client.auth.signInWithPassword(
    email: user.email,
    password: user.password,
  );
}

void main() {
  // FAIL CLOSED -- same guard as `household_exit_live_test.dart`.
  final host = Uri.parse(_url).host;
  if (host != '127.0.0.1' && host != 'localhost') {
    throw StateError(
      'REFUSING TO RUN: SUPABASE_URL is "$_url", whose host is "$host". '
      'This suite creates accounts and writes household data, so it only '
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

  const gateway = SupabaseHouseholdGateway();
  const transport = SupabaseSyncTransport();

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
    'markDeleted sets deleted_at on an occurrence and an assignee under '
    "RLS, advances updated_at, and a second member's pullTable sees it",
    () async {
      final owner = await _createUser();
      final joiner = await _createUser();

      await _signInAs(owner);
      final householdId = const Uuid().v4();
      final ownerMemberId = const Uuid().v4();
      await gateway.createHousehold(
        householdId: householdId,
        name: 'Tombstone household',
        memberId: ownerMemberId,
        memberName: 'Owner',
        memberColor: 0xFF2196F3,
      );
      final code = await gateway.createInvite(householdId);

      final choreId = const Uuid().v4();
      final occurrenceId = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await transport.upsertRows('chores', [
        {
          'id': choreId,
          'household_id': householdId,
          'title': 'Dishes',
          'start_date': '2026-01-01',
          'assignment_mode': 'fixed',
          'created_by': ownerMemberId,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        },
      ]);
      await transport.upsertRows('chore_occurrences', [
        {
          'id': occurrenceId,
          'chore_id': choreId,
          'household_id': householdId,
          'due_date': '2026-01-05',
          'status': 'pending',
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        },
      ]);
      await transport.upsertRows('chore_assignees', [
        {
          'chore_id': choreId,
          'member_id': ownerMemberId,
          'household_id': householdId,
          'position': 0,
          'deleted_at': null,
        },
      ], onConflict: 'chore_id,member_id');

      Future<Map<String, Object?>> pulledRow(
        String table,
        bool Function(Map<String, Object?>) match,
      ) async {
        final rows = await transport.pullTable(
          table,
          householdId: householdId,
          since: null,
        );
        return rows.singleWhere(match);
      }

      final occurrenceBefore = await pulledRow(
        'chore_occurrences',
        (row) => row['id'] == occurrenceId,
      );
      final assigneeBefore = await pulledRow(
        'chore_assignees',
        (row) => row['member_id'] == ownerMemberId,
      );
      expect(occurrenceBefore['deleted_at'], isNull);
      expect(assigneeBefore['deleted_at'], isNull);

      final deletedAt = DateTime.now().toUtc().toIso8601String();
      await transport.markDeleted('chore_occurrences', {
        'id': occurrenceId,
      }, deletedAt);
      await transport.markDeleted('chore_assignees', {
        'chore_id': choreId,
        'member_id': ownerMemberId,
      }, deletedAt);
      // Zero matching rows is success, not an error (spec §8.6.3).
      await transport.markDeleted('chore_occurrences', {
        'id': const Uuid().v4(),
      }, deletedAt);

      // The acting member sees it...
      final occurrenceAfter = await pulledRow(
        'chore_occurrences',
        (row) => row['id'] == occurrenceId,
      );
      final assigneeAfter = await pulledRow(
        'chore_assignees',
        (row) => row['member_id'] == ownerMemberId,
      );
      expect(occurrenceAfter['deleted_at'], isNotNull);
      expect(assigneeAfter['deleted_at'], isNotNull);
      // ...and the trigger moved updated_at forward, which is the only thing
      // that lets another device's cursor-based pull find the tombstone.
      expect(
        DateTime.parse(occurrenceAfter['updated_at']! as String).isAfter(
          DateTime.parse(occurrenceBefore['updated_at']! as String),
        ),
        isTrue,
      );
      expect(
        DateTime.parse(assigneeAfter['updated_at']! as String).isAfter(
          DateTime.parse(assigneeBefore['updated_at']! as String),
        ),
        isTrue,
      );

      // A SECOND household member, with a pull cursor from before the
      // delete, still sees both tombstones.
      await _signInAs(joiner);
      await gateway.joinAsNewMember(
        code: code,
        memberId: const Uuid().v4(),
        memberName: 'Joiner',
        memberColor: 0xFF4CAF50,
      );
      final since = DateTime.parse(
        occurrenceBefore['updated_at']! as String,
      ).toUtc();
      final occurrencesSeen = await transport.pullTable(
        'chore_occurrences',
        householdId: householdId,
        since: since,
      );
      final assigneesSeen = await transport.pullTable(
        'chore_assignees',
        householdId: householdId,
        since: since,
      );
      expect(
        occurrencesSeen.singleWhere(
          (row) => row['id'] == occurrenceId,
        )['deleted_at'],
        isNotNull,
      );
      expect(
        assigneesSeen.singleWhere(
          (row) => row['member_id'] == ownerMemberId,
        )['deleted_at'],
        isNotNull,
      );
    },
  );
}
