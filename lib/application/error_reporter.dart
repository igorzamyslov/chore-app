/// Uploads the local error buffer to the server (spec
/// `docs/specs/client-error-reporting.md` §4).
///
/// Editing this file triggers the live DB workflow (`.github/workflows/
/// db.yml`): the real [SupabaseErrorReportTransport] is exercised against a
/// local Supabase stack by `test_live/client_errors_live_test.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:chore_app/data/repositories/error_log_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// The one server operation the reporter needs. A seam so tests can fake the
/// network; production is [SupabaseErrorReportTransport].
// One-method seam by design (see the spec's unit table).
// ignore: one_member_abstracts
abstract interface class ErrorReportTransport {
  /// Inserts [rows] (snake_case, spec §4.2) into the server's
  /// `client_errors`, skipping any whose `id` already exists. Throws on any
  /// failure.
  Future<void> insertErrors(List<Map<String, Object?>> rows);
}

/// The production [ErrorReportTransport] over `Supabase.instance.client`.
class SupabaseErrorReportTransport implements ErrorReportTransport {
  /// Creates the transport. `Supabase.initialize()` must have already run.
  const SupabaseErrorReportTransport();

  @override
  Future<void> insertErrors(List<Map<String, Object?>> rows) async {
    // `ignoreDuplicates` (ON CONFLICT DO NOTHING), NEVER a plain upsert: the
    // table grants `authenticated` INSERT only, and Postgres checks UPDATE
    // privilege for an ON CONFLICT DO UPDATE at plan time whether or not a
    // conflict happens, so a plain upsert is rejected 42501 outright (the
    // same lesson as `members`, see `SupabaseHouseholdGateway.
    // uploadHouseholdData`). No `.select()` either: there is no SELECT
    // grant. `user_id` and `received_at` are deliberately not sent -- the
    // server fills both.
    await supabase.Supabase.instance.client
        .from('client_errors')
        .upsert(rows, onConflict: 'id', ignoreDuplicates: true);
  }
}

/// The four conditions that must all hold before anything is uploaded (spec
/// §4.2 step 2).
@immutable
class ErrorReportGate {
  /// Creates a gate snapshot.
  const ErrorReportGate({
    required this.supabaseConfigured,
    required this.signedIn,
    required this.linked,
    required this.enabled,
  });

  /// Whether this build talks to a Supabase backend at all.
  final bool supabaseConfigured;

  /// Whether a user is signed in.
  final bool signedIn;

  /// Whether this device is linked to a household.
  final bool linked;

  /// Whether the user's "Send error reports" switch is on.
  final bool enabled;

  /// Whether an upload may proceed.
  bool get open => supabaseConfigured && signedIn && linked && enabled;
}

/// Uploads pending rows of [ErrorLogRepository] through [ErrorReportTransport]
/// when triggered and [ErrorReportGate.open].
class ErrorReporter {
  /// Creates a reporter.
  ///
  /// [gate] is evaluated on every [flush] (and before every batch), so a
  /// sign-out or switch-off takes effect on the very next trigger. [nowUtc]
  /// is injectable for a fixed clock in tests.
  ErrorReporter({
    required this.repository,
    required this.transport,
    required this.gate,
    this.nowUtc = _defaultNowUtc,
  });

  /// Rows per request: `ErrorLogRepository.pending`'s default limit.
  static const int batchSize = 50;

  /// Requests per flush, so one flush uploads at most
  /// `batchSize * maxBatches` = 200 rows.
  static const int maxBatches = 4;

  /// The buffer to read pending rows from.
  final ErrorLogRepository repository;

  /// The server upload.
  final ErrorReportTransport transport;

  /// Reads the current gate state.
  final ErrorReportGate Function() gate;

  /// Returns the current UTC time, stamped on rows as `uploadedAt`.
  final DateTime Function() nowUtc;

  bool _flushing = false;

  /// Uploads pending rows if allowed. Never throws.
  ///
  /// A flush already in progress makes this a no-op. Any exception stops the
  /// flush with the remaining rows still pending for the next trigger; it is
  /// only `debugPrint`ed, never routed through `AppLog` -- an upload failure
  /// that recorded an error that then failed to upload would feed itself.
  Future<void> flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      for (var batch = 0; batch < maxBatches; batch++) {
        if (!gate().open) {
          return;
        }
        final rows = await repository.pending();
        if (rows.isEmpty) {
          return;
        }
        await transport.insertErrors([
          for (final row in rows)
            {
              'id': row.id,
              'source': row.source,
              'error_type': row.errorType,
              'message': row.message,
              'stack': row.stack,
              'context': row.context == null ? null : jsonDecode(row.context!),
              'count': row.count,
              'first_seen_at': row.firstSeenAt,
              'last_seen_at': row.lastSeenAt,
              'app_version': row.appVersion,
              'platform': row.platform,
              'household_id': row.householdId,
            },
        ]);
        await repository.markUploaded([for (final r in rows) r.id], nowUtc());
      }
    } on Object catch (error) {
      debugPrint('ErrorReporter.flush failed (will retry later): $error');
    } finally {
      _flushing = false;
    }
  }
}

DateTime _defaultNowUtc() => DateTime.now().toUtc();
