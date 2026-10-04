import 'dart:async';

import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSink implements ErrorLogSink {
  final List<({String source, ScrubbedError error})> recorded = [];

  @override
  Future<void> record({
    required String source,
    required ScrubbedError error,
  }) async {
    recorded.add((source: source, error: error));
  }
}

class _ThrowingSink implements ErrorLogSink {
  int calls = 0;

  @override
  Future<void> record({
    required String source,
    required ScrubbedError error,
  }) async {
    calls++;
    throw StateError('sink failed');
  }
}

class _SyncThrowingSink implements ErrorLogSink {
  @override
  Future<void> record({required String source, required ScrubbedError error}) {
    throw StateError('sink failed synchronously');
  }
}

void main() {
  tearDown(AppLog.detach);

  test('with no sink attached it does not throw', () {
    expect(
      () => AppLog.error('ui.test', StateError('boom'), StackTrace.current),
      returnsNormally,
    );
  });

  test('a scrubbed error reaches the attached sink', () async {
    final sink = _RecordingSink();
    AppLog.attach(sink);

    AppLog.error(
      'sync.realtime',
      StateError('failed for "Anna"'),
      null,
      context: {'status': 'channelError'},
    );
    await pumpEventQueue();

    final recorded = sink.recorded.single;
    expect(recorded.source, 'sync.realtime');
    expect(recorded.error.message, 'Bad state: failed for <str>');
    expect(recorded.error.context, {'status': 'channelError'});
  });

  test('a sink that rejects does not throw and is not retried', () async {
    final sink = _ThrowingSink();
    final unhandled = <Object>[];
    await runZonedGuarded(() async {
      AppLog.attach(sink);

      expect(
        () => AppLog.error('ui.test', StateError('a'), null),
        returnsNormally,
      );
      await pumpEventQueue();
    }, (error, stack) => unhandled.add(error));

    expect(sink.calls, 1);
    expect(unhandled, isEmpty);
  });

  test('a sink that throws synchronously does not throw', () {
    AppLog.attach(_SyncThrowingSink());

    expect(
      () => AppLog.error('ui.test', StateError('a'), null),
      returnsNormally,
    );
  });

  test('detach stops routing', () async {
    final sink = _RecordingSink();
    AppLog.attach(sink);
    AppLog.detach();

    AppLog.error('ui.test', StateError('a'), null);
    await pumpEventQueue();

    expect(sink.recorded, isEmpty);
  });

  group('DatabaseErrorLogSink', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    DatabaseErrorLogSink sink() => DatabaseErrorLogSink(
      db,
      nowUtc: () => DateTime.utc(2026, 10, 4),
      appVersion: () async => '0.13.0+20',
      platform: () => 'android 14',
    );

    ScrubbedError scrubbed() => ErrorScrubber.scrub(StateError('boom'), null);

    test('stamps version, platform and the linked household', () async {
      await SettingsRepository(db).setSyncLinked(
        householdId: 'h-1',
        linkedAt: DateTime.utc(2026),
      );

      await sink().record(source: 'ui.test', error: scrubbed());

      final row = (await db.select(db.clientErrors).get()).single;
      expect(row.appVersion, '0.13.0+20');
      expect(row.platform, 'android 14');
      expect(row.householdId, 'h-1');
      expect(row.firstSeenAt, '2026-10-04T00:00:00.000Z');
    });

    test('with no settings row it records unlinked and does not create '
        'one', () async {
      await sink().record(source: 'ui.test', error: scrubbed());

      final row = (await db.select(db.clientErrors).get()).single;
      expect(row.householdId, isNull);
      expect(await db.select(db.settings).get(), isEmpty);
    });
  });
}
