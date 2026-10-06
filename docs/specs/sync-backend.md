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
    (profiles + history stay with their households), soft-deletes
    households where the caller was the ONLY claimed member (cascade),
    then deletes the auth user **itself, in the same RPC** —
    `delete from auth.users where id = auth.uid()`, legal because the
    function is `postgres`-owned and `SECURITY DEFINER`. **There is no
    edge function and no service-role key anywhere near the client.**
    This bullet described an RPC-marks / edge-function-`delete-user`-
    finishes split until 2026-08-28; decision **D-L4** in
    `household-lifecycle.md` §1 replaced it with the single RPC, and §5.1
    there is the verification record. The fallback analysis is retained,
    unimplemented, in Appendix A of
    `docs/plans/2026-08-08-household-lifecycle-slices-4-6.md`, for the day
    the in-RPC delete regresses. The `delete from auth.users` is the sole
    exception to this project's DELETE-is-granted-nowhere rule and does
    not generalise. The app then drops back to local-only mode; local data
    on the user's own device is untouched unless they tick the
    `household-lifecycle.md` §3.3 opt-in (D-L3).
- **Amendment 2026-10-06 (persona review D3; migration
  `20261006120000_join_funnel.sql`) — `peek_invite(p_code text) returns
  text`.** SECURITY DEFINER, `set search_path = public`, EXECUTE revoked
  from `public`/`anon`, granted to `authenticated` only. Returns the
  household `name` for a code that is active (not revoked), unexpired and
  whose household is not cascaded — validation delegated to
  `_valid_invite`; every rejection raises the single message
  `'invalid code'`. Reveals nothing `list_claimable_members` does not
  already give the same code holder. Client: `HouseholdGateway.peekInviteHouseholdName`,
  called right after `list_claimable_members` succeeds; the join chooser
  and its new claim confirm ("Join {household} as {name}?", §7.4
  amendment) show the name. pgTAP: `supabase/tests/006_join_funnel_test.sql`.
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

**Step-1 failure taxonomy (added 2026-08-14).** The resume rule above
stands, and its complement is now specified. `create_household` inserts
`households` by the client's own id, so a taken id raises SQLSTATE `23505`;
the client types that as `HouseholdIdTakenFailure`
(`supabase/tests/002_membership_exit_test.sql` pins the code). Combined with
the readability probe the resume rule already performs:

- **readable ⇒ resume.** Unchanged. Covers both a half-succeeded retry and
  a Disconnect → Adopt, since A1.2 disconnect leaves the caller's `user_id`
  on the server member row, so `is_household_member` still passes.
- **id taken AND not readable ⇒ TERMINAL** for this device and this
  household id. The household is online and this account is not a member of
  it — the state a removed member reaches, because the revocation handling
  clears the sync link but keeps every local row, server household id
  included. Retrying re-sends the same id forever. Surfaced as a
  non-retryable, untappable state on the same `settings.account.adopt` row
  that names join-by-code as the recourse; it is per-visit widget state, not
  persisted, because a user who rejoins and later disconnects genuinely can
  adopt again.
- **anything else ⇒ retryable.** Unchanged. In particular a network failure
  inside the readability probe propagates before any classification, which
  is correct: an unreachable server is not a dead end.

Turning a removed member's local copy into an INDEPENDENT online household
("fork") was considered and deliberately NOT built — see OPD-1 in
`docs/plans/2026-08-14-reconnect-adopt-hardening.md` and its backlog row,
which records why re-keying the household id alone is insufficient.

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

> **Amendment 2026-10-06 (persona review B6, D6, D7) — signposting.** The
> adopt row's subtitle now leads with the family: "Put it online so your
> family can join with an invite code. Also keeps your other phones in
> step." Adopt is no longer one tap: a confirm sheet "Put '{household}'
> online?" states what is uploaded (members, chores, completion history,
> notes, shopping list), where (the sync server, under your account) and how
> to take it down (Delete my account / Leave the household); only "Put
> online" (`settings.account.adopt.confirm`; Cancel is
> `settings.account.adopt.cancel`) runs `HouseholdLinkService.adopt`. A
> "Try again" after a failed attempt skips the sheet. A LOCAL household's
> Members screen shows a disabled Invite row (`settings.members.inviteLocal`,
> "Sign in first to invite your family", no `onTap`) where the real one will
> be — hidden under the Noop gateway, which has no sign-in. The invite share
> text ends with the install link
> `https://github.com/igorzamyslov/chore-app/releases/latest`.

