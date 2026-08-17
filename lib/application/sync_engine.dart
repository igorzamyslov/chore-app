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

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/data/repositories/sync_repository.dart';
import 'package:chore_app/data/sync/row_mappers.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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

  /// Rows of [table] belonging to [householdId] with `updated_at >`
  /// [since], or every row if [since] is `null` (this device's first
  /// pull). RLS (or the fake) scopes access to [householdId]'s own rows.
  Future<List<Map<String, Object?>>> pullTable(
    String table, {
    required String householdId,
    required DateTime? since,
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

  final SyncRepository _sync;

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
          ]),
        )
        .listen((_) => _scheduleDebouncedPush());
    // Every event on this stream means "something may have changed on the
    // server, or we may have MISSED something that did" -- the transport
    // emits both on a live postgres_changes payload and on every
    // (re)subscribe (spec `docs/specs/sync-freshness.md` §2.1). Mapping
    // both to the same pull is what closes the gap a dropped-and-restored
    // socket used to leave open indefinitely.
    _realtimeSubscription = transport
        .householdChanges(householdId)
        .listen((_) => unawaited(pullSince()));
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
  /// [pushDirty] swallows that; [refreshNow] reports it.
  Future<void> _pushAll() async {
    await _pushHouseholds();
    await _pushMembers();
    await _pushCategories();
    await _pushChores();
    await _pushChoreAssignees();
    await _pushChoreOccurrences();
    await _pushShoppingItems();
  }

  @override
  Future<bool> refreshNow() async {
    try {
      await _pushAll();
      final revoked = await _pullSinceInner();
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
      await _pullSinceInner();
    } on Object catch (error, stackTrace) {
      _logFailure('pullSince', error, stackTrace);
    }
  }

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

    final householdRows = await transport.pullTable(
      'households',
      householdId: householdId,
      since: since,
    );
    final memberRows = await transport.pullTable(
      'members',
      householdId: householdId,
      since: since,
    );
    final categoryRows = await transport.pullTable(
      'categories',
      householdId: householdId,
      since: since,
    );
    final choreRows = await transport.pullTable(
      'chores',
      householdId: householdId,
      since: since,
    );
    final assigneeRows = await transport.pullTable(
      'chore_assignees',
      householdId: householdId,
      since: since,
    );
    final occurrenceRows = await transport.pullTable(
      'chore_occurrences',
      householdId: householdId,
      since: since,
    );
    final itemRows = await transport.pullTable(
      'shopping_items',
      householdId: householdId,
      since: since,
    );

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
      for (final row in assigneeRows) {
        await _sync.applyPulledChoreAssignee(choreAssigneeFromRow(row));
      }
      for (final row in occurrenceRows) {
        await _sync.applyPulledChoreOccurrence(choreOccurrenceFromRow(row));
      }
      for (final row in itemRows) {
        await _sync.applyPulledShoppingItem(shoppingItemFromRow(row));
      }
    });

    // Cursor stored only after the transaction above commits (spec §8.3).
    await settings.setSyncLastPulledAt(serverNow);
    return false;
  }

  /// Households-only push (spec §8.3's grants note applied to `households`
  /// too -- see [SyncTransport.updateHousehold]'s doc comment): a plain
  /// UPDATE per dirty row, never an upsert.
  Future<void> _pushHouseholds() async {
    final dirty = await _sync.dirtyHouseholds();
    for (final household in dirty) {
      await transport.updateHousehold(household.id, householdRow(household));
      await _sync.clearHouseholdDirty(household.id, household.updatedAt);
    }
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
  Future<void> _pushMembers() async {
    final dirty = await _sync.dirtyMembers();
    if (dirty.isEmpty) {
      return;
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
  }

  Future<void> _pushCategories() async {
    final dirty = await _sync.dirtyCategories();
    if (dirty.isEmpty) {
      return;
    }
    await transport.upsertRows('categories', [
      for (final category in dirty) categoryRow(category),
    ]);
    for (final category in dirty) {
      await _sync.clearCategoryDirty(category.id, category.updatedAt);
    }
  }

  Future<void> _pushChores() async {
    final dirty = await _sync.dirtyChores();
    if (dirty.isEmpty) {
      return;
    }
    await transport.upsertRows('chores', [
      for (final chore in dirty) choreRow(chore),
    ]);
    for (final chore in dirty) {
      await _sync.clearChoreDirty(chore.id, chore.updatedAt);
    }
  }

  /// `chore_assignees` denormalizes `household_id` (spec §2: "the client
  /// fills it on push") -- neither local row carries it directly (see
  /// `ChoreAssignees` in `lib/data/db/tables.dart`), so it's looked up via
  /// each dirty row's own chore.
  Future<void> _pushChoreAssignees() async {
    final dirty = await _sync.dirtyChoreAssignees();
    if (dirty.isEmpty) {
      return;
    }
    final choreIds = {for (final assignee in dirty) assignee.choreId};
    final chores = await (db.select(
      db.chores,
    )..where((tbl) => tbl.id.isIn(choreIds))).get();
    final choreHouseholdIds = {
      for (final chore in chores) chore.id: chore.householdId,
    };
    await transport.upsertRows('chore_assignees', [
      for (final assignee in dirty)
        choreAssigneeRow(assignee, choreHouseholdIds),
    ], onConflict: 'chore_id,member_id');
    for (final assignee in dirty) {
      await _sync.clearChoreAssigneeDirty(
        assignee.choreId,
        assignee.memberId,
        assignee.position,
      );
    }
  }

  /// `chore_occurrences` denormalizes `household_id` the same way
  /// `chore_assignees` does; see [_pushChoreAssignees].
  Future<void> _pushChoreOccurrences() async {
    final dirty = await _sync.dirtyChoreOccurrences();
    if (dirty.isEmpty) {
      return;
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
  }

  Future<void> _pushShoppingItems() async {
    final dirty = await _sync.dirtyShoppingItems();
    if (dirty.isEmpty) {
      return;
    }
    await transport.upsertRows('shopping_items', [
      for (final item in dirty) shoppingItemRow(item),
    ]);
    for (final item in dirty) {
      await _sync.clearShoppingItemDirty(item.id, item.updatedAt);
    }
  }

  /// Failure posture (spec §8.3): every engine error is swallowed into a
  /// silent retry-later; the app never surfaces sync errors in P3. This is
  /// the one place that happens, so both [pushDirty] and [pullSince] read
  /// identically at every call site.
  void _logFailure(String where, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('SyncEngine.$where failed (will retry later): $error');
    }
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
  }) async {
    // `households` is scoped by its own `id`; every other synced table
    // carries (or, for chore_assignees/chore_occurrences, denormalizes)
    // `household_id` directly.
    final scopeColumn = table == 'households' ? 'id' : 'household_id';
    var query = _client.from(table).select().eq(scopeColumn, householdId);
    if (since != null) {
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }
    final rows = await query;
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
            debugPrint('SyncTransport.householdChanges($status): $error');
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
