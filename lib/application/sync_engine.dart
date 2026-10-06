/// The P3 ongoing sync engine (spec `docs/specs/sync-backend.md` §8): the
/// seam that keeps two linked devices converging during daily use, on top
/// of the P2 bootstrap seam (`HouseholdGateway`,
/// `lib/application/household_gateway.dart`).
///
/// [SyncEngine] is the app-facing interface; [NoopSyncEngine] is what
/// `syncEngineProvider` (`lib/app/providers.dart`) returns whenever Supabase
/// is unconfigured OR the device is unlinked -- which is every widget test
/// and E2E run, so the debounced-push timer and the realtime subscription
/// this library sets up NEVER exist in the offline suite. [SyncTransport] is
/// the narrower network seam [SupabaseSyncEngine] depends on instead of
/// touching `Supabase.instance` directly (spec §8.4): tests substitute a
/// fake transport and exercise the engine's LWW/flag-clearing/cursor logic
/// against a real in-memory `AppDatabase`, with no live Supabase involved.
/// [SupabaseSyncTransport] is the only place that ever touches
/// `Supabase.instance` (including the realtime channel setup, spec §8.3d) --
/// isolated here so tests never construct it.
library;

import 'dart:async';

import 'package:chore_app/application/app_log.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/sync_repository.dart';
import 'package:chore_app/data/sync/row_mappers.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// The tables the FK order below is derived from (spec §8.3: "per table in
/// FK order") -- parents before children, both for push (upsert order) and
/// pull (apply order, all in one local transaction).
const List<String> syncedTablesInFkOrder = [
  'households',
  'members',
  'categories',
  'chores',
  'chore_assignees',
  'chore_occurrences',
  'shopping_items',
];

/// How many rows one server read asks for (spec §8.3 amendment
/// 2026-10-06, technical review #2). PostgREST silently truncates EVERY
/// response at its `max_rows` setting -- 1000 in `supabase/config.toml` and
/// on the hosted project -- with no error and no marker, so a bare
/// `select()` over a household's year of `chore_occurrences` returned the
/// first thousand rows in heap order and dropped the rest, and the cursor
/// then advanced past them forever. Every full-table read ([SyncTransport
/// .pullTable] and `HouseholdGateway.downloadHousehold`) therefore asks for
/// exactly this many rows at a time, ordered by `updated_at` then primary
/// key, and keeps going until a page comes back shorter than this. Equal to
/// `max_rows` on purpose: a larger value would be truncated to it anyway,
/// and the short-page stop condition would then never fire.
const int syncPageSize = 1000;

/// The columns that, after `updated_at`, make a page order total for
/// [table] -- its primary key. `chore_assignees` is keyed by
/// `(chore_id, member_id)` and has no `id`.
List<String> pageOrderKeyColumns(String table) =>
    table == 'chore_assignees' ? const ['chore_id', 'member_id'] : const ['id'];

/// App-facing sync engine seam (spec §8.2): [pushDirty] upserts every
/// locally-dirty row; [pullSince] fetches and applies everything the server
/// has changed since the last pull; [start]/[stop] arm/disarm the ongoing
/// triggers (debounced push-on-write, pull-on-resume, realtime) -- both
/// idempotent.
abstract class SyncEngine {
  /// Pushes every dirty row to the server, in FK order, then clears the
  /// flag on exactly the rows that were pushed (spec §8.3). Never throws --
  /// every failure is swallowed into a silent retry-later.
  Future<void> pushDirty();

  /// Fetches server `now()` and every row changed since the last pull,
  /// applies them locally under the LWW rule, and (only after that
  /// transaction commits) advances the pull cursor (spec §8.3). Never
  /// throws -- every failure is swallowed into a silent retry-later.
  Future<void> pullSince();

  /// Begins the ongoing triggers: an immediate [pushDirty] (which itself
  /// pulls afterward on success -- this is also what recovers rows left
  /// dirty from a prior session that never got pushed, e.g. after a cold
  /// start while linked), a listener that schedules a debounced
  /// [pushDirty] on any local write to a synced table, and a realtime
  /// subscription that schedules a [pullSince] on any server-side change
  /// (spec §8.3). Idempotent -- a second call while already started is a
  /// no-op.
  void start();

  /// Disarms everything [start] armed (timers, subscriptions). Idempotent.
  void stop();

  /// A USER-INITIATED sync (pull-to-refresh, spec
  /// `docs/specs/sync-freshness.md` §2.3): pushes then pulls, and reports
  /// whether it actually worked -- `true` on success, `false` if either half
  /// failed.
  ///
  /// Deliberately separate from [pushDirty]/[pullSince], whose contract is
  /// to swallow every error into a silent retry-later (spec §8.3). That is
  /// right for the background triggers, but it made the refresh indicator
  /// incapable of ever reporting failure: it spun and stopped identically
  /// whether the sync worked or the phone was in airplane mode. Found by the
  /// 2026-08-07 persona walkthrough, against §2.3's own promise of a failure
  /// snackbar.
  Future<bool> refreshNow();

