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
- **D1 (2026-08-07): a household is flat by design, not admin/member.**
  `members.role` is set once at creation (`create_household` makes the
  caller `admin`; every join/claim path leaves the joiner `member`) but
  gates nothing — no RLS policy above, no RPC, no client widget branches on
  it (grepped: zero `MemberRole` checks in `manage_members_screen.dart`,
  `account_section.dart`, `household_rename_sheet.dart`). The one place the
  client reads it at all is `actingMemberProvider`'s default-member
  tie-break (`lib/app/providers.dart`, spec
  `docs/specs/members-management.md` §2: "first admin, else first member")
  — a plausible-default guess for which member a fresh device is probably
  acting as, not a capability check; it grants that member nothing the
  others don't already have. Every member of a
  household can equally rename it, invite, remove other members, and edit
  anything — this is the actual, intentional model (a family is a circle of
  equals), not an oversight to be closed later. `role` is **vestigial**:
  keep writing it (removing the column is a migration, out of scope here),
  but treat it as inert until a real spec change gives it meaning. Do NOT
  add role-based enforcement on the strength of this decision. An earlier
  draft of this finding also recommended revoking the `members` UPDATE
  grant's `deleted_at` column (so one member couldn't soft-delete another)
  — **that recommendation is withdrawn**: member removal (shipped
  `docs/feedback/2026-08-01-ux-audit.md` A1) replicates to the server
  through exactly that grant (`SupabaseSyncEngine._pushMembers`,
  `lib/application/sync_engine.dart:464-490`, sends `deleted_at` as one of
  the four granted columns on every member push), so revoking it would
  silently stop member deletions from ever syncing. §7.2/§8.1's `members`
  grants (name, color, role, deleted_at) stay exactly as they are.
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
  the denormalized `household_id`), feeding the same apply path as pull.
  REQUIRES the synced tables be in the `supabase_realtime` publication
  (migration `20260801160000`; empty by default — found live 2026-08-01
  when realtime silently no-op'd while push/pull worked);
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

## 7. P2 client design (binding for slices P2b/P2c)

P2a (auth foundation: `AuthGateway`, Account section, deep links) landed
2026-08-01. The remaining P2 work splits into P2b (first device: adopt +
invite) and P2c (second device: join), both against this section.

### 7.1 Local linked-state (client schema v6)

`Settings` gains two nullable text columns, always set/cleared together:

- `syncHouseholdId` — the server household this DEVICE is linked to.
- `syncLinkedAt` — ISO timestamp when linking completed.

"Linked" ⇔ `syncHouseholdId != null`. Migration v5→v6 adds both columns
(nullable, default null); no data rewrite. NOTE: §3's "schema v6 adds
sync_dirty" is hereby renumbered — the dirty flag and `syncLastPulledAt`
cursor become client schema **v7** in P3.

### 7.2 HouseholdGateway (the second and last Supabase seam)

`lib/application/household_gateway.dart`, exactly parallel to
`AuthGateway`: interface + `NoopHouseholdGateway` (every method throws
`StateError`; unreachable because the UI gates on a signed-in user, which
Noop auth never produces) + `SupabaseHouseholdGateway`. Widget tests use a
fake. Methods mirror the P1 RPCs and the two bulk paths:

- `createHousehold(householdId, name, memberId, memberName, memberColor)`
  → RPC `create_household` (ids preserved — the RPCs take client UUIDs).
- `uploadHouseholdData(snapshot)` — PostgREST upserts, in FK order:
  members (the non-caller ones, `user_id` null), categories, chores,
  chore_assignees, chore_occurrences, shopping_items. Verbatim rows,
  tombstones included. Idempotent so a failed upload is re-runnable
  as-is. Members specifically use insert-with-ignore (ON CONFLICT DO
  NOTHING), not a real upsert: the fail-closed grants give UPDATE on
  members for (name, color, role, deleted_at) only, and Postgres checks
  UPDATE privilege on an upsert's whole SET list at plan time — a full-row
  members upsert is rejected (42501) even when no conflict occurs.
- `createInvite(householdId)` → code (8 chars).
- `revokeActiveInvites(householdId)` — PostgREST update stamping
  `revoked_at` (client-authored ISO timestamp) on every currently-active
  invite (`revoked_at is null`); called BEFORE `createInvite` at both
  entry points (spec `docs/feedback/2026-08-01-ux-audit.md` A3: one live
  code per household).
- `listClaimableMembers(code)` → `[(memberId, name, color)]`.
- `claimMember(code, memberId)` → householdId.
- `joinAsNewMember(code, memberId, name, color)` → householdId.
- `downloadHousehold(householdId)` → snapshot (plain selects; RLS scopes).

Snapshot type: a plain class of typed row lists; the Supabase impl owns
snake_case/ISO mapping (per-table mapping read off the P1 migration file).

### 7.3 P2b — adopt ("Put my household online") + invite

Account section, signed-in AND unlinked (banner-not-modal convention:
"blocking" in §4 is satisfied because nothing syncs until a choice is
made): shows the two choice rows (`settings.account.adopt`,
`settings.account.join`) with one line of explanatory copy each.

Adopt steps, in order, resumable at every point:
1. RPC `create_household` with the LOCAL household id + name and the
   ACTING member's id/name/color (the acting member is "the caller's
   member profile" of §4; server makes it admin + sets `user_id`).
2. `uploadHouseholdData` (everything else, upsert = retry-safe).
3. Local: acting member's role → admin (mirror the server rule).
4. Local: set `syncHouseholdId`+`syncLinkedAt` (only after 1–2 succeed).
Failure surface: inline error state + "Try again" on the adopt row —
rerunning is safe (RPC failure on rerun after a half-success: treat
"household already exists with my user as member" as step-1 success and
continue with 2).

Invite: once linked, the Members screen gains an "Invite" row
(`settings.members.invite`), and the Account section's signed-in tile
gains a "linked" subtitle (household name) plus its own "Invite a
member" row (`settings.account.invite`, spec
`docs/feedback/2026-08-01-ux-audit.md` B3) right below it -- both share
one handler (`runInviteFlow`,
`lib/features/settings/invite_flow.dart`): `revokeActiveInvites` (spec
A3 -- one live code per household, so creating a new one is how you
revoke the old one) → `createInvite` → bottom sheet with the code in
large type + a share button (share_plus).

