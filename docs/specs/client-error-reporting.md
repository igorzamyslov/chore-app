# Client error reporting

**Status:** binding. Client schemaVersion 16; server migration
`…_client_errors.sql` + pgTAP `005`. App version 0.13.0+20.

Goal (Igor, 2026-10-04): "I want you to be able to see failures on the client
and server side, to be able to resolve bugs quicker." Server failures are
already readable through the Supabase MCP (`query_logs`, advisors). This spec
makes **client** failures visible: every error the app catches or misses is
recorded locally and, on signed-in linked devices with the setting on,
uploaded to a Supabase table that only the operator reads.

Decisions settled in brainstorming (2026-10-04): own uploader triggered by
sync (§4); merge repeats only into not-yet-uploaded rows (§3.2); nightly
pg_cron cleanup, 90 days / 1000 rows per user (§5.3); opt-out switch, default
on (§6); privacy disclosure in PRIVACY.md + the switch subtitle only, the
sign-in intro is unchanged (§7); errors recorded before sign-in ARE uploaded
once the device is signed in and linked (§4.3); "Share diagnostics" is
deferred (§9).

## 1. Units

| Unit | Location | Purpose |
|---|---|---|
| `ErrorScrubber` | `lib/domain/error_scrubber.dart` | Pure: `Object error, StackTrace? stack` → `ScrubbedError(errorType, message, stack)`. No I/O. |
| `ClientErrors` table | `lib/data/db/tables.dart` | Local ring buffer, never synced. |
| `ErrorLogRepository` | `lib/data/repositories/error_log_repository.dart` | Record (merge + cap), read pending, mark uploaded. |
| `AppLog` | `lib/application/app_log.dart` | Static facade every call site uses. Never throws. |
| `ErrorReportTransport` | `lib/application/error_reporter.dart` | Interface + Supabase impl: one method, `insertErrors(rows)`. |
| `ErrorReporter` | `lib/application/error_reporter.dart` | Uploads pending rows when triggered and allowed. |
| `ErrorReporterController` | `lib/app/providers.dart` | Wires triggers (start, resume, successful pull) to the reporter. |
| Settings switch | `lib/features/settings/about_section.dart` | `Settings.errorReportsEnabled`. |

## 2. `ErrorScrubber` (privacy boundary)

No user content may leave the device: chore titles, member names, category
names, shopping items, household names, emails, invite codes. Error messages
from PostgREST/Postgres/our own exceptions can embed row values, so the
scrubber is deliberately lossy.

- `errorType`: `error.runtimeType.toString()`, max 200 chars.
- `message`, built in this order, then capped at 500 chars:
  1. `PostgrestException`: `'postgrest code=${e.code}'` plus
     `' status=…'` if available (supabase_flutter exposes `code`; include
     `details`/`message` NOT at all — they carry row values).
  2. `AuthException`: `'auth status=${e.statusCode} code=${e.code}'`.
  3. Everything else: `error.toString()`, then:
     - cut everything from `Causing statement` on: sqlite3's
       `SqliteException` (also when wrapped in `DriftRemoteException`)
       appends the SQL and its bound parameters **unquoted** — chore titles
       would otherwise pass the quote rule (found in review);
     - replace every email (`[^\s@]+@[^\s@]+\.[^\s@]+`) with `<email>`;
     - replace every single- or double-quoted span (`'…'`, `"…"`, also
       `«…»`/`“…”`) with `<str>`;
     - replace every run of 6+ digits with `<num>`;
     - **keep** UUIDs (they are ids, not content, and are what makes a
       report actionable) — so apply the digit rule only to runs that are
       not part of a UUID (`[0-9a-f]{8}-[0-9a-f]{4}-…`); simplest correct
       implementation: tokenise UUIDs out first, scrub, put them back.
- `stack`: `stack.toString()`, truncated to the first 4000 chars (cut at a
  line boundary). Stack frames contain file paths and line numbers only.
- `context` (passed by call sites, §3.3) is a `Map<String, String>` and
  call sites may only put ids, enum names, table names and counts in it.
  The scrubber caps it at 10 entries, keys ≤ 40 chars, values ≤ 100 chars.

Unit-test the scrubber with real-shaped inputs: a PostgrestException with a
chore title in `details`, an exception string with an email and a quoted
member name, a UUID next to a long number, a 10 KB stack.

