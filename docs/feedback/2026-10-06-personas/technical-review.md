# Famdo 0.14.0+21 — technical quality review

*Read-only code review of the worktree at `error-visibility-handover-7af6d0`
(HEAD `08d337e`, PR #60). Nothing was run except greps, one Python key diff
of the ARB files, and a look at the pinned `supabase`/`gotrue` sources in the
pub cache. Every citation is `path:line` in this worktree. Items already in
`docs/backlog.md` / `docs/future-improvements.md` / the wave-7 handover are
not re-reported; where I disagree with their priority I say so in one line.*

Severity key: **P1** data loss, security hole, silent incorrect state,
release-breaking · **P2** real bug or robustness gap on a plausible path ·
**P3** maintainability / perf / test gap worth a ticket.

---

## P1

### 1. A hard-delete tombstone deletes an occurrence another device has already *completed* — history silently lost

**Scenario.** Chore X has pending occurrence O. Device A completes O (O →
`done`, next occurrence A2 inserted). Device B, before pulling that, edits
X's schedule, pauses X, reopens an earlier closed-today occurrence, or
deletes X — every one of those calls `_deletePendingOccurrences`, which
hard-deletes O locally and records a tombstone. Both push.

- A pushes first: server O = `done`, A2 pending.
- B pushes: `_pushTombstones` → `markDeleted('chore_occurrences', {'id': O}, …)`
  → server O gets `deleted_at` **regardless of its status**
  (`lib/application/sync_engine.dart:716-734`, `:821-829` — the UPDATE
  matches on `id` only).
- A pulls: O arrives with `deleted_at != null` → `applyPulledOccurrenceDeletion`
  hard-deletes A's local `done` row (`lib/data/repositories/sync_repository.dart:341-343`
  — guard is `syncDirty == false`, no status check; A's row is clean because
  it was just pushed).

The completion is gone on the server and on A; B never had it. Stats
(`StatsRepository.doneCountsByMember`) and "Done today" undercount; the
chore's history is rewritten by a concurrent edit. If B pulled before
pushing, B *keeps* a local `done` row that the server has tombstoned —
permanent divergence between B and A. "Last push wins" is the documented
trade-off for *edits*; this is a tombstone written for a **pending** row
landing on a row that is no longer pending, which `sync-backend.md` §8.6
did not consider (§8.6.3 only discusses "never pushed" and "re-added").

**Why tests miss it.** `sync_engine_test.dart:923-1218` covers tombstone
push/pull with the target row still pending or absent; there is no case
where the server/local row has changed status between delete and tombstone.
`test_live/sync_tombstone_live_test.dart` likewise.

**Fix (S).** Tombstones for occurrences carry the semantics "the *pending*
row is gone", so (a) `SupabaseSyncTransport.markDeleted` for
`chore_occurrences` adds `.eq('status', 'pending')` (or `markDeleted` takes
an extra match map from the caller); (b) `applyPulledOccurrenceDeletion`
adds `status = pending` to its WHERE; (c) `repairGhostOccurrences` already
only touches pending rows. Then A's completion survives, B pulls O(done) and
its own B1 pending, and ghost repair settles the single-pending invariant.
Add the race as an engine test (dirty-done local row vs pulled tombstone;
server row `done` vs `markDeleted`).

### 2. Every server read is silently capped at PostgREST `max_rows = 1000` — join/download and the first pull truncate a household's history, and the cursor then skips the rest forever

**Evidence.** `supabase/config.toml:18` `max_rows = 1000` (the hosted
dashboard default is also 1000). No client query pages: the only
`.limit(`/`.range(` calls in `lib/` are `limit(1)` probes
(`household_gateway.dart:539,659,670`, `sync_engine.dart:837`).
`downloadHousehold` does bare `select().eq(household_id)` per table
(`lib/application/household_gateway.dart:534-593`) and `pullTable` does the
same with an optional `gt(updated_at)` (`sync_engine.dart:768-783`).

