import 'dart:async';

import 'package:chore_app/application/error_reporter.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/error_log_repository.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _FakeTransport implements ErrorReportTransport {
  final List<List<Map<String, Object?>>> batches = [];
  Exception? failWith;
  Completer<void>? block;

  @override
  Future<void> insertErrors(List<Map<String, Object?>> rows) async {
    batches.add(rows);
    final pending = block;
    if (pending != null) {
      await pending.future;
    }
    if (failWith != null) {
      throw failWith!;
    }
  }
}

void main() {
  late AppDatabase db;
  late ErrorLogRepository repo;
  late _FakeTransport transport;
  late ErrorReporter reporter;
  var gate = const ErrorReportGate(
    supabaseConfigured: true,
    signedIn: true,
    linked: true,
    enabled: true,
  );
  var seconds = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seconds = 0;
    repo = ErrorLogRepository(
      db,
      nowUtc: () => DateTime.utc(2026, 10, 4).add(Duration(seconds: seconds++)),
    );
    transport = _FakeTransport();
    gate = const ErrorReportGate(
      supabaseConfigured: true,
      signedIn: true,
      linked: true,
      enabled: true,
    );
    reporter = ErrorReporter(
      repository: repo,
      transport: transport,
      gate: () => gate,
      nowUtc: () => DateTime.utc(2027),
    );
  });

  tearDown(() => db.close());

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await repo.record(
        source: 'ui.test',
        error: ErrorScrubber.scrub(
          StateError('m$i'),
          null,
          context: {'n': '$i'},
        ),
        appVersion: '0.13.0+20',
        platform: 'android 14',
        householdId: 'h-1',
      );
    }
  }

  ErrorReportGate gateWith({
    bool? supabaseConfigured,
    bool? signedIn,
    bool? linked,
    bool? enabled,
  }) => ErrorReportGate(
    supabaseConfigured: supabaseConfigured ?? true,
    signedIn: signedIn ?? true,
    linked: linked ?? true,
    enabled: enabled ?? true,
  );

  group('gate', () {
    final cases = <String, ErrorReportGate>{
      'Supabase not configured': gateWith(supabaseConfigured: false),
      'signed out': gateWith(signedIn: false),
      'unlinked': gateWith(linked: false),
      'switch off': gateWith(enabled: false),
    };
    for (final entry in cases.entries) {
      test('${entry.key}: nothing is sent and rows stay pending', () async {
        await seed(2);
        gate = entry.value;

        await reporter.flush();

        expect(transport.batches, isEmpty);
        expect(await repo.pending(), hasLength(2));
      });
    }

    test('re-opening the gate sends what was held back', () async {
      await seed(2);
      gate = gateWith(enabled: false);
      await reporter.flush();
      gate = gateWith();

      await reporter.flush();

      expect(transport.batches.single, hasLength(2));
      expect(await repo.pending(), isEmpty);
    });
  });

  test(
    'sends the snake_case row shape, then marks the rows uploaded',
    () async {
      await seed(1);

      await reporter.flush();

      final row = transport.batches.single.single;
      expect(row.keys.toSet(), {
        'id',
        'source',
        'error_type',
        'message',
        'stack',
        'context',
        'count',
        'first_seen_at',
        'last_seen_at',
        'app_version',
        'platform',
        'household_id',
      });
      expect(row['source'], 'ui.test');
      expect(row['error_type'], 'StateError');
      expect(row['context'], {'n': '0'});
      expect(row['count'], 1);
      expect(row['household_id'], 'h-1');
      expect(row.containsKey('user_id'), isFalse);
      expect(row.containsKey('received_at'), isFalse);

      final stored = (await db.select(db.clientErrors).get()).single;
      expect(stored.uploadedAt, '2027-01-01T00:00:00.000Z');
    },
  );

  test('a null context is sent as null', () async {
    await repo.record(
      source: 'ui.test',
      error: ErrorScrubber.scrub(StateError('x'), null),
      appVersion: 'v',
      platform: 'p',
    );

    await reporter.flush();

    expect(transport.batches.single.single['context'], isNull);
  });

  test('batches of 50, at most 4 per flush (200 rows)', () async {
    // Distinct messages so nothing merges; 200 is also the buffer cap.
    await seed(200);
    await reporter.flush();

    expect(transport.batches.map((b) => b.length), [50, 50, 50, 50]);
    expect(await repo.pending(), isEmpty);
  });

  test(
    'a partial last batch is sent and a second flush has nothing to do',
    () async {
      await seed(120);
      final small = ErrorReporter(
        repository: repo,
        transport: transport,
        gate: () => gate,
      );

      await small.flush();
      expect(transport.batches.map((b) => b.length), [50, 50, 20]);

      await small.flush();
      expect(transport.batches, hasLength(3));
    },
  );

  test('a failing upload stops the flush and leaves rows pending', () async {
    await seed(3);
    transport.failWith = Exception('offline');

    await expectLater(reporter.flush(), completes);

    expect(transport.batches, hasLength(1));
    expect(await repo.pending(), hasLength(3));

    transport.failWith = null;
    await reporter.flush();
    expect(await repo.pending(), isEmpty);
  });

  test('a batch the server rejects as invalid data is dropped, not '
      'retried forever', () async {
    await seed(3);
    transport.failWith = const PostgrestException(
      message: 'new row violates check constraint',
      code: '23514',
    );

    await reporter.flush();

    expect(transport.batches, hasLength(1));
    expect(await repo.pending(), isEmpty);
  });

  test('a PostgrestException outside classes 22/23 still retries', () async {
    await seed(3);
    transport.failWith = const PostgrestException(
      message: 'JWT expired',
      code: 'PGRST301',
    );

    await reporter.flush();

    expect(await repo.pending(), hasLength(3));
  });

  test('a concurrent flush is dropped by the guard', () async {
    await seed(2);
    transport.block = Completer<void>();

    final first = reporter.flush();
    await pumpEventQueue();
    await reporter.flush();
    expect(transport.batches, hasLength(1));

    transport.block!.complete();
    await first;
    expect(await repo.pending(), isEmpty);

    // And the guard is released afterwards.
    transport.block = null;
    await seed(1);
    await reporter.flush();
    expect(transport.batches, hasLength(2));
  });

  test('an uploaded row is never re-sent', () async {
    await seed(1);
    await reporter.flush();
    await reporter.flush();

    expect(transport.batches, hasLength(1));
  });
}