> **Amendment 2026-10-06 (persona review D5) — invite code lifecycle.**
> `runInviteFlow` first asks `HouseholdGateway.activeInvite(householdId)`
> (a plain select on `household_invites`: `revoked_at is null and
> expires_at > now`, newest first). If a code is active, the sheet re-shows
> THAT code with "Valid until {date}" (`DateFormat.yMMMd`, id
> `settings.members.invite.validUntil`) and a "New code" text button
> (`settings.members.invite.newCode`) — nothing is revoked by opening the
> sheet. "New code" confirms ("Replace the shared code?" / "Anyone still
> joining with the old code will need this new one.", ids
> `settings.members.invite.replace.confirm` / `.cancel`) and only then runs
> the revoke-then-create pair above. With no active code the flow creates
> one directly, as before. On the join side, `joinCodeErrorMessage` keeps
> the "typo" copy only for a `PostgrestException` whose message contains
> `invalid` or `expired`; any other `PostgrestException` reads "Couldn't
> check the code right now — try again in a moment."

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

> **Amendment 2026-10-06 (persona review D3) — name the household, confirm
> the claim.** Once the code is accepted, the client also calls
> `peekInviteHouseholdName` (§2 amendment). The chooser heading becomes
> "Which one is you in {household}?" and, on the welcome join subpage, the
> AppBar title becomes the household name. Tapping a profile no longer
> claims it: a dialog "Join {household} as {name}?" / "You'll see and mark
> the chores assigned to {name}. Pick another name if this isn't you."
> (ids `join.claim.cancel` / `join.claim.confirm`) comes first, and only
> Join proceeds (to the import offer in the Settings sheet; to the join
> itself on the welcome subpage). The invite sheet carries the hint "Add
> everyone under Members first — they'll pick their own name when they
> join." so joiners claim a pre-created profile instead of duplicating it
> via "I'm new here".

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

**The probe contract (added 2026-08-14).**

- `findMyMembership` filters `deleted_at` on BOTH selects, orders the
  `members` select by `created_at` descending before its `limit(1)`, and
  returns `null` rather than a `MyMembership` with a blank household name.
  The ordering makes the legitimate multi-household case (an account may
  claim a member in several households — `delete_account`'s own comment
  relies on it) deterministic instead of dependent on Postgres row order:
  the household joined last is the one a returning device is most likely
  returning to. `created_at` is exact for join-as-new and adopt and
  approximate for `claim_member`; `updated_at` is NOT a substitute, being
  trigger-maintained and therefore a recency signal for activity rather
  than for joining. A chooser is the real answer and is backlogged; the
  auto-pick is acceptable meanwhile only because every path that renders
  the offer displays the household NAME, so the user can decline it.
- Those `deleted_at` predicates are **defense in depth, not the boundary**.
  `public.is_household_member` is the boundary — it requires the caller's
  own `members` row to be active, and `_cascade_if_orphaned` never
  soft-deletes a household that still has a claimed active member, so
  neither predicate changes a reachable result today.
  `supabase/tests/002_membership_exit_test.sql` now proves both directions,
  so weakening `is_household_member` turns a test red rather than turning a
  destructive replace live.
- **The replace is CONDITIONAL.** Reconnect skips the claim RPC (as specced
  above), so the downloaded snapshot is the ONLY authorization evidence the
  flow ever sees — and RLS filters rows rather than erroring, so a refusal
  arrives as a *successful* download of an empty snapshot. An absent
  household row (all three `JoinChoice` variants), or an absent or
  soft-deleted member row for the reconnecting member (`ReconnectChoice`
  only, since it is the sole variant with no server-side authorization
  step), aborts the whole flow **before** anything local is deleted. This
  is the one place §7.4's "the whole replace is one local transaction"
  needs a precondition stated OUTSIDE the transaction: the guard runs
  before it opens, so the failure is provably non-destructive rather than
  merely rolled back. The already-written archive is left in place — a
  spare archive file is harmless, a deleted household is not (there is no
  in-app importer; backlog G-3 / F12). The failure is surfaced with its own
  copy, and the offer that produced it is retired by re-probing
  `findMyMembership`.

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

**Amendment 2026-10-06 (persona + technical review, plan
`docs/plans/2026-10-06-persona-review-fixes.md` W1).** The bullets above
stand; the following refine them. Findings are numbered as in
`docs/feedback/2026-10-06-personas/technical-review.md`.