**Scenario.** A household with 3 daily + 4 weekly chores accrues ≈1,300
`chore_occurrences` rows in a year; `clearCheckedOlderThan`
(`providers.dart:819-827`) soft-deletes checked shopping items daily, so
`shopping_items` grows at the family's purchase rate (a few thousand/year)
and the suggestions feature reads that history. A second phone joins (or a
phone reconnects after reset): `_insertSnapshot` gets at most 1,000 rows per
table — PostgREST returns heap order, i.e. mostly oldest-first, so the
**newest rows, including the current pending occurrences, are the ones
dropped**. The first `pullSince` (`since == null`, `sync_engine.dart:478-480`)
fetches the same capped 1,000, then stores the cursor (`:569`); every
missing row has `updated_at < cursor` and is never fetched again. Chores
whose pending occurrence was dropped vanish from that phone's list until
the other device next touches them; stats undercount; shopping suggestions
are a subset. No error anywhere — this is the exact "silent incorrect
state" class.

**Why tests miss it.** `FakeSyncTransport`/`FakeHouseholdGateway` return
whatever they are given; pgTAP and `test_live` use handfuls of rows.

**Fix (S).** Page every full-table read with `.order('updated_at').range(i, i+999)`
until a short page (both `downloadHousehold` and `pullTable`), and make
`pullTable` order by `updated_at` so the cursor can be advanced to the last
row seen if a page is cut. Alternatively raise `max_rows` in the dashboard
*and* page — the cap also exists on the hosted project. A `test_live` case
that inserts 1,001 occurrences and asserts the second client sees them all
would have caught this.

---

## P2

### 3. Pull-cursor race: a row committed by a transaction that *started* before `server_now()` but *committed* after this pull's table read is never pulled

`_pullSinceInner` takes `serverNow` first (`sync_engine.dart:485`) then reads
seven tables in seven round trips (`:487-521`) and stores `serverNow` as the
cursor (`:569`). `set_updated_at()` stamps `now()`
(`supabase/migrations/20260731120000_initial_schema.sql:10-18`), which in
Postgres is the **transaction start time**. A concurrent push whose
PostgREST transaction began at `t0 < serverNow` and committed after the
corresponding `pullTable` read gets `updated_at = t0 < cursor` and is
invisible to every later incremental pull. The comment at `:481-484`
("ends up with updated_at AFTER this value") assumes `now()` is commit time;
it is not. The window is the pull's own duration (hundreds of ms across
seven requests) against a bulk upsert's transaction time — small, but it is
a steady-state leak with no repair path except re-join (and realtime does
not help: the event fires, the pull runs, the row is below the cursor).
PLAUSIBLE in frequency, verified in mechanism.

**Fix (XS).** Store `serverNow - overlap` (e.g. 30 s) as the cursor; the
pull apply is idempotent (LWW + dirty check) so re-applying is harmless. Or
switch the trigger to `clock_timestamp()` (narrows but does not close the
window). Add an engine test with a fake transport whose `pullTable` returns
a row stamped just before the `serverNow` it handed out.

### 4. Ghost repair's survivor key mixes device-authored and server-authored `updatedAt`; a concurrent catch-up can delete *both* pending occurrences and make the chore disappear

`repairGhostOccurrences` orders by `updatedAt` string compare
(`sync_repository.dart:389-395`). A locally created row carries the
device's `DateTime.now().toUtc().toIso8601String()` (`…Z`, 3 or 6 fraction
digits); a pulled row carries Postgres' `…+00:00` (6 digits). Two devices
both running `catchUpOverdue` on the same morning (`chore_service.dart:172-209`
— each closes O as missed and inserts its *own* new pending row with a fresh
UUID) is the common case that produces two pending rows. The engine starts
`pushDirty()` and, via the realtime `subscribed` tick, a `pullSince()`
*concurrently* (`sync_engine.dart:304-318`, `:899-904`), so the pull can
apply the other device's row while the local one is still unpushed. If B's
clock is behind the server by more than the gap between A's push and B's
catch-up, B keeps A1 and tombstones B1, while A (comparing two server
stamps) keeps B1 and tombstones A1. Both tombstones push; both pending rows
end up `deleted_at` on the server; after the next pulls **neither device has
a pending occurrence** and nothing regenerates one — `catchUpOverdue` skips
chores with no pending row (`chore_service.dart:185-188`), so the chore
silently leaves the list until someone edits its schedule.
Independently, the `Z` vs `+00:00` suffix makes `'…00.123Z' > '…00.123456+00:00'`
lexically, so a 3-digit local stamp can "win" over a later server stamp.
PLAUSIBLE, unverified end-to-end (needs two clients + skewed clock).

