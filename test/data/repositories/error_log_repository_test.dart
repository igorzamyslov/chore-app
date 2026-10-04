import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/error_log_repository.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock {
  _FixedClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration duration) => _now = _now.add(duration);
}

ScrubbedError _error(
  String message, {
  String type = 'StateError',
  String? stack,
  Map<String, String> context = const {},
}) => ScrubbedError(
  errorType: type,
  message: message,
  stack: stack,
  context: context,
);

void main() {
  late AppDatabase db;
  late ErrorLogRepository repo;
  late _FixedClock clock;
  var nextId = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = _FixedClock(DateTime.utc(2026, 10, 4, 12));
    nextId = 0;
    repo = ErrorLogRepository(
      db,
      nowUtc: clock.call,
      newId: () => 'id-${(nextId++).toString().padLeft(4, '0')}',
    );
  });

  tearDown(() => db.close());

  Future<void> record(
    String source,
    ScrubbedError error, {
    String appVersion = '0.13.0+20',
    String? householdId,
  }) => repo.record(
    source: source,
    error: error,
    appVersion: appVersion,
    platform: 'android 14',
    householdId: householdId,
  );

  test('a first occurrence inserts a row with count 1', () async {
    await record(
      'sync.pushDirty',
      _error('boom', context: {'table': 'chores'}),
      householdId: 'h1',
    );

    final row = (await db.select(db.clientErrors).get()).single;
    expect(row.id, 'id-0000');
    expect(row.source, 'sync.pushDirty');
    expect(row.errorType, 'StateError');
    expect(row.message, 'boom');
    expect(row.context, '{"table":"chores"}');
    expect(row.count, 1);
    expect(row.firstSeenAt, '2026-10-04T12:00:00.000Z');
    expect(row.lastSeenAt, '2026-10-04T12:00:00.000Z');
    expect(row.appVersion, '0.13.0+20');
    expect(row.platform, 'android 14');
    expect(row.householdId, 'h1');
    expect(row.uploadedAt, isNull);
  });

  test('a repeat merges into the pending row and refreshes details', () async {
    await record('sync.pushDirty', _error('boom', stack: 'old'));
    clock.advance(const Duration(minutes: 5));
    await record(
      'sync.pushDirty',
      _error('boom', stack: 'new', context: {'k': 'v'}),
      appVersion: '0.13.1+21',
    );

    final row = (await db.select(db.clientErrors).get()).single;
    expect(row.count, 2);
    expect(row.firstSeenAt, '2026-10-04T12:00:00.000Z');
    expect(row.lastSeenAt, '2026-10-04T12:05:00.000Z');
    expect(row.stack, 'new');
    expect(row.context, '{"k":"v"}');
    expect(row.appVersion, '0.13.1+21');
  });

  test('a different source, type or message is a separate row', () async {
    await record('sync.pushDirty', _error('boom'));
    await record('sync.pullSince', _error('boom'));
    await record('sync.pushDirty', _error('boom', type: 'Exception'));
    await record('sync.pushDirty', _error('other'));

    expect(await db.select(db.clientErrors).get(), hasLength(4));
  });

  test('an uploaded row is never merged into: a repeat starts a new '
      'row', () async {
    await record('sync.pushDirty', _error('boom'));
    await repo.markUploaded(['id-0000'], clock());
    clock.advance(const Duration(minutes: 1));
    await record('sync.pushDirty', _error('boom'));

    final rows = await db.select(db.clientErrors).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.count), [1, 1]);
    expect(await repo.pending(), hasLength(1));
  });

  test('keeps only the newest 200 rows by lastSeenAt', () async {
    for (var i = 0; i < 203; i++) {
      await record('ui.test', _error('m$i'));
      clock.advance(const Duration(seconds: 1));
    }

    final rows = await db.select(db.clientErrors).get();
    expect(rows, hasLength(200));
    final messages = rows.map((r) => r.message).toSet();
    expect(messages, isNot(contains('m0')));
    expect(messages, isNot(contains('m2')));
    expect(messages, contains('m3'));
    expect(messages, contains('m202'));
  });

  test('uploaded rows count toward the cap', () async {
    for (var i = 0; i < 200; i++) {
      await record('ui.test', _error('m$i'));
      clock.advance(const Duration(seconds: 1));
    }
    final all = await db.select(db.clientErrors).get();
    await repo.markUploaded([for (final r in all) r.id], clock());

    await record('ui.test', _error('fresh'));

    final rows = await db.select(db.clientErrors).get();
    expect(rows, hasLength(200));
    expect(rows.map((r) => r.message), contains('fresh'));
    expect(rows.map((r) => r.message), isNot(contains('m0')));
  });

  test('pending returns un-uploaded rows, oldest first, up to limit', () async {
    for (var i = 0; i < 5; i++) {
      await record('ui.test', _error('m$i'));
      clock.advance(const Duration(seconds: 1));
    }
    await repo.markUploaded(['id-0001'], clock());

    final pending = await repo.pending(limit: 3);

    expect(pending.map((r) => r.message), ['m0', 'm2', 'm3']);
  });

  test('markUploaded stamps uploadedAt and ignores an empty list', () async {
    await record('ui.test', _error('m'));
    await repo.markUploaded(const [], clock());
    expect(await repo.pending(), hasLength(1));

    await repo.markUploaded(['id-0000'], DateTime.utc(2026, 10, 5));

    final row = (await db.select(db.clientErrors).get()).single;
    expect(row.uploadedAt, '2026-10-05T00:00:00.000Z');
  });

  test('deleteAll empties the table', () async {
    await record('ui.test', _error('m'));
    await repo.deleteAll();
    expect(await db.select(db.clientErrors).get(), isEmpty);
  });
}