- **Paging (#2).** PostgREST silently truncates every response at
  `max_rows` (1000). Every full-table read — `SyncTransport.pullTable` and
  each per-table read in `HouseholdGateway.downloadHousehold` — asks for
  `syncPageSize` (= 1000) rows at a time, ordered by `updated_at` then the
  primary key (`id`, or `chore_id, member_id` for `chore_assignees`), and
  keeps going until a page comes back shorter than the page size. A failure
  on any page fails the whole pull, so the cursor never advances past rows
  that were not fetched.
- **Cursor overlap (#3).** Postgres' `now()` is the transaction START time,
  so a push whose transaction began before our `server_now()` read and
  committed after a table read is stamped below an exact cursor and would
  never be pulled. The cursor is stored as `server_now() − syncCursorOverlap`
  (30 s). The re-fetch this causes is idempotent: a pulled row that equals
  the local row (data-class equality) is **not rewritten**, so a re-apply
  fires no table update and cannot feed the write listener into a
  push/pull loop.
- **Per-table push with quarantine (#5).** `_pushAll` never throws. Each
  table is pushed in its own try/catch and the sequence continues past a
  failure. A batch the server **rejects** — a `PostgrestException` whose
  SQLSTATE class is `22`, `23` or `42` — is retried row by row; a row still
  rejected is *quarantined*: left dirty, skipped for this tick, and recorded
  once per engine session as `AppLog.error('sync.rejected', …, context:
  {table, id})` (deduplicated by `table:id`). A rejected tombstone stays in
  the outbox the same way. Any other failure (network, server down) is
  retry-later as before and is logged once per tick as `sync.pushDirty`.
  `pushDirty` skips its follow-up pull only on an ordinary failure, never
  because of a quarantined row.
- **`refreshNow()` returns `RefreshOutcome`** (`ok` | `offline` |
  `rejected`) instead of a bool: `rejected` if any row was quarantined this
  run, `offline` on any other failure (including a revocation discovered by
  the pull), else `ok`. The UI mapping is in `sync-freshness.md` §2.3.
- **One pull in flight; own echo ignored (#17).** `pullSince()` and
  `refreshNow()` join a running pull instead of starting a second one, so
  two pulls can never interleave and race each other's cursor write. A
  realtime `householdChanges` event within `realtimeEchoWindow` (1 s) of our
  own successful push is dropped as the server echoing rows we just wrote
  (the push's own follow-up pull already fetched them); a genuine
  other-device change inside that window is caught by the next poll tick.
- **A chore's assignee list is one LWW value (#8).** On pull, the
  `chore_assignees` rows and tombstones are grouped per chore. If the local
  chore row is dirty — or any of its local assignee rows is — nothing is
  applied for that chore (local dirty wins for the whole list). Otherwise,
  if any live row was pulled, the local list is replaced by the pulled list
  (delete then insert, positions as pulled); if only tombstones were pulled
  (a pull landing between the other device's row push and its tombstone
  push), only those members are deleted. Rows are never merged one by one:
  that produced a union with duplicate `position`s and a per-device
  rotation order. `_currentAssigneeIds` tie-breaks `position` by `memberId`
  as defence in depth.
- **Device-clock pull stamp (#7).** After every successful pull the engine
  reports `clock.now()` (device time) through `onPullCompleted`;
  `syncLastPullCompletedAtProvider` holds it for the session. The cursor
  stays server time for correctness; health and "Last synced" read the
  device stamp (`sync-freshness.md` §2.5 amendment).

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

- ~~`chore_assignees` has no tombstones~~ — superseded by §8.6 (the
  server columns existed all along; only the client never used them).
- `households` and `members` push via UPDATE/insert-ignore respectively
  (their fail-closed grants forbid literal upserts) — an extension of
  §7.2's members reasoning, applied engine-wide.

### 8.6 Hard-delete tombstones (client schema v15) — binding

**The bug this fixes (found 2026-10-03).** Three local writes HARD-delete
synced rows, and a hard delete has no row left to mark dirty, so the push
path never saw it: the server copy stayed live forever, and every other
device kept it.

| Site (`ChoreRepository`) | Deletes | Reached from |
|---|---|---|
| `softDeleteChore` | the chore's pending occurrence | chore delete |
| `deletePendingOccurrences` | the chore's pending occurrence(s) | pause, schedule edit (`ChoreService.updateChore`), reopen |
| `updateChore` (assignee rewrite) | every `chore_assignees` row of the chore, then re-inserts the new set | chore edit |

Visible effect on the OTHER device: after a pause→resume, a schedule edit
or a reopen there are TWO pending occurrences of one chore (the ghost plus
the new one) — a chore card that "was deleted" still shows, and
`ChoreRepository.pendingOccurrenceOf` (`getSingleOrNull`) throws, which
breaks `catchUpOverdue` on that device. Removed assignees resurrect on
every device that pulls them. (A soft-deleted *chore* itself did sync —
its `deleted_at` is pushed — and its leftover pending occurrence is hidden
by the `chores.deleted_at IS NULL` display filters, but it is still a
ghost row on the server.)

The server already has `deleted_at` on `chore_occurrences` and
`chore_assignees` (initial schema) and grants UPDATE on both. **No server
migration.** Locally these two tables keep their hard-delete semantics —
no `deletedAt` column, no query changes; a tombstone is an outbox entry.

1. **Outbox table `SyncTombstones`** (schema v14→v15, `createTable`):
   `id` integer autoincrement PK, `entity` text (`'chore_occurrences'` |
   `'chore_assignees'`), `rowId` text (occurrence id, or the assignee's
   `chore_id`), `memberId` nullable text (assignees only), `deletedAt`
   text (ISO UTC, the same `_isoNow()` clock as the delete). Not a synced
   table: no `syncDirty`, never pulled, never uploaded by adopt.
2. **Recording.** The three sites above insert one tombstone per row they
   actually delete, in the same transaction as the delete (select the
   victims first, then delete). `updateChore`'s assignee rewrite
   tombstones only members in old-set minus new-set — a member kept
   across the edit is re-inserted dirty and needs no tombstone.
   Local WIPES are not deletions and record nothing: `data_reset.dart`
   and `HouseholdJoinService`'s replace both also clear `SyncTombstones`.
3. **Push** (`_pushTombstones`, runs LAST in `_pushAll`, after
   `_pushShoppingItems`): for each tombstone, oldest first — if a local
   row with that key exists again (assignee re-added), drop the tombstone
   without a network call; else `SyncTransport.markDeleted(entity, key,
   deletedAt)` → PostgREST `update({'deleted_at': ...})` matched on the
   key (`id`, or `chore_id`+`member_id`) — never an upsert (a tombstone
   carries no full row). An UPDATE matching zero rows (never pushed) is
   success. Then delete exactly that tombstone row by `id`. Throws like
   every other push step.
4. **Resurrection on push.** `choreAssigneeRow` and `choreOccurrenceRow`
   send `'deleted_at': null`, so re-adding a previously removed assignee
   (same composite key) un-tombstones the server row.
5. **Pull.** A pulled `chore_occurrences`/`chore_assignees` row with
   non-null `deleted_at` is applied as a local hard delete of that key —
   unless the local row exists and is `syncDirty` (local dirty wins, the
   same LWW rule as §8.3; the dirty row's push then sends
   `deleted_at: null`). The P2 full download (`downloadHousehold`, used by
   join/reconnect) skips such rows entirely.
6. **Ghost repair** (the rows the old client already orphaned). Inside
   the pull transaction, after applying, for every chore of the household
   with MORE THAN ONE pending occurrence: keep the one with the greatest
   `updatedAt` (tie: greater `dueDate`, then greater `id`), hard-delete
   the others through the same tombstone-recording path as §8.6.2. The
   product invariant is "at most one pending occurrence per chore"
   (`occurrence-lifecycle.md`), so a second one can only be a ghost; the
   latest-`updatedAt` survivor is the one a schedule edit, resume or
   reopen just wrote. Converges: the device that already has one pending
   pulls the tombstone as a no-op.
7. **Trigger.** The engine's write listener also watches `SyncTombstones`.
8. **Testing.** Engine tests with the fake transport (push sends
   `markDeleted` and clears the outbox; re-added assignee drops its
   tombstone with no call; pull of a tombstoned occurrence deletes the
   clean local row and keeps a dirty one; ghost repair keeps the right
   survivor and records a tombstone); repository tests for the three
   recording sites; a v14→v15 migration test; and a live test
   (`test_live/`, real `SupabaseSyncTransport` against the local stack in
   `db.yml`) proving `markDeleted` really sets `deleted_at` under RLS and
   that a second client's `pullTable` sees it.

**Amendment 2026-10-06 (technical review #1, #4, #6).**

- **Tombstones only kill the pending row (#1).** Every local site that
  hard-deletes an occurrence deletes PENDING rows only, so an occurrence
  tombstone means "the pending row is gone" — not "this id is gone". The
  push matches `{'id': …, 'status': 'pending'}` (`markDeleted` filters on
  every entry of the match), and `applyPulledOccurrenceDeletion` adds
  `status = pending` to its WHERE. Hence a completion recorded and pushed
  on device A survives a concurrent delete/edit/pause on device B: B's
  tombstone matches nothing on the server, and B pulls the completion back.
  Item 5 above reads with that extra condition.
- **Convergent survivor key (#4).** Item 6's survivor is now the pending
  occurrence with the greatest `dueDate`, tie-broken by greater `id`.
  `updatedAt` left the key: a locally written stamp is device time and a
  pulled one is server time, so two devices comparing the same two rows
  could each keep a different one and tombstone the other's, leaving the
  chore with no pending row anywhere. See §8.7.
- **Timestamps are normalised at the boundary (#4).** Every `*FromRow`
  mapper rewrites each `*_at` value as
  `DateTime.parse(s).toUtc().toIso8601String()` (a `Z` suffix, like every
  local write), so local and pulled stamps share one format wherever they
  are compared as text (the guarded dirty-clear). A value that does not
  parse is passed through unchanged rather than failing the pull.
- **Repair is reachable without a pull (#6).** `repairGhostOccurrences`
  is callable outside the pull transaction (it only touches pending rows),
  and `ChoreService.catchUpOverdue` runs it for the household before
  iterating chores, so an unlinked device — or a race between a local
  insert and a pull that already repaired — is healed at the next catch-up.
  `ChoreRepository.pendingOccurrenceOf` is tolerant meanwhile: it orders by
  `dueDate` desc, `updatedAt` desc and takes one row instead of
  `getSingleOrNull()`, so two pending rows can no longer throw out of
  bootstrap.

### 8.7 Invariants (added 2026-10-06)

These hold across every device of a household, and every sync rule above
must preserve them:

1. **Survivor selection uses only fields both devices see identically
   (`dueDate`, `id`).** Any rule that picks one row over another for
   convergence — ghost repair today, anything similar tomorrow — must not
   read `updatedAt`, `createdAt` or any other stamp that one device wrote
   from its clock and the other received from the server.
2. **A tombstone names the state it deletes.** An occurrence tombstone
   deletes a *pending* row; it never deletes a row that has since become
   `done`, `skipped` or `missed`. Local hard deletes only ever delete
   pending occurrences, so this is the semantics the outbox already has.
3. **The pull cursor never advances past a row that was not applied.** Every
   page of every table is fetched before the single apply transaction, and
   the cursor is written only after that transaction commits — with the
   overlap, so a transaction-start-stamped row is never skipped.
4. **Re-applying what is already local is a no-op.** A pulled row equal to
   the local row writes nothing; a pulled assignee list equal to the local
   list writes nothing. This is what lets the overlap re-fetch be free.
5. **One bad row never blocks another.** Push proceeds per table and, on
   rejection, per row; the rejected row is quarantined and reported, the
   rest keep flowing, and the pull is never conditional on the push.

### 8.8 Shopping field-level merge (amendment 2026-10-06, finding A9)

§8.3's rule "a pulled row never overwrites a locally dirty row" is a
whole-row, last-PUSH-wins rule: which device's version survives is decided
by when each device manages to push, not by when the human acted. For most
tables that is accepted at family scale. For `shopping_items` it loses data
in an ordinary trip: Tom ticks "Milch" and presses *Clear checked* with no
reception (row = deleted, dirty); at home his partner re-adds or un-checks
the same item; Tom's phone reconnects and pushes its older `deleted_at`
over her newer edit, and her request vanishes without a message on either
phone.

**Rule.** `SyncRepository.applyPulledShoppingItem`, when the local row is
dirty AND the pulled row's `updatedAt` (already normalised by `utcIso`, and
compared as instants) is later than the local `updatedAt`:

- writes the pulled `checkedAt` and `deletedAt` onto the local row;
- keeps the local `name`, `quantityNote`, `categoryId` and `updatedAt`;
- keeps `syncDirty = true`, so the local fields still go out on the next push
  (and the guarded dirty-clear, which matches on `updatedAt`, still matches).

If the pulled row is not newer, or the local row is clean, the §8.3 rules
apply unchanged (dirty local wins; clean local is replaced).

**Why only those two fields.** `checkedAt` and `deletedAt` are the *state*
of the item ("is it still wanted, is it in the cart"); the later edit of
that state is the one that reflects the household's current intent.
`name`, `quantityNote` and `categoryId` are descriptive; letting a pulled
value replace a half-typed local rename would be a worse surprise than
last-push-wins on those fields, which stay as before. Brand-new items are
separate rows with their own UUIDs and never conflict.

**Residual.** The comparison uses each device's clock for `updatedAt` on
the local row and the server's for the pulled row, so a badly skewed device
can pick the wrong side; this is the same exposure §8.7 invariant 1
documents and is accepted. Test: `test/application/sync_engine_test.dart`,
group "shopping field-level merge".