## 3. Local storage and `AppLog`

### 3.1 Table `client_errors` (drift `ClientErrors`, schemaVersion 15 → 16)

Device-scoped, **never synced** (not in `SyncEngine`'s `tableUpdates` list,
no `syncDirty`, not exported by Data export, cleared by "Reset app data").

| column | type | notes |
|---|---|---|
| `id` | text PK | uuid v4, client-generated; also the server PK |
| `source` | text | where it happened, e.g. `sync.pushDirty`, `ui.inviteFlow` (§3.3) |
| `errorType` | text | from scrubber |
| `message` | text | from scrubber |
| `stack` | text nullable | from scrubber |
| `context` | text nullable | JSON object string |
| `count` | int, default 1 | merged repeats |
| `firstSeenAt` | text | ISO-8601 UTC |
| `lastSeenAt` | text | ISO-8601 UTC |
| `appVersion` | text | `'<version>+<build>'`, e.g. `0.13.0+20` |
| `platform` | text | `'${Platform.operatingSystem} ${Platform.operatingSystemVersion}'`, capped 100 |
| `householdId` | text nullable | `Settings.syncHouseholdId` at record time |
| `uploadedAt` | text nullable | set after a successful upload |

Migration: `if (from < 16) { await migrator.createTable(clientErrors); }`
plus `Settings.errorReportsEnabled` (`boolean().withDefault(true)`) added via
`addColumn` for `from >= 2` installs (follow the existing pattern in
`app_database.dart`). Add the v15 → v16 step to the existing migration test.
"Reset app data" (`lib/application/data_reset.dart`) deletes all
`client_errors` rows.

### 3.2 `ErrorLogRepository.record(...)` — merge and cap, one transaction

1. Look for a row with `uploadedAt IS NULL` and the same
   (`source`, `errorType`, `message`). If found: `count += 1`,
   `lastSeenAt = now`, and update `stack`/`context`/`appVersion` to the
   latest values. Otherwise insert a new row (`count = 1`,
   `firstSeenAt = lastSeenAt = now`).
2. Delete everything except the newest **200** rows by `lastSeenAt` (ties by
   `id`). Uploaded rows are kept locally as history but count toward the cap.

Other methods: `pending({int limit = 50})` (oldest `firstSeenAt` first,
`uploadedAt IS NULL`), `markUploaded(List<String> ids, DateTime at)`,
`deleteAll()`.

### 3.3 `AppLog`

```dart
abstract final class AppLog {
  static void error(String source, Object error, StackTrace? stack,
      {Map<String, String>? context});
  static void attach(ErrorLogSink sink);   // main.dart, after DB is open
  static void detach();                    // tests
}
```

- `error()` is **synchronous and fire-and-forget**: it scrubs, then
  `unawaited(sink.record(...))` wrapped in its own try/catch. It never
  throws, never awaits, and never calls `AppLog.error` on its own failure
  (that path only `debugPrint`s) — no recursion.