### 7.4 P2c — join ("Join an existing household")

From the join row: enter code (`settings.account.join.code` field) →
`listClaimableMembers` → chooser: each unclaimed profile ("Are you
Anna?") + "I'm new here" → `claimMember` or `joinAsNewMember` (new UUID,
name prompt, auto color). Then, per §4, strictly in this order:
1. Automatic JSON export (G8 exporter) written to the app documents dir
   (filename `famdo-archive-<date>.json`); abort the whole join if this
   write fails.
2. Import offer, IN-FLOW (amended 2026-08-01; a post-replace banner
   can't work — the offer's source rows are exactly what step 3
   deletes, so the choice must happen while they still exist): one
   screen/sheet step "Bring over your open chores and unchecked
   shopping items?" with accept/decline. On accept, the open chores
   (new UUIDs, no history) + unchecked items are captured NOW and
   carried into step 3.
3. `downloadHousehold` → replace: soft-archive = local rows of the old
   household are DELETED after the export succeeds (the file IS the
   archive; UI copy states this plainly), snapshot inserted, settings
   repointed (actingMemberId = claimed/new member, linked fields set),
   accepted import copies inserted locally AND pushed via
   `uploadHouseholdData` of just those rows. Client-side the whole
   replace is one local transaction; the post-replace UI must re-resolve
   the bootstrap household (provider invalidation), since the household
   id changes.

### 7.5 Testing

- Widget tests: `FakeHouseholdGateway` (third override on top of
  db/clock + auth fake), covering adopt success/retry, join
  claim/join-new, export-fails-aborts-join, import-offer accept/dismiss.
- E2E stays fully offline (empty SUPABASE_* defines → 'coming soon');
  live-stack flows are exercised manually against `supabase start` and,
  as a P3 stretch, via the two-simulator harness.
- pgTAP already covers the server side; no new SQL in P2b/P2c.

### 7.6 P2d — reconnect (returning device)

Gap found 2026-08-01: a user whose profile is ALREADY claimed by their
account (phone reset, new phone) cannot rejoin — `list_claimable_members`
only offers unclaimed profiles, and "I'm new here" would duplicate them.
No server change needed: their account IS a member server-side, so RLS
already grants full read access.

- `HouseholdGateway` gains `findMyMembership()`: PostgREST select on
  `members` where `user_id = auth.uid()` (RLS-scoped anyway), returning
  (householdId, memberId, householdName via a joined/second select) or
  null.
- Account section, signed-in AND unlinked: BEFORE showing adopt/join,
  probe `findMyMembership()`; when non-null, show a third row FIRST
  (`settings.account.reconnect`): "Reconnect to <household>" with copy
  stating it replaces local data (same archive guarantee as join).
- Flow: reuse the join machinery with a new `ReconnectChoice(memberId)`
  that SKIPS the claim RPC (already claimed — idempotency also covers a
  re-claim, but no call is cleaner) and skips code entry entirely; the
  archive-first ordering, import offer, download/replace, and
  settings-repoint steps are identical to §7.4.
- Tests: fake gateway returns a membership → reconnect row appears and
  completes the replace; returns null → adopt/join rows as today;
  linked → no reconnect row.

### 7.7 P2 verification record

2026-08-01: full live smoke test against the local stack passed —
magic-link sign-in (Mailpit → PKCE verify → `famdo://` deep link), adopt
(RPC + bulk upload), invite sheet, second-device join with claim,
download/replace, both devices linked; server roster verified in SQL.
Idempotent claim/join retries hardened server-side (migration
20260801130000, pgTAP 31 green).

