import 'dart:convert';

import 'package:chore_app/domain/error_scrubber.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('message', () {
    test('a PostgrestException keeps only its code, never details', () {
      const error = PostgrestException(
        message: 'new row for relation "chores" violates check constraint',
        code: '23514',
        details: "Failing row contains (Clean Anna's bathroom, 2026-01-01).",
        hint: 'Anna Schmidt',
      );

      final scrubbed = ErrorScrubber.scrub(error, null);

      expect(scrubbed.errorType, 'PostgrestException');
      expect(scrubbed.message, 'postgrest code=23514');
      expect(scrubbed.message, isNot(contains('Anna')));
    });

    test('a SqliteException never carries its statement or parameters', () {
      final error = SqliteException(
        extendedResultCode: 2067,
        message: 'UNIQUE constraint failed: chores.id',
        causingStatement: 'INSERT INTO chores (id, title) VALUES (?, ?)',
        parametersToStatement: [
          '20000000-0000-0000-0000-000000000001',
          "Clean Anna's room",
        ],
      );

      final scrubbed = ErrorScrubber.scrub(error, null);

      expect(
        scrubbed.message,
        'SqliteException(2067): UNIQUE constraint failed: chores.id',
      );
      expect(scrubbed.message, isNot(contains('Anna')));
    });

    test('an AuthException keeps only status and code', () {
      const error = AuthException(
        'User igor@example.com already registered',
        statusCode: '422',
        code: 'user_already_exists',
      );

      final scrubbed = ErrorScrubber.scrub(error, null);

      expect(scrubbed.message, 'auth status=422 code=user_already_exists');
    });

    test('emails and quoted member names are replaced', () {
      final error = Exception(
        'could not invite igor.z+famdo@mail.example.com as "Anna Schmidt" '
        "and 'Max' and «Lena» and “Tom”",
      );

      final scrubbed = ErrorScrubber.scrub(error, null);

      expect(
        scrubbed.message,
        'Exception: could not invite <email> as <str> and <str> and <str> '
        'and <str>',
      );
    });

    test('a UUID survives next to a long number, which is replaced', () {
      const id = '3f2b8c1e-9d4a-4e7b-8a61-0c5d2e9f7a13';
      final error = StateError('chore $id has 123456789 occurrences, 12345 ok');

      final scrubbed = ErrorScrubber.scrub(error, null);

      expect(
        scrubbed.message,
        'Bad state: chore $id has <num> occurrences, 12345 ok',
      );
    });

    test('digits inside a UUID are never mistaken for a long number', () {
      const id = '12345678-1234-1234-1234-123456789012';

      expect(
        ErrorScrubber.scrub(StateError('row $id'), null).message,
        'Bad state: row $id',
      );
    });

    test('a UUID inside a quoted span goes with the span', () {
      const id = '3f2b8c1e-9d4a-4e7b-8a61-0c5d2e9f7a13';

      expect(
        ErrorScrubber.scrub(StateError('bad "title $id"'), null).message,
        'Bad state: bad <str>',
      );
    });

    test('the message is capped at 500 characters and the type at 200', () {
      final scrubbed = ErrorScrubber.scrub(StateError('x' * 5000), null);

      expect(scrubbed.message, hasLength(500));
      expect(scrubbed.errorType.length, lessThanOrEqualTo(200));
    });

    test('a throwing toString does not defeat the report', () {
      final scrubbed = ErrorScrubber.scrub(_Unprintable(), null);

      expect(scrubbed.message, 'unprintable error');
      expect(scrubbed.errorType, '_Unprintable');
    });
  });

  group('stack', () {
    test('null stays null and an empty stack is dropped', () {
      expect(ErrorScrubber.scrub(StateError('a'), null).stack, isNull);
      expect(
        ErrorScrubber.scrub(StateError('a'), StackTrace.empty).stack,
        isNull,
      );
    });

    test('a 10 KB stack is cut at a line boundary within 4000 characters', () {
      final lines = [
        for (var i = 0; i < 300; i++)
          '#$i      Foo.bar (package:chore_app/foo.dart:$i:1)',
      ];
      final stack = StackTrace.fromString(lines.join('\n'));
      expect(stack.toString().length, greaterThan(10000));

      final scrubbed = ErrorScrubber.scrub(StateError('a'), stack);

      final cut = scrubbed.stack!;
      expect(cut.length, lessThanOrEqualTo(4000));
      expect(lines, contains(cut.split('\n').last));
      expect(stack.toString(), startsWith(cut));
    });

    test('a short stack is kept verbatim', () {
      final stack = StackTrace.fromString('#0 main (file.dart:1:1)');

      expect(ErrorScrubber.scrub(StateError('a'), stack).stack, '$stack');
    });
  });

  group('context', () {
    test('is bounded: 10 entries, keys <= 40, values <= 100', () {
      final scrubbed = ErrorScrubber.scrub(
        StateError('a'),
        null,
        context: {
          for (var i = 0; i < 15; i++) 'k$i${'x' * 60}': 'v' * 300,
        },
      );

      expect(scrubbed.context, hasLength(10));
      for (final entry in scrubbed.context.entries) {
        expect(entry.key.length, lessThanOrEqualTo(40));
        expect(entry.value.length, lessThanOrEqualTo(100));
      }
    });

    test('contextJson is null when empty and a JSON object otherwise', () {
      expect(ErrorScrubber.scrub(StateError('a'), null).contextJson, isNull);
      final scrubbed = ErrorScrubber.scrub(
        StateError('a'),
        null,
        context: {'status': 'channelError'},
      );
      expect(jsonDecode(scrubbed.contextJson!), {'status': 'channelError'});
    });
  });
}

class _Unprintable {
  @override
  String toString() => throw StateError('no');
}