**Fix (S).** Pick the survivor from fields both devices see identically:
`dueDate` desc, then `id` desc — drop `updatedAt` from the key (convergence
matters more than "the one a schedule edit just wrote", and edits always
produce the later due date anyway except when moving a start date back).
Also normalise timestamps at the boundary (`DateTime.parse(..).toUtc().toIso8601String()`
in `*FromRow`) so local and pulled stamps are the same format. Longer term:
generate catch-up/next occurrence ids deterministically
(`uuid v5(choreId + dueDate)`) so both devices create the *same* row and
the problem vanishes.

### 5. One persistently rejected row blocks the push of every later table, silently and forever

`_pushAll` is a straight sequence that throws on the first failure
(`sync_engine.dart:399-408`) and `pushDirty` returns on that throw
(`:429-443`). A single row rejected with a non-transient error (an FK the
server does not have, a check constraint, a 42501 like the pre-#51
`members.user_id` bug) therefore stops households→…→tombstones at that table
on every tick; the only user-visible signal is the D-5 banner's generic
"unsent changes" after 3 min, with no hint which row. The B-6 fix made
the *pull* unconditional but left the push all-or-nothing. #51 fixed one
instance of this class; the structure that turned one bad row into a total
push outage is unchanged.

**Fix (S).** Push each table in its own try/catch and continue; on a batch
failure of class 22/23/42, retry row-by-row and quarantine the offender
(record via `AppLog.error('sync.rejected', …, context: {table, id})`,
leave it dirty) so the rest of the household keeps syncing. This mirrors
what `ErrorReporter.flush` already does for its own batches
(`error_reporter.dart`).

### 6. Two pending occurrences locally make `pendingOccurrenceOf` throw, which kills catch-up and can turn into the startup error screen

`pendingOccurrenceOf` uses `getSingleOrNull()` (`chore_repository.dart:439-446`);
`catchUpOverdue` calls it per chore (`chore_service.dart:185`) and runs
inside `bootstrapProvider` (`providers.dart:815-817`) and the day-change /
resume path (`providers.dart:1560-1563`, unawaited). §8.6 argues repair on
pull removes ghosts, but repair only runs on a *linked* device inside a
pull transaction. An unlinked device that was once linked, or any path that
leaves two pending rows (the race in #4 between a local insert and a pull
that has already run its repair; a join-import copy plus a later pull),
makes bootstrap throw → `_Bootstrapped` shows the startup error screen, and
the resume/day-change run dies silently (only `PlatformDispatcher.onError`
sees it). `sync-backend.md` §8.6 itself records this as the symptom the
old client produced.

**Fix (XS).** Make `pendingOccurrenceOf` tolerant: order by `dueDate desc,
updatedAt desc` and `limit(1)`, and have `catchUpOverdue` (or bootstrap)
call `repairGhostOccurrences` for the household first. Add a test with two
pending rows → catch-up completes and repairs.

### 7. Sync-health banner compares a *server* timestamp with the *device* clock

`computeSyncHealth` uses `lastPulledAt` — the stored `server_now()`
(`settings.setSyncLastPulledAt(serverNow)`, `sync_engine.dart:569`) — and
`now` from `clockProvider` (`lib/domain/sync_health.dart:17-34`,
`providers.dart:635-643`). A phone whose clock is >5 min ahead of the server
shows the "can't reach the household" banner permanently once a session is
older than 5 min, with sync working perfectly; a phone behind by N minutes
hides a real outage for N extra minutes. Manual-clock phones exist and the
rest of the app is careful to never trust the device clock for this cursor.

**Fix (XS).** Keep the server cursor for correctness, but stamp a second,
device-clock `lastPullCompletedAt` (in-memory in the engine, or a settings
column) and feed *that* to `computeSyncHealth`. Test: skewed clock,
healthy sync → healthy status.

### 8. Concurrent assignee edits produce a union with duplicate `position`s and a nondeterministic rotation order

