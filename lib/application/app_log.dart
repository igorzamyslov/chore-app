/// The one call every swallowed or uncaught error goes through (spec
/// `docs/specs/client-error-reporting.md` §3.3): scrub, record locally, and
/// leave the uploading to `ErrorReporter`.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/error_log_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/domain/error_scrubber.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Where [AppLog] hands a scrubbed error. Implemented by
/// [DatabaseErrorLogSink] in production and by a recording fake in tests.
// One-method seam by design: the fake in tests and the database sink in
// production are the two implementations.
// ignore: one_member_abstracts
abstract interface class ErrorLogSink {
  /// Records one occurrence of [error] from [source].
  Future<void> record({required String source, required ScrubbedError error});
}

/// Static facade every error call site uses.
///
/// Static on purpose: the call sites include `main.dart`'s global handlers
/// and a background isolate, neither of which has a `WidgetRef`. Never
/// throws, never awaits.
abstract final class AppLog {
  static ErrorLogSink? _sink;

  /// Starts routing errors to [sink]. Called from `main.dart` once the
  /// database is reachable; until then (and in unit tests) errors only reach
  /// `debugPrint`.
  // A method, not a setter: `attach`/`detach` are a pair of verbs.
  // ignore: use_setters_to_change_properties
  static void attach(ErrorLogSink sink) => _sink = sink;

  /// Stops routing errors anywhere. For tests.
  static void detach() => _sink = null;

  /// Reports [error] caught at [source], an `area.thing` identifier (lower
  /// camel case after the dot). [source] is a grouping key on the server, so
  /// it must never have data interpolated into it. [context] may only hold
  /// ids, enum names, table names and counts.
  ///
  /// Synchronous and fire-and-forget. Its own failures only `debugPrint`:
  /// routing them back through here would recurse.
  static void error(
    String source,
    Object error,
    StackTrace? stack, {
    Map<String, String>? context,
  }) {
    if (kDebugMode) {
      debugPrint('[$source] $error');
    }
    final sink = _sink;
    if (sink == null) {
      return;
    }
    try {
      final scrubbed = ErrorScrubber.scrub(error, stack, context: context);
      unawaited(
        sink
            .record(source: source, error: scrubbed)
            .catchError(
              (Object e) => debugPrint('AppLog: could not record error: $e'),
            ),
      );
    } on Object catch (e) {
      debugPrint('AppLog: could not record error: $e');
    }
  }
}

/// The production [ErrorLogSink]: stamps the app version, platform and the
/// linked household onto each error and writes it through
/// [ErrorLogRepository].
class DatabaseErrorLogSink implements ErrorLogSink {
  /// Creates a sink over [db].
  ///
  /// [appVersion] resolves `'<version>+<build>'` (cached after first use);
  /// [platform] resolves the platform string. Both are injectable so tests
  /// need no platform channel.
  DatabaseErrorLogSink(
    AppDatabase db, {
    DateTime Function()? nowUtc,
    Future<String> Function()? appVersion,
    String Function()? platform,
  }) : _db = db,
       _repository = nowUtc == null
           ? ErrorLogRepository(db)
           : ErrorLogRepository(db, nowUtc: nowUtc),
       _appVersion = appVersion ?? _packageVersion,
       _platform = platform ?? _operatingSystem;

  final AppDatabase _db;
  final ErrorLogRepository _repository;
  final Future<String> Function() _appVersion;
  final String Function() _platform;

  @override
  Future<void> record({
    required String source,
    required ScrubbedError error,
  }) async {
    // Read, never `ensureSettings`: a missing row (fresh install, or just
    // after a data reset) means "unlinked", and recording an error must not
    // be what creates the settings row.
    final settings =
        await (_db.select(_db.settings)
              ..where((tbl) => tbl.id.equals(SettingsRepository.deviceId)))
            .getSingleOrNull();
    await _repository.record(
      source: source,
      error: error,
      appVersion: await _appVersion(),
      platform: _platform(),
      householdId: settings?.syncHouseholdId,
    );
  }
}

String? _cachedVersion;

Future<String> _packageVersion() async {
  final cached = _cachedVersion;
  if (cached != null) {
    return cached;
  }
  final info = await PackageInfo.fromPlatform();
  return _cachedVersion = '${info.version}+${info.buildNumber}';
}

String _operatingSystem() {
  final text = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  return text.length <= 100 ? text : text.substring(0, 100);
}