  /// Suspends the periodic safety-net poll while the app is backgrounded
  /// (spec `docs/specs/sync-freshness.md` §2.2) -- a backgrounded app must
  /// not hold a network wakeup every minute. Everything else [start] armed
  /// (the write listener, the realtime subscription) stays live, because
  /// the OS, not this engine, decides whether those still deliver.
  /// Idempotent.
  void pauseBackgroundWork();

  /// Resumes what [pauseBackgroundWork] suspended. Idempotent, and a no-op
  /// when the engine was never [start]ed.
  void resumeBackgroundWork();
}

/// The inert [SyncEngine] used whenever Supabase is unconfigured or the
/// device is unlinked (`syncEngineProvider`, `lib/app/providers.dart`) --
/// every method is a true no-op, so no timer or subscription this library
/// defines ever exists in the fully-offline test suite.
class NoopSyncEngine implements SyncEngine {
  /// Creates the no-op engine.
  const NoopSyncEngine();

  @override
  Future<void> pushDirty() async {}

  @override
  Future<void> pullSince() async {}

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<bool> refreshNow() async => true;

  @override
  void pauseBackgroundWork() {}

  @override
  void resumeBackgroundWork() {}
}

/// The narrow network seam [SupabaseSyncEngine] depends on (spec §8.4)
/// instead of touching `Supabase.instance` directly -- lets tests substitute
/// a fake and exercise the engine's push/pull/LWW logic against a real
/// in-memory `AppDatabase`, with no live Supabase involved.
///
/// Row shapes are plain snake_case maps (mirroring the wire format) rather
/// than typed drift rows: the engine itself owns converting to/from typed
/// rows via the shared mappers in `lib/data/sync/row_mappers.dart`, so this
/// seam stays a thin, mechanical "move bytes" boundary.
abstract class SyncTransport {
  /// The RPC `server_now()` -- the pull cursor's clock source (spec §8.3:
  /// never the device clock).
  Future<DateTime> serverNow();

  /// ONE PAGE of the rows of [table] belonging to [householdId] with
  /// `updated_at >` [since], or of every row if [since] is `null` (this
  /// device's first pull): rows `[offset, offset + limit)` of the matching
  /// set ordered by `updated_at`, then primary key ([pageOrderKeyColumns]).
  /// The engine keeps calling with a growing [offset] until a page comes
  /// back shorter than [limit] (see [syncPageSize]). RLS (or the fake)
  /// scopes access to [householdId]'s own rows.
  Future<List<Map<String, Object?>>> pullTable(
    String table, {
    required String householdId,
    required DateTime? since,
    required int offset,
    required int limit,
  });

  /// Upserts [rows] into [table] -- the ordinary push path for every synced
  /// table except `households`/`members`, whose grants forbid a literal
  /// upsert (see [updateHousehold]/[insertMembersIgnoringConflicts] and
  /// `HouseholdGateway.uploadHouseholdData`'s doc comment for the reason).
  /// A no-op if [rows] is empty.
  Future<void> upsertRows(
    String table,
    List<Map<String, Object?>> rows, {
    String? onConflict,
  });

  /// Members-only: insert-with-ignore (`ON CONFLICT DO NOTHING`) -- the
  /// insert half of the members push (spec §8.3). A no-op if [rows] is
  /// empty.
  Future<void> insertMembersIgnoringConflicts(List<Map<String, Object?>> rows);

  /// Members-only: updates the granted columns (name, color, role,
  /// deleted_at) of one already-existing member row -- the update half of
  /// the members push (spec §8.3), needed because
  /// [insertMembersIgnoringConflicts] alone never touches an existing row's
  /// changed fields.
  Future<void> updateMemberGrantedColumns(
    String id,
    Map<String, Object?> columns,
  );

  /// Households-only: updates one already-existing household row's
  /// columns. Never an upsert: the server grants only `select, update` on
  /// `households` (no `insert`), and Postgres checks INSERT privilege on an
  /// upsert's `INSERT ... ON CONFLICT DO UPDATE` regardless of whether a
  /// conflict actually occurs -- mirroring the members grants note above,
  /// this table has the same constraint even though spec §8.3 only spells
  /// it out for members.
  Future<void> updateHousehold(String id, Map<String, Object?> columns);

  /// Sets `deleted_at` to [deletedAt] on the [table] row(s) matching
  /// [match] (column to value: `{'id': ..., 'status': 'pending'}` for an
  /// occurrence, `{'chore_id': ..., 'member_id': ...}` for an assignee) --
  /// the push half of a local HARD delete (spec `docs/specs/sync-backend.md`
  /// §8.6.3). Every entry of [match] is a filter: a tombstone whose row no
  /// longer matches (an occurrence completed elsewhere since) must match
  /// nothing.
  ///
  /// An UPDATE, never an upsert: a tombstone carries no full row. Matching
  /// zero rows (the row was never pushed) is success, not an error.
  Future<void> markDeleted(
    String table,
    Map<String, Object?> match,
    String deletedAt,
  );