`applyPulledChore` keeps a dirty local chore and skips the pulled chore, but
the pulled `chore_assignees` rows are applied anyway
(`sync_engine.dart:534-548`): rows for members only the other device added
are inserted, tombstones for members this device still has dirty are kept.
Result: both edits merged, two rows with the same `position`
(`chore_repository.dart:694-709` numbers from 0 each time).
`_currentAssigneeIds` orders by `position` with ties → SQLite returns an
arbitrary order → `nextRotationAssignee` can pick differently on each device
until the next edit rewrites the list. Also `clearChoreAssigneeDirty` keys
on `position` (`sync_repository.dart`), which in this state is not unique.

**Fix (S).** Treat the assignee list as part of the chore row for LWW
purposes: on pull, if the chore is dirty skip *its* assignee rows too; if
it is clean, replace the whole set (delete local rows for that chore, insert
pulled). Tie-break ordering by `memberId` as a defensive measure.

---

## P3

### 9. `db.yml`'s "touches the database" scope misses `lib/data/repositories/sync_repository.dart`

The regex at `.github/workflows/db.yml:86` lists `lib/data/sync/` and
`sync_engine.dart` but not `sync_repository.dart`, where the LWW apply,
tombstone deletion and ghost repair actually live (PR #57 changed it by 118
lines). A PR editing only that file skips pgTAP + `test_live` and reports
green. **Fix (XS):** add it (and `lib/data/db/tables.dart`, whose column
set is the wire contract) to the pattern.

### 10. Release workflow never checks that the tag matches `pubspec.yaml`

`release.yml` builds whatever is at the tag; nothing asserts `v0.14.0` ==
`version: 0.14.0+21` (`pubspec.yaml:19`) or that the build number is higher
than the previous release (Obtainium/F-Droid key off `versionCode`). A tag
pushed before the bump ships an APK that will not install over the previous
one, or installs with the wrong About text. **Fix (XS):** one step that
greps `pubspec.yaml` and fails on mismatch; the aapt dump already in the
job can also assert `versionCode`.

### 11. Migration tests cover `N→13` and single steps `13→14…16→17`, not `N→17`

`schema_migration_test.dart` has no `1→17`, `12→17` or `14→17` case, and the
`from >= 14 && from < 17` guard (`app_database.dart` v16→17 block) and the
`from < 16` `else`-branch backfill are exactly the shapes whose correctness
depends on the combined path. By inspection they are right; the suite does
not prove it, and real users jump several versions. **Fix (S):** a
parametrised test opening a v`N` fixture for every `N` in `1..16` and
asserting the full v17 column set — replaces the hand-written ladder.

### 12. `household_invites` and `households` grant full-column UPDATE; invite codes come from `random()`

`grant select, update on public.household_invites` (initial schema `:423`)
lets any member rewrite `code`, `expires_at` (a permanent invite) or
`created_by`; the client only ever needs `revoked_at`. `households` gets
full UPDATE (`:410`) though the client sends only `name` (plus `created_at`/
`updated_at`, the latter trigger-overwritten — but `created_at` is
client-writable). The WITH CHECK (= USING) keeps this inside the household,
and an account in two households can legitimately move a chore's
`household_id` from A to B via upsert, leaving its children's denormalised
`household_id` pointing at A. `create_invite` uses `random()` (`:255-262`),
not `gen_random_bytes`; at 40 bits and a 7-day expiry brute force is
infeasible, but a CSPRNG is a one-line change. **Fix (XS):** column-scope
both grants like `members`; `substr(encode(gen_random_bytes(8),'hex')…)`
or `pgcrypto`-based alphabet mapping.

### 13. Errors in the notification-action background isolate are never recorded

`handleNotificationAction` runs in its own isolate where `AppLog.attach`
has never been called, so `AppLog.error('app.notificationAction', …)`
(`notification_action_handler.dart:154`) is `debugPrint` only. The one path
the handover says "needs a human with a phone" (GATE 3) is also the one
whose failures the new error-reporting pipeline cannot see. **Fix (XS):**
attach a `DatabaseErrorLogSink(database)` in `_run` before the try, detach
in `finally` (the `ClientErrors` ring buffer is in the same SQLite file).

### 14. No retention for soft-deleted rows; shopping suggestions load the entire item history into memory

