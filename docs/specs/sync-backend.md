# Spec: Supabase backend & sync (G4/G5/G6 + protocol)

*Status: BINDING for the backend phase. Prerequisite gaps G4/G5/G6 from
docs/app-lifecycle.md are designed here, per the rule that they block any
backend code. Supabase project facts: docs/backend-supabase.md. Workflow
(user decision 2026-07-31): develop + test against a LOCAL Supabase stack
(Docker); the user pastes reviewed migrations into their project's SQL
editor — no credentials ever cross the chat boundary.*

## 0. Principles

- **Local-first stays.** The app remains fully functional offline and for
  never-signed-in users. Sync is an upgrade, not a requirement.
- **The household owns its data.** History (who did what) belongs to the
  household, not the individual account: leaving or deleting an account
  never rewrites history — profiles just become unclaimed (G6).
- **RLS is the security boundary** (not the anon key, not the client):
  every synced table gets policies scoped to household membership; the
  project's fail-closed settings (no auto-expose, auto-RLS) are backstop.
- **settings is device-scoped and never synced.**

## 1. Server schema (mirror of local, plus auth/invite glue)

Tables (snake_case, same columns/semantics as lib/data/db/tables.dart
unless noted): `households`, `members`, `categories`, `chores`,
`chore_assignees`, `chore_occurrences`, `shopping_items`.

Deltas vs local:
- All `id`/FK columns: `uuid` (client already generates UUIDv4 text).
- `created_at`/`updated_at`: `timestamptz`; **`updated_at` is
  server-maintained** by a `BEFORE INSERT OR UPDATE` trigger
  (`set_updated_at()`) — client-sent values are overwritten. This makes
  the pull cursor monotonic per the server clock (no device-clock trust).
- `households.created_by uuid references auth.users` — the creator.
- `members.user_id uuid references auth.users` — the claiming link (G5);
  UNIQUE per household (one profile per account per household).
- Soft deletes: `deleted_at` exactly as local; rows are never hard-deleted
  by sync (tombstones must replicate).
- New table `household_invites`: `id uuid pk`, `household_id fk`,
  `code text unique` (8-char unambiguous alphabet, server-generated),
  `created_by uuid`, `created_at timestamptz`, `expires_at timestamptz`
  (default now()+7d), `revoked_at timestamptz null`. Redemption is only
  possible through the RPC below — the table itself is not readable by
  non-members beyond what the RPC needs (SECURITY DEFINER).

## 2. RLS

- Helper `public.is_household_member(hid uuid) returns boolean` —
  SECURITY DEFINER, STABLE: true iff a `members` row exists with
  `household_id = hid AND user_id = auth.uid() AND deleted_at IS NULL`.
- Every data table: SELECT/INSERT/UPDATE allowed iff
  `is_household_member(household_id)` (for `chore_assignees` /
  `chore_occurrences`, via their chore's household — denormalize
  `household_id` onto both tables server-side to keep policies and
  realtime filters trivial; the client fills it on push). No DELETE
  policies anywhere (soft deletes only).
- `households`: SELECT iff member; INSERT iff `created_by = auth.uid()`;
  UPDATE iff member. Bootstrap ordering (create household then its first
  member row in one RPC `create_household(name, member_name, color)` —
  SECURITY DEFINER — avoids the chicken-and-egg INSERT policy).
- `members`: SELECT/UPDATE iff member of that household; INSERT only via
  RPCs (`create_household`, `redeem_invite`) — prevents self-inviting.
- RPCs (all SECURITY DEFINER, `set search_path = public`):
  - `create_household(p_name, p_member_name, p_color)` → creates
    household + creator's claimed member row; returns household id.
  - `create_invite(p_household_id)` → member-only; returns code.
  - `redeem_invite(p_code, p_member_name, p_color)` → validates
    (unexpired, unrevoked), then EITHER returns the list of unclaimed
    member profiles for the claiming step, or (companion RPC
    `claim_member(p_code, p_member_id)` / `join_as_new_member(p_code,
    p_member_name, p_color)`) links `user_id = auth.uid()` to an
    unclaimed profile or inserts a fresh member row (G5).
  - `delete_account()` (G6): unlinks `user_id` from all member rows
    (profiles + history stay with their households), deletes households
    where the caller is the ONLY claimed member (cascade soft-delete),
    then deletes the auth user via an edge function with service-role
    key (the RPC marks; the edge function `delete-user` finishes). The
    app then drops back to local-only mode; local data is untouched.