  /// One realtime subscription for [householdId]: emits an event (payload
  /// ignored -- data always comes from [pullTable], spec §8.3d) on any
  /// change to a row scoped to [householdId], across every synced table.
  /// The stream closes (no more events) once nothing is listening.
  Stream<void> householdChanges(String householdId);

  /// Whether the signed-in account still has a live claimed membership in
  /// [householdId] (spec `docs/specs/household-lifecycle.md` §3.5).
  ///
  /// This is the revocation signal: RLS answers a revoked device with
  /// EMPTY RESULT SETS rather than errors, so an ordinary pull is
  /// indistinguishable from "nothing changed" and the device would look
  /// healthy forever.
  ///
  /// Called on EVERY pull -- the 60s foreground poll, every realtime
  /// event, and after every successful push (spec §8.3c) -- so this is
  /// one extra round trip per pull, not a one-off check. Whoever next
  /// sizes the sync budget (poll interval, realtime fan-out) should not
  /// have to discover that by reading every `_pullSinceInner` call site.
  Future<bool> hasMembership(String householdId);
}

/// The production [SyncEngine]: LWW push/pull over a [SyncTransport], with
/// a debounced push-on-write trigger, a realtime pull trigger, and a
/// periodic foreground poll that unconditionally pulls AND retries any
/// still-dirty push (spec §8.3, extended by B-6 -- see [_pollTick]).
class SupabaseSyncEngine implements SyncEngine {
  /// Creates an engine for [householdId], reading/writing [db] and talking
  /// to the server through [transport]. [settings] is where the pull cursor
  /// (`syncLastPulledAt`) lives. [pushDebounce] defaults to the spec's ~2s;
  /// tests pass a shorter value so debounce tests don't need to wait 2 real
  /// seconds.
  SupabaseSyncEngine({
    required this.db,
    required this.transport,
    required this.settings,
    required this.householdId,
    this.pushDebounce = const Duration(seconds: 2),
    this.pollInterval = const Duration(seconds: 60),
    this.realtimeEchoWindow = const Duration(seconds: 1),
    this.clock = const Clock(),
  }) : _sync = SyncRepository(db);

  /// The local database this engine reads from and writes to.
  final AppDatabase db;

  /// The network seam (spec §8.4).
  final SyncTransport transport;

  /// Where the pull cursor (`syncLastPulledAt`) is read from and written to.
  final SettingsRepository settings;

  /// The household this engine is linked to.
  final String householdId;

  /// How long [start]'s write-listener waits after the last local write
  /// before calling [pushDirty] (spec §8.3: "debounced ~2s").
  final Duration pushDebounce;

  /// How often the foreground safety-net poll ticks (spec
  /// `docs/specs/sync-freshness.md` §2.2: 60s). Each tick runs [_pollTick]
  /// (extended by B-6, `docs/backlog.md`, from a bare [pullSince] to also
  /// retry any row a prior debounced push failed to send) -- see
  /// [_pollTick]'s doc comment for why the pull half is unconditional even
  /// when the push half fails. Realtime is still the fast path for pull;
  /// this only bounds worst-case staleness, for both directions, when
  /// realtime is degraded in a way the re-subscribe trigger cannot see.
  /// Tests pass a shorter value.
  final Duration pollInterval;

  /// How long after our own successful push a realtime `householdChanges`
  /// event is treated as the server echoing the rows we just wrote, and
  /// dropped (technical review 2026-10-06 #17). The push's own follow-up
  /// pull (spec §8.3c) already fetched those rows; the echo used to start a
  /// SECOND pull of the same data, and with the start-time push racing the
  /// `subscribed` tick, two interleaved pulls could move the cursor
  /// backwards. A genuine other-device change inside this window is
  /// caught by the next poll tick at the latest (`pollInterval`). Tests
  /// pass a shorter value.
  final Duration realtimeEchoWindow;

  /// The DEVICE clock, used for the echo window and for tombstone stamps
  /// -- never for the pull cursor, which is server time (spec §8.3).
  /// Injected so tests can pin it.
  final Clock clock;

  final SyncRepository _sync;

  /// The pull currently running, if any (technical review 2026-10-06 #17):
  /// [pullSince] and [refreshNow] join it instead of starting a second one,
  /// so two pulls can never interleave and race each other's cursor write.
  Future<bool>? _inFlightPull;

  /// Until when realtime events are dropped as our own echo -- see
  /// [realtimeEchoWindow].
  DateTime? _ignoreRealtimeUntil;