- In debug builds it also `debugPrint`s `'[$source] $error'` (preserving
  today's `SyncEngine` debug output).
- With no sink attached (unit tests, pre-DB startup), it only `debugPrint`s.
- `ErrorLogSink` is a tiny interface implemented by `ErrorLogRepository`
  plus whatever supplies `appVersion`/`platform`/`householdId`; tests attach a
  recording fake. The sink reads `householdId` from the settings row at
  record time.
- `source` strings are stable identifiers, `area.thing`, lower camel case
  after the dot. They are grouping keys on the server — never interpolate
  data into them.

### 3.4 Call sites (all must be wired)

| Site | `source` |
|---|---|
| `SupabaseSyncEngine._logFailure(where, …)` | `sync.<where>` (`sync.pushDirty`, `sync.pullSince`, `sync.refreshNow`). Keep the debug print behaviour via AppLog. |
| Realtime subscribe callback error (`SupabaseSyncTransport.householdChanges`) | `sync.realtime`, context `{'status': status.name}` |
| Every `catch (_)` in `lib/` that swallows an error (today: `invite_flow.dart:33`, `reset_flow.dart:115`, `account_section.dart:224,380,584,737,940`, `export_row.dart:66`, `notification_action_handler.dart:150`, `household_exit_service.dart:115`) | `ui.<file-ish name>` / `app.<service>`; change to `catch (e, s)` and call `AppLog.error` before the existing handling. **Exception:** a catch of a typed domain failure that is an expected outcome, not a bug (e.g. `member_edit_sheet.dart:458` `ClaimedMemberRemovalFailure`) is NOT logged. Re-grep `catch (` across `lib/` for other swallow sites (`on … catch (e)` blocks that drop `e`) and wire them too, applying the same expected-outcome exception. |
| `FlutterError.onError` (main.dart) | `flutter.framework`; then call the previous handler (`FlutterError.presentError` in debug). |
| `PlatformDispatcher.instance.onError` (main.dart) | `flutter.uncaught`; return `true` in release (handled), `false` in debug so the debugger still sees it. |

Add `ui`/`app` sources sparingly and descriptively; list every source you
add in a table in this section when implementing.

#### Implemented sources

| `source` | Site |
|---|---|
| `sync.pushDirty` | `SupabaseSyncEngine._logFailure` (push failures, two call sites) |
| `sync.pullSince` | `SupabaseSyncEngine._logFailure` (pull failures) |
| `sync.refreshNow` | `SupabaseSyncEngine._logFailure` (pull-to-refresh failures) |
| `sync.realtime` | `SupabaseSyncTransport.householdChanges` subscribe callback, context `status` |
| `flutter.framework` | `FlutterError.onError` in `main.dart` |
| `flutter.uncaught` | `PlatformDispatcher.instance.onError` in `main.dart` |
| `ui.inviteFlow` | `invite_flow.dart` |
| `ui.resetFlow` | `reset_flow.dart` |
| `ui.accountSignOut` | `account_section.dart` sign-out |
| `ui.accountSendMagicLink` | `account_section.dart` magic-link send |
| `ui.accountAdopt` | `account_section.dart` put-household-online (adopt) generic failure |
| `ui.accountLeaveHousehold` | `account_section.dart` leave household |
| `ui.accountDeleteAccount` | `account_section.dart` delete account |
| `ui.exportData` | `export_row.dart` |
| `ui.joinHouseholdSheet` | `join_household_sheet.dart` join step, any failure except `HouseholdSnapshotUnavailable` (expected outcome) |
| `ui.welcomeJoin` | `welcome_join_page.dart` join step, same exception |
| `app.notificationAction` | `notification_action_handler.dart` (background isolate: no sink is attached there, so this only reaches `debugPrint`) |
| `app.deleteAccountSignOut` | `household_exit_service.dart` best-effort sign-out after account erasure |

Deliberately NOT logged (expected outcomes or errors that are rethrown /
wrapped rather than swallowed): `ClaimedMemberRemovalFailure`
(`member_edit_sheet.dart`), the join code-entry step's `PostgrestException`/
offline mapping (`joinCodeErrorMessage` in `join_household_sheet.dart` and
`welcome_join_page.dart`), `HouseholdLinkService`'s step-1 classification,
`MemberService.deleteMember`'s wrap, `SupabaseHouseholdGateway`'s `23505`
rethrow.

### Deviations

- `PostgrestException` in the pinned `postgrest` 2.8.0 has no HTTP status
  field, so §2's optional `status=…` is omitted: the message is
  `postgrest code=<code>`.
- The About switch's semantic id is `settings-error-reports-switch` exactly
  as §6 specifies, which departs from the dotted `settings.about.*` ids of
  the neighbouring rows.

## 4. Upload

### 4.1 Triggers

`ErrorReporterController` (activated once from `main.dart`, like
`SyncEngineController`) calls `reporter.flush()` on:

1. startup (once the reporter exists),
2. app resume (`_AppResumeObserver`),
3. every successful pull: `ref.listen(settingsProvider.select((s) =>
   s.valueOrNull?.syncLastPulledAt), …)` — the pull writes this cursor at the
   end of every successful pull (`sync_engine.dart`), so no `SyncEngine`
   change is needed.

No timer, no backoff: sync's cadence is the pace.

### 4.2 `flush()`

1. If a flush is already running, return (single `bool` guard).
2. Gate — all must hold, checked on every flush: Supabase configured, signed
   in (`currentAuthUserProvider`), linked (`syncHouseholdId != null`),
   `errorReportsEnabled == true`. Otherwise return.
3. Read `pending(limit: 50)`; if empty return.
4. `transport.insertErrors(rows)` → Supabase
   `from('client_errors').upsert(rows, onConflict: 'id', ignoreDuplicates: true)`.
   **Never** a plain upsert (42501 lesson — no UPDATE grant exists). Do not
   chain `.select()` (no SELECT grant). Do not send `user_id` (server
   default `auth.uid()`) or `received_at`.
5. On success `markUploaded(ids, now)`; loop to step 3 at most 4 times
   (≤ 200 rows per flush).
6. A `PostgrestException` of class `22`/`23` (the server rejected the
   rows' data — retrying fails identically and would block every later
   report behind them, since pending is read oldest first): drop the
   batch by marking it uploaded, `debugPrint`, continue.
7. Any other exception: stop, `debugPrint` only (never `AppLog`), rows stay
   pending for the next trigger.

Row shape sent (snake_case): `id, source, error_type, message, stack,
context` (JSON object or null), `count, first_seen_at, last_seen_at,
app_version, platform, household_id`.

### 4.3 Semantics

- Rows recorded while signed out / unlinked are uploaded once the device is
  signed in and linked (accepted in brainstorming; covered by the
  disclosure).
- Switch off → nothing is uploaded, recording continues locally. Switch back
  on → still-pending rows go on the next trigger.
- Sign-out / leaving the household → the gate fails on the next flush.
- An uploaded row is never re-sent; a repeat of it starts a new local row.

## 5. Server

### 5.1 Migration `supabase/migrations/<ts>_client_errors.sql`

```sql
create extension if not exists pg_cron with schema pg_catalog;

create table public.client_errors (
  id            uuid primary key,
  user_id       uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  household_id  uuid,
  source        text not null check (char_length(source) <= 100),
  error_type    text not null check (char_length(error_type) <= 200),
  message       text not null check (char_length(message) <= 1000),
  stack         text check (char_length(stack) <= 8000),
  context       jsonb,
  count         integer not null default 1 check (count >= 1),
  first_seen_at timestamptz not null,
  last_seen_at  timestamptz not null,
  app_version   text not null check (char_length(app_version) <= 50),
  platform      text not null check (char_length(platform) <= 100),
  received_at   timestamptz not null default now()
);

create index client_errors_user_received_idx
  on public.client_errors (user_id, received_at desc);

alter table public.client_errors enable row level security;
revoke all on table public.client_errors from anon, authenticated;
grant insert on table public.client_errors to authenticated;
grant select (id) on table public.client_errors to authenticated;  -- ON CONFLICT (id) needs it
grant select, delete on table public.client_errors to service_role;  -- operator; not a default on newer stacks

create policy client_errors_insert on public.client_errors
  for insert to authenticated
  with check (user_id = (select auth.uid()));
-- ON CONFLICT also requires the conflicting row to pass a SELECT policy.
-- With the id-only grant this exposes at most the ids of one's own reports.
create policy client_errors_select_own on public.client_errors
  for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.prune_client_errors()
returns void
language sql
set search_path = public
as $$
  delete from public.client_errors
   where received_at < now() - interval '90 days';
  delete from public.client_errors c
   using (select id from (select id, row_number() over (
            partition by user_id order by received_at desc, id desc) as rn
          from public.client_errors) ranked where rn > 1000) extra
   where c.id = extra.id;
$$;
revoke execute on function public.prune_client_errors()
  from public, anon, authenticated;

select cron.schedule('prune-client-errors', '17 3 * * *',
                     'select public.prune_client_errors()');
```

`household_id` deliberately has no FK: error rows must never block or be
cascaded by household lifecycle. Not added to the realtime publication.
No UPDATE/DELETE for clients, and SELECT only of `id` on their own rows (what ON CONFLICT needs): the operator reads via MCP/dashboard
(service role / postgres).

### 5.2 pgTAP `supabase/tests/005_client_errors_test.sql`

Same harness as `004` (`test_login`). Assert:
1. an authenticated user can insert a row without `user_id`; it lands with
   `user_id = auth.uid()`;
2. inserting with another user's `user_id` throws `42501`;
3. re-inserting the same id with `on conflict do nothing` lives;
4. as authenticated, `select message from client_errors` throws `42501`,
   `select count(*)` sees only the caller's own rows (id-only grant), and
   `update`/`delete` throw;
5. `anon` cannot insert;
6. deleting the `auth.users` row cascades the user's error rows;
7. `prune_client_errors()` (run as postgres) deletes rows with
   `received_at` older than 90 days and keeps only the newest 1000 per user
   (insert 1002 rows for one user, check 1000 remain);
8. authenticated cannot execute `prune_client_errors()`;
9. the cron job `prune-client-errors` exists in `cron.job`.

### 5.3 Live smoke `test_live/client_errors_live_test.dart`

Copy the setup + loopback safety guard from `sync_tombstone_live_test.dart`.
Sign in a fresh user and call the **real** `SupabaseErrorReportTransport
.insertErrors` with two rows, then again with the same two rows (must not
throw — proves `ignoreDuplicates` needs no SELECT/UPDATE grant), then verify
with the service-role client that exactly two rows exist with that user's
`user_id`. Add `lib/application/error_reporter.dart` to `db.yml`'s change
filter.

### 5.4 Applying to prod

Done by Claude via the Supabase MCP `apply_migration` (replaces the
paste-SQL step in `docs/supabase-setup-checklist.md` for new migrations):

1. One-time: prod's `supabase_migrations.schema_migrations` was empty
   (every earlier migration was pasted by hand; all seven verified live on
   2026-10-04). Backfill those seven versions as applied.
2. `apply_migration` the new migration; rename the repo file to the version
   the MCP recorded so `supabase/migrations/` matches `list_migrations`.
3. Re-run advisors; check `cron.job`.

**As shipped (2026-10-04):** `apply_migration` was auto-declined in the
desktop app, so Igor pasted the migration in the SQL editor; Claude verified
RLS, policies, grants, the cron job and advisors read-only. Steps 1–2 are
deferred to the first migration that goes through the MCP
(`docs/supabase-setup-checklist.md` §1).

## 6. Settings switch

Settings → About, a switch row above the licenses row, using the existing
`SettingsRow(onSwitchChanged: …)` pattern, semantic id
`settings-error-reports-switch`. Bound to `Settings.errorReportsEnabled`
via a `SettingsRepository.setErrorReportsEnabled(bool)`. Shown always (also
signed-out — the value then governs future uploads).

| key | en | de |
|---|---|---|
| `settingsErrorReportsTitle` | Send error reports | Fehlerberichte senden |
| `settingsErrorReportsSubtitle` | Sends technical error details (no chore or member data) to the sync server to help fix bugs. Only when signed in. | Sendet technische Fehlerdetails (keine Aufgaben- oder Mitgliederdaten) an den Sync-Server, damit Fehler behoben werden können. Nur wenn du angemeldet bist. |

## 7. PRIVACY.md

- "Without an account": unchanged.
- "With an account" list, new bullet:
  > - error reports, unless you turn them off in Settings → About: when an
  >   error happens in the app, the time, app version, platform, where in
  >   the app it happened and the technical error message. They never
  >   contain chore titles, names, shopping items or your email. Reports
  >   are deleted after 90 days.
- "Deleting your data": add "Deleting your account also deletes its error
  reports."

## 8. Testing

- Unit: `ErrorScrubber` (§2), `ErrorLogRepository` merge/cap/pending/
  markUploaded on a real in-memory `AppDatabase`, `AppLog` with a recording
  sink (no sink → no throw; sink throws → no throw, no recursion),
  `ErrorReporter.flush` with a fake transport: gate (each of the four
  conditions false → no call), batching, success marks uploaded, failure
  leaves pending, concurrent flush guard.
- Sync: an engine test where the fake transport throws on push now asserts
  `AppLog` recorded `sync.pushDirty`.
- Widget: the About switch toggles `errorReportsEnabled`.
- Migration test v15 → v16.
- Server: pgTAP 005, live smoke (§5).
- Rules from the project: real in-memory DB + fixed clock, no mocked repos,
  never await drift streams outside the pump.

## 9. Out of scope

- "Share diagnostics" export of the local buffer (deferred; the buffer is
  designed so it is a single row + a formatter later).
- Any in-app UI showing errors to users; the D-5 indicator stays inferred.
- Breadcrumbs / non-error logging.