## 8. P3 client design (binding for the sync engine)

Everything below rides on §3's protocol; this section pins the client
shapes so implementation slices need no further design decisions.

### 8.1 Client schema v8

- Every synced table (`households`, `members`, `categories`, `chores`,
  `chore_assignees`, `chore_occurrences`, `shopping_items`) gains
  `syncDirty` BoolColumn, default FALSE, non-null. Migration v7→v8 adds
  the columns; existing rows stay false (a linked device's rows are on
  the server already — P2 uploaded/downloaded them; unlinked devices
  never push anyway).
- `Settings` gains `syncLastPulledAt` (nullable text, server-clock ISO
  from the pull round trip — never the device clock).
- Repositories mark `syncDirty: true` on EVERY local insert/update of
  synced rows (including soft deletes; a shared drift helper, not
  copy-paste in every method). The flag is set unconditionally — also
  while unlinked or signed out; it's meaningless until linked, cheap to
  keep accurate, and makes "link later" push everything that changed.
  The ONLY writers that clear it (set false) are the engine's
  post-push confirmation and the pull's row-replace.

### 8.2 SyncEngine seam

`lib/application/sync_engine.dart`: `abstract class SyncEngine` with
`Future<void> pushDirty()`, `Future<void> pullSince()`, `void start()`,
`void stop()` (start = begin realtime subscription + resume-triggered
pulls; idempotent). `NoopSyncEngine` (all no-ops) when Supabase is
unconfigured OR the device is unlinked; `SupabaseSyncEngine` otherwise —
provider `syncEngineProvider` re-evaluates on the linked state
(watches settingsProvider's `syncHouseholdId`).

### 8.3 SupabaseSyncEngine behavior

- **pushDirty**: per table in FK order, select rows where
  `syncDirty == true`, upsert to the server (members via
  insert-with-ignore + a second UPDATE limited to the granted columns
  (name, color, role, deleted_at) for already-existing rows — the §7.2
  grants constraint applies to the engine too), then clear the flag on
  exactly the pushed row ids IN THE SAME order they were read (a row
  dirtied again mid-push must stay dirty: clear with
  `WHERE id IN (...) AND updated_at == <the value read>` or re-check
  dirty rows after clearing — implementer's choice, tested either way).
- **pullSince**: one round trip fetching server `now()` FIRST (an RPC
  `server_now()` — new one-line SECURITY INVOKER function, add to the
  migrations + checklist), then per table rows with
  `updated_at > syncLastPulledAt` (RLS scopes to the household). Apply
  LWW per §3: replace the local row UNLESS its `syncDirty` is true
  (local dirty wins; the next push settles it). Occurrences/chores
  referencing not-yet-pulled parents: apply tables in FK order within
  one local transaction. Set `syncLastPulledAt` to the fetched server
  now() only after the transaction commits.
- **Triggers**: pull on (a) `start()`, (b) app resume (reuse the
  CatchUpController's lifecycle hook pattern — do NOT add a second
  lifecycle observer), (c) after every successful push, (d) realtime
  `postgres_changes` event for the household (the event only
  short-circuits the timer — the payload is ignored; data always comes
  from the pull path). Push on: any local write while linked (debounced
  ~2s), app resume, reconnect, and (B-6, `docs/backlog.md`) the 60s
  foreground safety-net poll defined below in `sync-freshness.md` §2.2 --
  the same timer already used for the pull safety net now retries anything
  still dirty on every tick too, not only on resume. The poll's pull half
  is unconditional: a push failure on one tick must never suppress that
  tick's pull (see `sync-freshness.md` §2.2 and
  `SupabaseSyncEngine._pollTick`'s doc comment for why).
- **Failure posture**: every engine error is swallowed into a silent
  retry-later (log in debug); the app NEVER surfaces sync errors in P3
  (local-first: the UI is always consistent with the local db).

### 8.4 Testing

- Unit/widget: FakeSyncEngine recording calls; engine logic tested
  against the in-memory db with a FakeHouseholdGateway-style transport
  fake (no live Supabase in the suite).
- LWW matrix as service-level tests: pulled-newer vs local-clean
  (replace), pulled vs local-dirty (keep local), tombstone pull
  (deletedAt replicates), dirty-tombstone push.
- The two-simulator live test (§6 P3 stretch) stays manual, following
  the §7.7 smoke-test method.

### 8.5 Known limitations (P3, accepted)

- `chore_assignees` has no tombstones (no `deleted_at` locally or on the
  server, a P1 schema decision): removing an assignee deletes the local
  row, which the push path cannot propagate — only inserts/replacements
  sync. Practical impact is small (assignee edits regenerate the full
  set, and the next full edit from any device converges it), but precise
  removal propagation needs a schema change; revisit with P4.
- `households` and `members` push via UPDATE/insert-ignore respectively
  (their fail-closed grants forbid literal upserts) — an extension of
  §7.2's members reasoning, applied engine-wide.