  StreamSubscription<Set<TableUpdate>>? _writeSubscription;
  StreamSubscription<void>? _realtimeSubscription;
  Timer? _pushTimer;
  Timer? _pollTimer;
  bool _started = false;
  bool _foreground = true;

  @override
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _writeSubscription = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            db.households,
            db.members,
            db.categories,
            db.chores,
            db.choreAssignees,
            db.choreOccurrences,
            db.shoppingItems,
            db.syncTombstones,
          ]),
        )
        .listen((_) => _scheduleDebouncedPush());
    // Every event on this stream means "something may have changed on the
    // server, or we may have MISSED something that did" -- the transport
    // emits both on a live postgres_changes payload and on every
    // (re)subscribe (spec `docs/specs/sync-freshness.md` §2.1). Mapping
    // both to the same pull is what closes the gap a dropped-and-restored
    // socket used to leave open indefinitely.
    _realtimeSubscription = transport.householdChanges(householdId).listen((
      _,
    ) {
      final ignoreUntil = _ignoreRealtimeUntil;
      if (ignoreUntil != null && clock.now().isBefore(ignoreUntil)) {
        return;
      }
      unawaited(pullSince());
    });
    // Push on start (recovers rows left dirty from a prior session that
    // never got pushed -- e.g. a cold start while linked), which itself
    // pulls afterward on success (spec §8.3a/c): this covers "pull on
    // start" too, so a bare pullSince() call here is not enough on its
    // own. _armPoll() below repeats a push-then-always-pull periodically
    // while foregrounded (B-6, see _pollTick), so a row that fails to
    // push here, or via the debounced write-listener, keeps getting
    // retried instead of waiting for the next local write or resume --
    // and the pull half of the poll keeps running even if that retry
    // itself fails again.
    unawaited(pushDirty());
    _armPoll();
  }

  @override
  void stop() {
    _started = false;
    _pushTimer?.cancel();
    _pushTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_writeSubscription?.cancel());
    _writeSubscription = null;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
  }

  @override
  void pauseBackgroundWork() {
    _foreground = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void resumeBackgroundWork() {
    _foreground = true;
    _armPoll();
  }

  /// The poll timer's own tick (B-6, `docs/backlog.md`): pushes every
  /// dirty row, swallowing any failure exactly like [pushDirty]'s own
  /// try/catch (spec §8.3's failure posture), and then ALWAYS pulls --
  /// regardless of whether the push succeeded.
  ///
  /// Deliberately NOT `await pushDirty(); await pullSince();`: [pushDirty]
  /// already pulls once internally on a successful push (spec §8.3c), so
  /// that would double-pull on every tick where nothing was wrong.
  ///
  /// Deliberately NOT a bare `await pushDirty()` either: [pushDirty]
  /// returns early on failure and never reaches its own pull (see its
  /// body) -- pointing the poll timer straight at it would make the
  /// periodic pull conditional on the push succeeding. A single
  /// persistently-rejected row (a `42501` from the column-restricted
  /// `members`/`households` grants, or a row referencing something
  /// deleted elsewhere) would then turn the 60s freshness bound
  /// `docs/specs/sync-freshness.md` §2.2 exists to guarantee into a
  /// total, silent pull blackout for this device -- while the other
  /// household member's changes keep arriving unseen. This method's own
  /// try/catch exists specifically so a push failure can never prevent
  /// the pull that follows it.
  Future<void> _pollTick() async {
    try {
      await _pushAll();
    } on Object catch (error, stackTrace) {
      _logFailure('pushDirty', error, stackTrace);
    }
    await pullSince();
  }

  /// (Re)arms the foreground safety-net poll, but only while the engine is
  /// started AND the app is foregrounded -- so a resume that arrives before
  /// the engine exists, or after it was stopped, never leaves a stray timer
  /// behind. Ticks call [_pollTick] (B-6, `docs/backlog.md`), not a bare
  /// [pullSince]: see [_pollTick]'s own doc comment for why it must push
  /// too, and why that push must never be allowed to block the pull.
  void _armPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_started || !_foreground) {
      return;
    }
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_pollTick()));
  }

  void _scheduleDebouncedPush() {
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () => unawaited(pushDirty()));
  }

  /// Every table's push, in FK order (spec §8.3) -- THROWS on failure.
  /// [pushDirty] swallows that; [refreshNow] reports it. Returns whether
  /// anything at all was sent, which is what opens the realtime echo
  /// window (see [realtimeEchoWindow]): a push with nothing to send
  /// produces no server event to ignore.
  Future<bool> _pushAll() async {
    var pushedAny = false;
    pushedAny |= await _pushHouseholds();
    pushedAny |= await _pushMembers();
    pushedAny |= await _pushCategories();
    pushedAny |= await _pushChores();
    pushedAny |= await _pushChoreAssignees();
    pushedAny |= await _pushChoreOccurrences();
    pushedAny |= await _pushShoppingItems();
    pushedAny |= await _pushTombstones();
    if (pushedAny) {
      _ignoreRealtimeUntil = clock.now().add(realtimeEchoWindow);
    }
    return pushedAny;
  }

  @override
  Future<bool> refreshNow() async {
    try {
      await _pushAll();
      final revoked = await _pull();
      // A pull that discovers revocation is not a success from the
      // caller's point of view: this is a deliberate pull-to-refresh, and
      // "true" here would tell the user "yes, working" at the exact
      // moment their device is being cut off from the household -- right
      // before the refresh affordance itself disappears because it is
      // gated on linked state.
      return !revoked;
    } on Object catch (error, stackTrace) {
      _logFailure('refreshNow', error, stackTrace);
      return false;
    }
  }

  @override
  Future<void> pushDirty() async {
    try {
      await _pushAll();
    } on Object catch (error, stackTrace) {
      // Catches `Error` subclasses too, not just `Exception` -- spec
      // §8.3's "every engine error is swallowed" is read literally here:
      // an uncaught `Error` (e.g. from an unexpected server response
      // shape) would otherwise propagate to the zone and could be killed
      // silently, with no debug log at all.
      _logFailure('pushDirty', error, stackTrace);
      return;
    }
    // Pull after every successful push (spec §8.3c).
    await pullSince();
  }

  @override
  Future<void> pullSince() async {
    try {
      await _pull();
    } on Object catch (error, stackTrace) {
      _logFailure('pullSince', error, stackTrace);
    }
  }

  /// Runs [_pullSinceInner], or joins the one already running (technical
  /// review 2026-10-06 #17). `whenComplete` clears the slot before the
  /// shared future completes, so a caller that starts a pull AFTER this
  /// one finished gets a fresh pull, while every caller that arrived during
  /// it shares this one's result -- including its error, which each
  /// caller's own try/catch then handles.
  Future<bool> _pull() => _inFlightPull ??= _pullSinceInner().whenComplete(
    () => _inFlightPull = null,
  );

  /// The pull itself -- THROWS on failure. [pullSince] swallows that;
  /// [refreshNow] reports it. Returns whether this pull discovered
  /// revocation (and therefore short-circuited before fetching any table)
  /// -- [pullSince] ignores it, [refreshNow] folds it into its own return
  /// value so a pull-to-refresh that finds the device cut off does not
  /// report success.
  Future<bool> _pullSinceInner() async {
    // Revocation probe (spec docs/specs/household-lifecycle.md §3.5).
    // While linked, a missing membership IS the signal that this device
    // was removed from its household -- RLS stops returning rows rather
    // than erroring, so a pull would otherwise look like "no changes"
    // forever.
    //
    // This deliberately overrides sync-backend.md §8.3's swallow-all-
    // errors posture. §8.3 rests on the local DB always being consistent
    // with the household; that argument stops holding the moment this
    // device is cut off from it. Do not "fix" this back into silence.
    if (!await transport.hasMembership(householdId)) {
      await settings.setMembershipRevoked();
      await settings.clearSyncLink();
      return true;
    }

    final current = await settings.ensureSettings();
    final since = current.syncLastPulledAt == null
        ? null
        : DateTime.parse(current.syncLastPulledAt!);
    // Server now() FIRST (spec §8.3): a row touched between this call and
    // the per-table reads below ends up with `updated_at` AFTER this
    // value, so the NEXT pull (cursor == this value) finds it again --
    // a possible harmless re-apply, never a missed row.
    final serverNow = await transport.serverNow();

    final householdRows = await _pullAllPages('households', since);
    final memberRows = await _pullAllPages('members', since);
    final categoryRows = await _pullAllPages('categories', since);
    final choreRows = await _pullAllPages('chores', since);
    final assigneeRows = await _pullAllPages('chore_assignees', since);
    final occurrenceRows = await _pullAllPages('chore_occurrences', since);
    final itemRows = await _pullAllPages('shopping_items', since);

    // Apply in FK order, in ONE local transaction (spec §8.3).
    await db.transaction(() async {
      for (final row in householdRows) {
        await _sync.applyPulledHousehold(householdFromRow(row));
      }
      for (final row in memberRows) {
        await _sync.applyPulledMember(memberFromRow(row));
      }
      for (final row in categoryRows) {
        await _sync.applyPulledCategory(categoryFromRow(row));
      }
      for (final row in choreRows) {
        await _sync.applyPulledChore(choreFromRow(row));
      }
      // Assignees are applied PER CHORE as one LWW value (spec §8.3
      // amendment 2026-10-06): live rows and tombstones (§8.6.5) for a
      // chore are grouped and handed over together, so a dirty local chore
      // keeps its whole list and a clean one takes the pulled list whole.
      final liveByChore = <String, List<ChoreAssignee>>{};
      final tombstonedByChore = <String, List<String>>{};
      for (final row in assigneeRows) {
        final choreId = row['chore_id']! as String;
        if (row['deleted_at'] != null) {
          tombstonedByChore
              .putIfAbsent(choreId, () => [])
              .add(row['member_id']! as String);
        } else {
          liveByChore
              .putIfAbsent(choreId, () => [])
              .add(choreAssigneeFromRow(row));
        }
      }
      for (final choreId in {...liveByChore.keys, ...tombstonedByChore.keys}) {
        await _sync.applyPulledAssigneeSet(
          choreId,
          live: liveByChore[choreId] ?? const [],
          tombstonedMemberIds: tombstonedByChore[choreId] ?? const [],
        );
      }
      for (final row in occurrenceRows) {
        if (row['deleted_at'] != null) {
          await _sync.applyPulledOccurrenceDeletion(row['id']! as String);
        } else {
          await _sync.applyPulledChoreOccurrence(choreOccurrenceFromRow(row));
        }
      }
      for (final row in itemRows) {
        await _sync.applyPulledShoppingItem(shoppingItemFromRow(row));
      }
      // Ghost repair (spec §8.6.6): last, so it sees the final applied
      // state. Records tombstones for what it deletes; they ride the next
      // push.
      await _sync.repairGhostOccurrences(
        householdId,
        clock.now().toUtc().toIso8601String(),
      );
    });

    // Cursor stored only after the transaction above commits (spec §8.3).
    await settings.setSyncLastPulledAt(serverNow);
    return false;
  }

  /// Every matching row of [table], fetched [syncPageSize] at a time until
  /// a short page (see [syncPageSize] for why). Throws like any other pull
  /// step: a failure on any page fails the whole pull, so the cursor never
  /// advances past rows that were not fetched.
  Future<List<Map<String, Object?>>> _pullAllPages(
    String table,
    DateTime? since,
  ) async {
    final rows = <Map<String, Object?>>[];
    var offset = 0;
    while (true) {
      final page = await transport.pullTable(
        table,
        householdId: householdId,
        since: since,
        offset: offset,
        limit: syncPageSize,
      );
      rows.addAll(page);
      if (page.length < syncPageSize) {
        return rows;
      }
      offset += syncPageSize;
    }
  }

  /// Households-only push (spec §8.3's grants note applied to `households`
  /// too -- see [SyncTransport.updateHousehold]'s doc comment): a plain
  /// UPDATE per dirty row, never an upsert.
  Future<bool> _pushHouseholds() async {
    final dirty = await _sync.dirtyHouseholds();
    for (final household in dirty) {
      await transport.updateHousehold(household.id, householdRow(household));
      await _sync.clearHouseholdDirty(household.id, household.updatedAt);
    }
    return dirty.isNotEmpty;
  }

  /// Members-only push (spec §8.3): insert-with-ignore for every dirty row
  /// (covers brand-new members), THEN a granted-columns-only update for
  /// every dirty row (covers a changed name/color/role/deleted_at on an
  /// already-existing member, which the insert-ignore step alone would
  /// silently skip). `deleted_at` travels here too (spec
  /// `docs/feedback/2026-08-01-ux-audit.md` A1) -- it's one of the four
  /// granted columns (name, color, role, deleted_at), so a local soft
  /// delete (`MemberService.deleteMember`) propagates as a tombstone
  /// exactly like every other field change.
  Future<bool> _pushMembers() async {
    final dirty = await _sync.dirtyMembers();
    if (dirty.isEmpty) {
      return false;
    }
    await transport.insertMembersIgnoringConflicts([
      for (final member in dirty) memberRow(member),
    ]);
    for (final member in dirty) {
      await transport.updateMemberGrantedColumns(member.id, {
        'name': member.name,
        'color': member.color,
        'role': member.role.name,
        'deleted_at': member.deletedAt,
      });
      await _sync.clearMemberDirty(member.id, member.updatedAt);
    }
    return true;
  }

  Future<bool> _pushCategories() async {
    final dirty = await _sync.dirtyCategories();
    if (dirty.isEmpty) {
      return false;
    }
    await transport.upsertRows('categories', [
      for (final category in dirty) categoryRow(category),
    ]);
    for (final category in dirty) {
      await _sync.clearCategoryDirty(category.id, category.updatedAt);
    }
    return true;
  }

  Future<bool> _pushChores() async {
    final dirty = await _sync.dirtyChores();
    if (dirty.isEmpty) {
      return false;
    }
    await transport.upsertRows('chores', [
      for (final chore in dirty) choreRow(chore),
    ]);
    for (final chore in dirty) {
      await _sync.clearChoreDirty(chore.id, chore.updatedAt);
    }
    return true;
  }

  /// `chore_assignees` denormalizes `household_id` (spec §2: "the client
  /// fills it on push") -- neither local row carries it directly (see
  /// `ChoreAssignees` in `lib/data/db/tables.dart`), so it's looked up via
  /// each dirty row's own chore.
  Future<bool> _pushChoreAssignees() async {
    final dirty = await _sync.dirtyChoreAssignees();
    if (dirty.isEmpty) {
      return false;
    }
    final choreIds = {for (final assignee in dirty) assignee.choreId};
    final chores = await (db.select(
      db.chores,
    )..where((tbl) => tbl.id.isIn(choreIds))).get();
    final choreHouseholdIds = {
      for (final chore in chores) chore.id: chore.householdId,
    };
    await transport.upsertRows(
      'chore_assignees',
      [
        for (final assignee in dirty)
          choreAssigneeRow(assignee, choreHouseholdIds),
      ],
      onConflict: 'chore_id,member_id',
    );
    for (final assignee in dirty) {
      await _sync.clearChoreAssigneeDirty(
        assignee.choreId,
        assignee.memberId,
        assignee.position,
      );
    }
    return true;
  }

  /// `chore_occurrences` denormalizes `household_id` the same way
  /// `chore_assignees` does; see [_pushChoreAssignees].
  Future<bool> _pushChoreOccurrences() async {
    final dirty = await _sync.dirtyChoreOccurrences();
    if (dirty.isEmpty) {
      return false;
    }
    final choreIds = {for (final occurrence in dirty) occurrence.choreId};
    final chores = await (db.select(
      db.chores,
    )..where((tbl) => tbl.id.isIn(choreIds))).get();
    final choreHouseholdIds = {
      for (final chore in chores) chore.id: chore.householdId,
    };
    await transport.upsertRows('chore_occurrences', [
      for (final occurrence in dirty)
        choreOccurrenceRow(occurrence, choreHouseholdIds),
    ]);
    for (final occurrence in dirty) {
      await _sync.clearChoreOccurrenceDirty(
        occurrence.id,
        occurrence.updatedAt,
      );
    }
    return true;
  }

  Future<bool> _pushShoppingItems() async {
    final dirty = await _sync.dirtyShoppingItems();
    if (dirty.isEmpty) {
      return false;
    }
    await transport.upsertRows('shopping_items', [
      for (final item in dirty) shoppingItemRow(item),
    ]);
    for (final item in dirty) {
      await _sync.clearShoppingItemDirty(item.id, item.updatedAt);
    }
    return true;
  }

  /// Pushes the hard-delete outbox (spec `docs/specs/sync-backend.md`
  /// §8.6.3), oldest first. An assignee that was removed and then re-added
  /// has a local row again: its tombstone is dropped with no network call
  /// (the re-added row's own push already sends `deleted_at: null`).
  /// Otherwise [SyncTransport.markDeleted], then delete exactly that
  /// tombstone. Throws like every other push step.
  ///
  /// An occurrence tombstone matches on `status = 'pending'` as well as
  /// `id` (spec §8.6 amendment 2026-10-06, technical review #1): every
  /// local site that hard-deletes an occurrence only ever deletes PENDING
  /// rows, so the tombstone's meaning is "the pending row is gone" -- and
  /// it must not land on a row another device has since completed, which
  /// would erase that completion from the server and from every device.
  Future<bool> _pushTombstones() async {
    final tombstones = await _sync.pendingTombstones();
    for (final tombstone in tombstones) {
      final memberId = tombstone.memberId;
      final isAssignee = tombstone.entity == 'chore_assignees';
      final readded = isAssignee
          ? await _sync.assigneeExists(tombstone.rowId, memberId!)
          : await _sync.occurrenceExists(tombstone.rowId);
      if (!readded) {
        await transport.markDeleted(
          tombstone.entity,
          isAssignee
              ? {'chore_id': tombstone.rowId, 'member_id': memberId}
              : {'id': tombstone.rowId, 'status': 'pending'},
          tombstone.deletedAt,
        );
      }
      await _sync.deleteTombstone(tombstone.id);
    }
    return tombstones.isNotEmpty;
  }

  /// Failure posture (spec §8.3): every engine error is swallowed into a
  /// silent retry-later; the app never surfaces sync errors in P3. This is
  /// the one place that happens, so both [pushDirty] and [pullSince] read
  /// identically at every call site.
  ///
  /// The failure is no longer only a debug print: it is recorded through
  /// [AppLog] as `sync.<where>` (spec `docs/specs/client-error-reporting.md`
  /// §3.4), which still prints in debug builds.
  void _logFailure(String where, Object error, StackTrace stackTrace) {
    AppLog.error('sync.$where', error, stackTrace);
  }
}