Nothing ever prunes `deleted_at` rows locally or on the server (the only
retention job is `prune_client_errors`). `clearCheckedOlderThan` converts
every bought item into a permanent history row, and `_historyRows`
(`shopping_repository.dart:320-338`) `select()`s all of them for every
suggestion computation. Combined with #2 this is the table most likely to
cross 1,000 rows first. **Fix (S):** cap history per normalised name
(keep last N), or a scheduled local compaction of soft-deleted shopping
rows older than a year with a matching server cron; make
`_historyRows` a grouped SQL query.

### 15. `watchActiveChores` is N+1 and re-queries on every emission

`query.watch().asyncMap(_choreDetailsFromRows)` (`chore_repository.dart:310`)
issues one `chore_assignees` query per chore per emission; `pausedChoresProvider`
and `hasActiveChoresProvider` both subscribe, and every chore write (including
each pulled row in a sync transaction) re-emits. Fine at 20 chores; wasteful
and jank-prone at 100+. The comment at `:303-308` also admits the stream
does not watch `chore_assignees` itself — a pulled assignee-only change
(possible after #8) is not re-rendered until some chore row changes.
**Fix (S):** one joined query mapped in Dart, or `readsFrom: {choreAssignees}`
on a custom select.

### 16. `ErrorScrubber` scrubs the message but not `context` values or non-quoted raw input in `FormatException`s

`_context` only caps lengths (`error_scrubber.dart:143-150`); any future
`AppLog.error(..., context: {...})` call site that passes a member name or
email would upload it verbatim (none does today — the only `context:` use is
`{'status': …}`). `FormatException.toString()` appends the offending source
unquoted (e.g. a mistyped date or join code), which passes the quote/email/
digit rules. **Fix (XS):** run `_message`'s rules over context values too;
special-case `FormatException` to `error.message` only.

### 17. `householdChanges` and the poll have no mutual exclusion; every push triggers two pulls

`start()` fires `pushDirty()` (which pulls on success) and the realtime
`subscribed` tick fires `pullSince()` concurrently (`sync_engine.dart:304-318`);
every later push is followed by its own pull *and* a realtime event from the
server for the rows it just wrote → a second pull. Two interleaved
`_pullSinceInner`s each set the cursor (`:569`), so a slow earlier pull can
move the cursor *backwards* after a faster later one (harmless re-apply, but
it is the precondition for #4's divergence and doubles `hasMembership`
round trips). **Fix (XS):** a single in-flight `Future` guard
(`_pulling ??= _pullSinceInner()…whenComplete`) and ignore realtime events
for ≈1 s after our own push.

---

## Things I checked that are fine (so nobody re-reviews them)

- **RLS isolation** holds for every table and verb I traced: SELECT/UPDATE
  USING + implicit WITH CHECK scoped by `is_household_member`; child-table
  INSERT cross-checks the chore's household; DELETE granted nowhere;
  invites unreadable to non-members; all RPCs `security definer` with
  `set search_path = public` (linter 0011 closed in `20260801150000`).
  `remove_member` avoids an existence oracle. pgTAP 001/002 exercise the
  matrix and the exit RPCs.
- **Revocation probe cannot false-positive on auth loss**: an expired token
  whose refresh fails transiently makes `AuthHttpClient`/`_getAccessToken`
  throw (pub cache `supabase-2.14.0/lib/src/supabase_client.dart:262-283`),
  and a non-retryable refresh failure removes the session → `signedOut` →
  `syncEngineProvider` swaps to `NoopSyncEngine` before any probe runs.
  `anon` has no SELECT grant, so an unauthenticated probe errors instead of
  returning empty.
- **No secrets in the repo**: only the publishable key
  (`lib/app/supabase_config.dart`), by design; `test_live` reads the
  service key from the environment and refuses non-loopback hosts.
- **Android release gates** (INTERNET, `allowBackup=false`, action receiver)
  assert on the built APK; iOS backup exclusion covers the four SQLite files
  (`ios/Runner/AppDelegate.swift:79-98`) and is pinned by a test.
- **DE localisation is complete**: 362 keys in both ARBs, zero missing /
  extra (the EN file is larger only because it carries `@` descriptions).
  No test pins parity, but `gen_l10n` with `nullable-getter: false` fails
  the build on a missing key rather than falling back.
- **Notifications**: one-shot `zonedSchedule` from local-calendar
  `DateTime` components converted by instant, `inexactAllowWhileIdle`, boot
  receiver declared, writes serialised through one promise chain
  (`notification_scheduler.dart:545-550`), horizon rewritten on every
  recompute; `nextLocalMidnight` is DST-safe.
- **Local FKs are enforced** (`PRAGMA foreign_keys = ON`) and `downloadHousehold`
  includes soft-deleted members/categories, so pulled history rows never
  dangle. A pull transaction that does fail rolls back without advancing the
  cursor (test `sync_engine_test.dart:300`).
- **Rotation cover logic (#60)** is pure, tested, and deterministic given
  the same assignee order on both devices.

---

## Architecture health

**Solid.** The layering is real: `domain/` is pure and clock-free,
`application/` orchestrates, `data/` is storage, `features/` reaches up
only through providers (one `ref.watch(syncEngineProvider) is! NoopSyncEngine`
type test in `chores_list_screen.dart:111` is the only smell). Seams
(`SyncTransport`, `HouseholdGateway`, `AuthGateway`, `ErrorReportTransport`,
`DigestNotificationPlugin`) are narrow and faked consistently; the engine's
LWW/flag/cursor logic is tested against a real in-memory drift DB. Specs are
binding and cited from code; the doc comments explain *why*, not *what*.
Release gates assert on the artefact. The error-reporting pipeline is
well-scoped (scrubbed, deduped, capped, opt-out, server-pruned). Riverpod
discipline (select-scoped watches, controllers constructed once in `main`,
no autoDispose misuse) is deliberate and documented where it bit.

**Drifting.**
- *The conflict model has outgrown "LWW per row".* Tombstones (#1), ghost
  repair (#4), assignee sets (#8) and catch-up (#4) are each a small
  hand-rolled merge rule on top of LWW, with no shared statement of
  invariants ("a tombstone only kills pending rows", "assignees are one
  value", "ids are deterministic"). Writing those four rules down in
  `sync-backend.md` §8.7 before fixing any of them will prevent the next
  three findings.
- *Timestamps are three things in one column.* `updatedAt` is a device
  stamp on write, a server stamp after a round trip, and a format that
  differs between the two; it is used as a dirty-clear guard (fine), a
  survivor key (#4) and a health signal (#7). The repositories' injectable
  `nowUtc` discipline is good; the boundary normalisation is missing.
- *All-or-nothing network steps.* `_pushAll` (#5), `downloadHousehold`/
  `pullTable` without paging (#2) and the seven-request pull snapshot (#3)
  all assume small, fast, atomic. Each is one small change away from
  robust.
- *Oversized files.* `providers.dart` (1,874 lines) holds four controllers,
  the sync graph, the digest graph and the clock; `chores_list_screen.dart`
  (1,045) and `account_section.dart` (1,000) mix layout with flow logic.
  Not wrong, but every reviewer pays for it.
- *Verification asymmetry.* 173 unit/widget files vs. three `test_live`
  files, 17 Maestro flows, and iOS E2E on demand only. Everything that
  crosses a process boundary (second device, background isolate,
  notification delivery) is reasoned about rather than observed — the
  handover says so honestly. The findings above cluster exactly there.

---

## Suggested order of work

1. **#1 tombstone status guard + #6 tolerant `pendingOccurrenceOf`** (S + XS):
   stops the one confirmed history-loss path and the one confirmed crash
   path; both are tiny and testable in the existing engine/service suites.
2. **#2 paging** (S): every household crosses 1,000 history rows within a
   year; fix before the second-device/reconnect story is relied on.
3. **#4 convergent ghost-repair key + timestamp normalisation, #17 pull
   guard** (S + XS): remove the divergence that can make a chore vanish.
4. **#3 cursor overlap + #5 per-table push with quarantine** (XS + S):
   closes the two silent, permanent desync modes.
5. **#7 health clock, #9 db.yml scope, #10 tag check** (3 × XS): a
   mid-afternoon's worth of CI/observability hygiene that each removes a
   false signal.

Then write the §8.7 invariants (architecture note above) before the next
sync feature, and consider deterministic occurrence ids as the structural
fix behind #4.