- **Tests: pgTAP** in `supabase/tests/` — the isolation matrix (member of
  A cannot read/write anything of B, for every table and every verb),
  invite lifecycle (expiry, revocation, double-claim rejection), RPC
  authorization (non-member cannot invite), trigger behavior
  (updated_at bumps on update, client-supplied value ignored). Run via
  `supabase test db` against the local stack; wired into CI later.

## 3. Sync protocol (client)

Family-scale data (hundreds of rows) permits a simple, robust engine:

- **Cursor pull**: per household, client stores `last_pulled_at`
  (server-clock timestamptz). Pull = for each table, rows with
  `updated_at > last_pulled_at` (RLS scopes it); new cursor = server
  `now()` fetched in the same round trip. Applied locally by plain
  row-replace (see LWW below).
- **Dirty push**: local schema v6 (backend phase, not before) adds a
  `sync_dirty` boolean (default true on every local write once the
  device is linked; set false after successful push). Push = upsert all
  dirty rows; the server trigger stamps `updated_at`.
- **Conflict rule (LWW per row)**: a pulled row overwrites the local row
  UNLESS the local row is dirty; a dirty local row wins locally and its
  push then wins on the server (server updated_at = push time). Two
  devices editing the same row: last push wins — acceptable for chores
  at family scale; occurrences are mostly-append which limits real
  conflicts. Tombstones (`deleted_at`) replicate exactly like updates.
- **Realtime**: `postgres_changes` subscription per household (filter on
  the denormalized `household_id`), feeding the same apply path as pull;
  a realtime event just short-circuits the polling interval. Pull runs
  on: app resume, post-push, subscription (re)connect.
- Engine lives behind an interface (`SyncEngine`) with a no-op local-only
  implementation; providers gate every feature on "linked or not".

## 4. G4 — adopting local data at first sign-in

After first successful auth with pre-existing local data, an explicit,
blocking choice (no silent merge, no silent loss):
1. **"Put my household online"** — uploads the local household verbatim
   (ids preserved; caller's member profile gets `user_id`); from then on
   this is the synced household. The natural path for the family's first
   device.
2. **"Join an existing household"** (invite code) — the local household
   is NOT merged: the app (a) writes an automatic JSON export of the old
   data (reuses the G8 exporter) into the app documents folder, (b)
   offers a one-time import of OPEN chores + unchecked shopping items
   into the joined household (new UUIDs, history stays in the archive),
   then (c) soft-archives the local household. Reversible only via the
   archive file — stated plainly in the UI copy.
Never-signed-in users never see any of this.

## 5. Client auth

- `supabase_flutter`, magic-link email (DESIGN.md decision). Deep link
  `famdo://auth-callback` (iOS URL scheme + Android intent filter — after
  the Famdo rename lands). Local stack uses Inbucket to read the mail in
  E2E/dev.
- UI: Settings gains an Account section (signed-out: email field + "Send
  sign-in link"; signed-in: email, household link state, "Leave
  household", "Delete account" (G6, double-confirm patterned on G9),
  sign out). Household screen gains "Invite" (shows/generates code) once
  synced.

## 6. Phasing

- **P1 (this round, local only)**: `supabase init`, initial migration
  (schema + triggers + RLS + RPCs), pgTAP suite green via
  `supabase test db`. Deliverable for the user: nothing to do yet.
- **P2**: auth UI + create/join/adopt flows (G4/G5) against the local
  stack; Maestro E2E with Inbucket-read magic links where feasible,
  widget tests elsewhere.
- **P3**: sync engine (v6 dirty flag, push/pull/LWW/realtime) + E2E
  two-client test harness (two simulators, one household) — stretch.
- **P4**: G6 delete-account edge function, leave-household, ownership
  transfer. First paste-SQL handoff to the real project at the END of
  P1 review (schema stabilized enough) or P2, user's call.
