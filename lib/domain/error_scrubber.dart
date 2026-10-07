/// The privacy boundary for client error reporting (spec
/// `docs/specs/client-error-reporting.md` §2): turns any caught error into a
/// [ScrubbedError] that is safe to store and upload.
///
/// No user content may leave the device -- chore titles, member names,
/// category names, shopping items, household names, emails, invite codes.
/// Error messages from PostgREST/Postgres/our own exceptions can embed row
/// values, so this is deliberately LOSSY: it would rather drop a useful word
/// than leak a name. Pure: no I/O, no clock, no platform access.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

/// The scrubbed, bounded form of one reported error.
class ScrubbedError {
  /// Creates a scrubbed error. Only [ErrorScrubber.scrub] should build one.
  const ScrubbedError({
    required this.errorType,
    required this.message,
    required this.stack,
    required this.context,
  });

  /// The error's runtime type name, at most 200 characters.
  final String errorType;

  /// The scrubbed message, at most 500 characters.
  final String message;

  /// The stack trace, truncated at a line boundary to at most 4000
  /// characters, or `null` when none was available.
  final String? stack;

  /// The call site's context: at most 10 entries, keys at most 40 and values
  /// at most 100 characters. Call sites should only put ids, enum names,
  /// table names and counts into it; as a second line of defence every value
  /// also goes through the same message rules as the error text (emails,
  /// quoted spans and long digit runs are replaced; UUIDs are kept).
  final Map<String, String> context;

  /// [context] as a JSON object string, or `null` when it is empty.
  String? get contextJson => context.isEmpty ? null : jsonEncode(context);
}

/// Pure error scrubber. See the library comment.
abstract final class ErrorScrubber {
  static const int _maxType = 200;
  static const int _maxMessage = 500;
  static const int _maxStack = 4000;
  static const int _maxContextEntries = 10;
  static const int _maxContextKey = 40;
  static const int _maxContextValue = 100;

  static final RegExp _uuid = RegExp(
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    '[0-9a-fA-F]{12}',
  );
  static final RegExp _email = RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+');
  static final RegExp _quoted = RegExp(
    r'''\x27[^\x27]*\x27|"[^"]*"|«[^»]*»|“[^”]*”''',
  );
  static final RegExp _longDigits = RegExp(r'\d{6,}');
  // Private-use sentinels around a UUID's index. They contain no quote,
  // `@`, whitespace or 6-digit run, so every rule below leaves them alone.
  static final RegExp _placeholder = RegExp(r'\uE000(\d+)\uE001');

  /// Scrubs [error] (and [stack], and the call site's [context]).
  static ScrubbedError scrub(
    Object error,
    StackTrace? stack, {
    Map<String, String>? context,
  }) {
    return ScrubbedError(
      errorType: _cap(error.runtimeType.toString(), _maxType),
      message: _cap(_message(error), _maxMessage),
      stack: _stack(stack),
      context: _context(context),
    );
  }

  static String _message(Object error) {
    // `details`/`message`/`hint` are NOT included for Postgrest: they carry
    // row values. The code alone ("23505", "42501") is what is actionable.
    if (error is PostgrestException) {
      return 'postgrest code=${error.code}';
    }
    if (error is AuthException) {
      return 'auth status=${error.statusCode} code=${error.code}';
    }
    // `FormatException.toString` appends the offending source text ("Invalid
    // JSON ... at character 12 <the input>"), which can be a chore title or
    // a pasted invite code: keep the parser's own `message` only.
    if (error is FormatException) {
      return _scrubText(error.message);
    }
    String raw;
    try {
      raw = error.toString();
    } on Object {
      // A throwing `toString` must not defeat the report.
      return 'unprintable error';
    }
    return _scrubText(raw);
  }

  /// The message rules shared by error messages and call-site context
  /// values: drop SQL statements, then replace emails, quoted spans and long
  /// digit runs, keeping UUIDs.
  static String _scrubText(String input) {
    var raw = input;
    // sqlite3's `SqliteException.toString` appends the failing SQL and its
    // bound parameters UNQUOTED ("parameters: Clean Anna's room, ..."), so
    // the quote rule below cannot catch them. Drop everything from that
    // marker on -- the result code and message before it are what is
    // actionable. Matched on the text, not the type, because drift_flutter
    // runs the database in a background isolate and the exception usually
    // arrives wrapped (`DriftRemoteException`), carrying the same text.
    final statement = raw.indexOf('Causing statement');
    if (statement >= 0) {
      raw = raw.substring(0, statement).trimRight();
    }
    // UUIDs are ids, not content, and are what makes a report actionable:
    // lift them out so the digit rule cannot mangle them, put them back
    // after.
    final uuids = <String>[];
    var text = raw.replaceAllMapped(_uuid, (match) {
      uuids.add(match.group(0)!);
      return '\uE000${uuids.length - 1}\uE001';
    });
    text = text
        .replaceAll(_email, '<email>')
        .replaceAll(_quoted, '<str>')
        .replaceAll(_longDigits, '<num>');
    return text.replaceAllMapped(_placeholder, (match) {
      final index = int.parse(match.group(1)!);
      return index < uuids.length ? uuids[index] : '';
    });
  }

  static String? _stack(StackTrace? stack) {
    if (stack == null) {
      return null;
    }
    final text = stack.toString();
    if (text.isEmpty) {
      return null;
    }
    if (text.length <= _maxStack) {
      return text;
    }
    final head = text.substring(0, _maxStack);
    final cut = head.lastIndexOf('\n');
    return cut > 0 ? head.substring(0, cut) : head;
  }

  static Map<String, String> _context(Map<String, String>? context) {
    if (context == null || context.isEmpty) {
      return const {};
    }
    return {
      for (final entry in context.entries.take(_maxContextEntries))
        _cap(entry.key, _maxContextKey): _cap(
          _scrubText(entry.value),
          _maxContextValue,
        ),
    };
  }

  static String _cap(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