/// The production [SyncTransport]: a thin wrapper over
/// `Supabase.instance.client`'s RPC/PostgREST/realtime access. The only
/// class in this library that ever touches `Supabase.instance` -- tests
/// depend on [SyncTransport] and substitute their own fake instead.
class SupabaseSyncTransport implements SyncTransport {
  /// Creates a transport over the app's Supabase client. `Supabase.
  /// initialize()` must have already run (see `main.dart`) before any
  /// method on this class is called.
  const SupabaseSyncTransport();

  supabase.SupabaseClient get _client => supabase.Supabase.instance.client;

  @override
  Future<DateTime> serverNow() async {
    final result = await _client.rpc<dynamic>('server_now');
    return DateTime.parse(result as String).toUtc();
  }

  @override
  Future<List<Map<String, Object?>>> pullTable(
    String table, {
    required String householdId,
    required DateTime? since,
    required int offset,
    required int limit,
  }) async {
    // `households` is scoped by its own `id`; every other synced table
    // carries (or, for chore_assignees/chore_occurrences, denormalizes)
    // `household_id` directly.
    final scopeColumn = table == 'households' ? 'id' : 'household_id';
    var query = _client.from(table).select().eq(scopeColumn, householdId);
    if (since != null) {
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }
    // A total order is what makes `range` pages disjoint and complete
    // (see [syncPageSize]): `updated_at` alone has ties (one bulk upsert
    // stamps every row with the same `now()`), so the primary key follows.
    var ordered = query.order('updated_at', ascending: true);
    for (final column in pageOrderKeyColumns(table)) {
      ordered = ordered.order(column, ascending: true);
    }
    final rows = await ordered.range(offset, offset + limit - 1);
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }

  @override
  Future<void> upsertRows(
    String table,
    List<Map<String, Object?>> rows, {
    String? onConflict,
  }) async {
    if (rows.isEmpty) {
      return;
    }
    await _client.from(table).upsert(rows, onConflict: onConflict);
  }

  @override
  Future<void> insertMembersIgnoringConflicts(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return;
    }
    await _client.from('members').upsert(rows, ignoreDuplicates: true);
  }

  @override
  Future<void> updateMemberGrantedColumns(
    String id,
    Map<String, Object?> columns,
  ) async {
    await _client.from('members').update(columns).eq('id', id);
  }

  @override
  Future<void> updateHousehold(String id, Map<String, Object?> columns) async {
    await _client.from('households').update(columns).eq('id', id);
  }

  @override
  Future<void> markDeleted(
    String table,
    Map<String, Object?> match,
    String deletedAt,
  ) async {
    await _client.from(table).update({'deleted_at': deletedAt}).match({
      for (final entry in match.entries) entry.key: entry.value!,
    });
  }

  @override
  Future<bool> hasMembership(String householdId) async {
    final rows = await _client
        .from('members')
        .select('id')
        .eq('household_id', householdId)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Stream<void> householdChanges(String householdId) {
    supabase.RealtimeChannel? channel;
    late final StreamController<void> controller;

    void notify(supabase.PostgresChangePayload payload) {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }

    controller = StreamController<void>.broadcast(
      onListen: () {
        final ch = _client.channel('sync-engine-household-$householdId');
        channel = ch;
        ch.onPostgresChanges(
          event: supabase.PostgresChangeEvent.all,
          schema: 'public',
          table: 'households',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'id',
            value: householdId,
          ),
          callback: notify,
        );
        for (final table in const [
          'members',
          'categories',
          'chores',
          'chore_assignees',
          'chore_occurrences',
          'shopping_items',
        ]) {
          ch.onPostgresChanges(
            event: supabase.PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: supabase.PostgresChangeFilter(
              type: supabase.PostgresChangeFilterType.eq,
              column: 'household_id',
              value: householdId,
            ),
            callback: notify,
          );
        }
        // Spec `docs/specs/sync-freshness.md` §2.1 -- the fix for the
        // field-reported "the other phone takes very long to see my
        // change". A `subscribed` status is not just the FIRST connect: the
        // Supabase client reconnects on its own after a socket drop (Wi-Fi
        // to cell, a doze window, a proxy timeout) and re-emits it. Every
        // change the other device made DURING that outage was broadcast to
        // nobody, and nothing else would ever have told this engine it
        // missed them -- so a (re)subscribe must itself trigger a pull.
        //
        // Errors are logged and otherwise ignored: the client retries on
        // its own, and that retry produces the `subscribed` tick that
        // recovers the gap.
        ch.subscribe((status, error) {
          if (status == supabase.RealtimeSubscribeStatus.subscribed) {
            if (!controller.isClosed) {
              controller.add(null);
            }
            return;
          }
          if (error != null) {
            AppLog.error(
              'sync.realtime',
              error,
              null,
              context: {'status': status.name},
            );
          }
        });
      },
      onCancel: () {
        final ch = channel;
        channel = null;
        if (ch != null) {
          unawaited(_client.removeChannel(ch));
        }
      },
    );
    return controller.stream;
  }
}
