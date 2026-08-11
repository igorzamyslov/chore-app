# Household Lifecycle (P4) — Slices 1–3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the server-side membership-exit surface (leave / remove /
delete-account / orphan cascade), close the two local claim-state gaps, and
replace the silent-revocation trap with an honest notice — without shipping
any of the three exit UIs yet.

**Architecture:** Three `SECURITY DEFINER` RPCs over two internal helpers
(`_exit_membership`, `_cascade_if_orphaned`), proven by pgTAP against the
local Docker stack. On the client, two small correctness fixes to how local
`members.userId` is maintained, plus a membership probe folded into the sync
engine's pull path that detects revocation and surfaces it honestly.

**Tech Stack:** Postgres 15 / Supabase (local Docker stack, pgTAP), Flutter
3.44, Riverpod, drift/SQLite, gen_l10n.

**Spec:** `docs/specs/household-lifecycle.md` (BINDING). Section references
below (§2.2, §3.1 G-A, etc.) point into it.

## Global Constraints

- Every user-visible string goes through gen_l10n: add to `lib/l10n/app_en.arb`
  (template) AND `lib/l10n/app_de.arb` (du-form). Never hardcode display text.
- Every interactive widget gets a semantic id via the `semantic()` helper.
- Strict lints: `very_good_analysis` with `--fatal-infos`. Public members need
  doc comments.
- Widget tests are integration-style: real in-memory `AppDatabase`, fixed
  clock, overriding only db/clock/gateway providers. Never mock repositories.
- Never `await` a drift stream outside a widget pump — it deadlocks.
- Run Flutter/Dart commands as `env -u GIT_DIR -u GIT_INDEX_FILE flutter ...`
  when anywhere near git hooks or worktrees.
- **Running tests requires the Supabase dart-defines**, exactly as
  `lefthook.yml` does — they keep `syncEngineProvider` offline, and six
  tests fail without them:
  `env -u GIT_DIR -u GIT_INDEX_FILE flutter test --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY= <path>`
- Do NOT run more than 2 concurrent `flutter test`/`build` processes.
- Never add `Co-Authored-By` trailers to commits.
- `members.role` is vestigial (D1). Do not add role-based enforcement.
- SQL style: follow `supabase/migrations/20260731120000_initial_schema.sql` —
  `security definer`, `set search_path = public`, explicit
  `revoke execute ... from public, anon` then `grant execute ... to authenticated`.

## Three deliberate deviations from the spec

All three are refinements found while planning. They are called out here
rather than silently applied:

1. **§2.8 says "extends `supabase/tests/001_rls_isolation_test.sql`".** This
   plan adds `supabase/tests/002_membership_exit_test.sql` instead. `001` opens
   with `select plan(32)` and is 259 lines; growing it means re-counting that
   plan on every task and re-running unrelated assertions. A second file is the
   same coverage with independent counts.
2. **§2.2 writes `leave_household()` with no parameter.** This plan uses
   `leave_household(p_household_id uuid)`. `members.user_id` is UNIQUE *per
   household*, so an account can legitimately belong to several and a
   no-argument version would have to guess which one to leave. The client
   always knows its `syncHouseholdId`. `delete_account()` stays parameterless
   and loops over all memberships, exactly as specced.
3. **§3.5 says to fold `HouseholdGateway.findMyMembership()` into the pull
   path.** `SupabaseSyncEngine` does not hold a `HouseholdGateway` — it talks
   to the server exclusively through `SyncTransport`, "the network seam (spec
   §8.4)". Injecting a second gateway into the engine to make the wording
   literal would give it two network seams. This plan instead adds one method
   to `SyncTransport`, which is faithful to the intent (probe membership on
   pull) and keeps the engine's single-seam design.

---

## Slice 1 — Server

### Task 1: Prove the `auth.users` delete (HARD GATE, D-L4)

Everything about `delete_account` depends on whether a `postgres`-owned
`SECURITY DEFINER` function may delete from `auth.users`. Settle it before
writing anything that assumes it.

**Files:**
- Create: `supabase/migrations/20260808120000_membership_exit.sql`
- Create: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: `public.delete_account() returns void`. Task 6 extends it; Tasks 2–5 do not depend on it.

- [ ] **Step 1: Start the local stack**

```bash
supabase start
```

Expected: a table of local URLs (API on `http://127.0.0.1:54321`). If it is
already running this is a no-op.

**Applies to every task in slice 1:** `supabase test db` does NOT apply new
or changed migrations — it runs the test files against the database as it
currently stands. After editing anything under `supabase/migrations/`, run

```bash
supabase db reset
```

first, then `supabase test db`. Skipping the reset produces confusing
"function does not exist" failures long after you wrote the function.

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/002_membership_exit_test.sql`:

```sql
-- pgTAP: membership exit (spec docs/specs/household-lifecycle.md §2.8).
-- Run: `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(2);

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000d1', 'dana@test.local');

create or replace function test_login(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Dana bootstraps a household, then deletes her account.
select test_login('00000000-0000-0000-0000-0000000000d1');
select lives_ok(
  $$select create_household(
      '10000000-0000-0000-0000-0000000000d1'::uuid, 'Haus D',
      '20000000-0000-0000-0000-0000000000d1'::uuid, 'Dana', 4278190080)$$,
  'dana can bootstrap her household');

select lives_ok(
  $$select delete_account()$$,
  'delete_account() runs and removes the auth user (D-L4 gate)');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
supabase test db
```

Expected: FAIL — `function delete_account() does not exist`.

- [ ] **Step 4: Write the minimal migration**

Create `supabase/migrations/20260808120000_membership_exit.sql`:

```sql
-- Membership exit (spec docs/specs/household-lifecycle.md §2): leave,
-- remove-a-member, delete-account, and the orphan-household cascade.
-- All three public RPCs are SECURITY DEFINER over internal helpers that
-- are never granted to authenticated.

-- The auth.users foreign keys (§2.7). Three constraints reference
-- auth.users with NO ACTION. The unclaim handles members.user_id; these
-- two are NOT NULL and would block `delete from auth.users` for every
-- account that ever created a household or an invite -- which is every
-- account delete_account exists for. Both columns are write-only (no RLS
-- policy, RPC or client reads them), so relaxing them is safe:
--   * a household outlives its creator by design (§0: the household owns
--     its data), so a null creator is the honest representation;
--   * invites are ephemeral 7-day codes and should die with their creator.
alter table public.households
  alter column created_by drop not null;
alter table public.households
  drop constraint households_created_by_fkey;
alter table public.households
  add constraint households_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

alter table public.household_invites
  drop constraint household_invites_created_by_fkey;
alter table public.household_invites
  add constraint household_invites_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete cascade;

-- delete_account (§2.2, D-L4), first form: unclaim every membership, then
-- delete the auth user. The auth.users delete works because this function
-- is owned by `postgres`, which has rights on the auth schema -- no edge
-- function and no service-role key. Task 1's pgTAP case proves that.
--
-- The unclaim is NOT optional padding: members.user_id is the third
-- NO ACTION foreign key to auth.users, and unlike the two created_by
-- columns it must NOT be relaxed -- is_household_member() reads it, so it
-- is load-bearing for every RLS policy. Nulling it here is what the
-- finished form does anyway (§2.2 loops over memberships), so this stub is
-- a true subset of the final behaviour rather than a throwaway.
--
-- Still deliberately INCOMPLETE: no orphan cascade, and no reuse of the
-- _exit_membership / _cascade_if_orphaned helpers, which do not exist yet.
-- Task 6 replaces this body entirely. Do not add the cascade here.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  update members set user_id = null where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
supabase test db
```

Expected: PASS, 2/2 in `002_membership_exit_test.sql`.

**If it FAILS with a permission error on `auth.users`:** stop here. D-L4 is
refused. Do not continue to Task 2. Report the exact error and re-plan
slice 6 against the `sync-backend.md` §2 edge function. Tasks 2–5 remain
valid either way, but the handoff story changes and the user must decide.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260808120000_membership_exit.sql supabase/tests/002_membership_exit_test.sql
git commit -m "Prove the auth.users delete works from a SECURITY DEFINER RPC (D-L4 gate)"
```

---

### Task 2: `_exit_membership` + `leave_household`

**Files:**
- Modify: `supabase/migrations/20260808120000_membership_exit.sql`
- Modify: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Consumes: `public.is_household_member(uuid)` from the initial schema.
- Produces: `public._exit_membership(p_member_id uuid) returns uuid` (returns the household id; NOT granted to `authenticated`), `public.leave_household(p_household_id uuid) returns void`.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/002_membership_exit_test.sql`, change `select plan(2);` to
`select plan(7);` and insert before `select * from finish();`:

```sql
-- test_login() sets role=authenticated through set_config(..., true),
-- which persists for the REST OF THIS TRANSACTION -- it never reverts on
-- its own. Any statement needing superuser must `reset role;` first:
-- writing auth.users, or inserting a CLAIMED members row (members_insert
-- deliberately forbids those from the client). This recurs all through
-- the file; when a fixture fails with "permission denied for table
-- users", a missing reset role is why.
reset role;

-- Erik and Fran share household E. `outsider` belongs to no household and
-- is the non-member probe for every authorization case below -- Dana is
-- NOT reusable for that: Task 1 deleted her auth row.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000e1', 'erik@test.local'),
       ('00000000-0000-0000-0000-0000000000f1', 'fran@test.local'),
       ('00000000-0000-0000-0000-00000000000c', 'outsider@test.local');

select test_login('00000000-0000-0000-0000-0000000000e1');
select create_household(
  '10000000-0000-0000-0000-0000000000e1'::uuid, 'Haus E',
  '20000000-0000-0000-0000-0000000000e1'::uuid, 'Erik', 4278190080);

-- Fran is a second claimed member (inserted as superuser: the members
-- INSERT policy deliberately forbids claimed profiles from the client).
reset role;
insert into members (id, household_id, name, color, role, user_id)
values ('20000000-0000-0000-0000-0000000000f1',
        '10000000-0000-0000-0000-0000000000e1', 'Fran', 4278190081,
        'member', '00000000-0000-0000-0000-0000000000f1');

-- The outsider is not a member of E and cannot leave it.
select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$select leave_household('10000000-0000-0000-0000-0000000000e1'::uuid)$$,
  'not a member of this household',
  'a non-member cannot leave a household they were never in');

select test_login('00000000-0000-0000-0000-0000000000e1');
select lives_ok(
  $$select leave_household('10000000-0000-0000-0000-0000000000e1'::uuid)$$,
  'erik can leave his household');

reset role;
select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-0000000000e1'),
  null,
  'leaving unclaims the member row');

select is(
  (select deleted_at from members
   where id = '20000000-0000-0000-0000-0000000000e1'),
  null,
  'leaving does NOT soft-delete the profile (§2.2: it stays claimable)');

select is(
  (select deleted_at from households
   where id = '10000000-0000-0000-0000-0000000000e1'),
  null,
  'no cascade while Fran is still claimed');
```

- [ ] **Step 2: Run to verify it fails**

```bash
supabase test db
```

Expected: FAIL — `function leave_household(uuid) does not exist`.

- [ ] **Step 3: Add the helper and the RPC**

Append to `supabase/migrations/20260808120000_membership_exit.sql`:

```sql
-- Internal: sever one member row's claim. Returns the household id so
-- callers can run the cascade check. NEVER granted to authenticated --
-- unclaiming must go through the three authorized RPCs.
create or replace function public._exit_membership(p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
begin
  update members set user_id = null
    where id = p_member_id
    returning household_id into v_household_id;
  if v_household_id is null then
    raise exception 'no such member';
  end if;
  return v_household_id;
end;
$$;

revoke execute on function public._exit_membership(uuid)
  from public, anon, authenticated;

-- leave_household (§2.2): unclaims ONLY. The profile stays active so the
-- family keeps seeing the person and their history, and they can reclaim
-- it later through the invite path. Takes the household id explicitly --
-- user_id is UNIQUE per household, so an account may belong to several.
create or replace function public.leave_household(p_household_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_id uuid;
begin
  if not is_household_member(p_household_id) then
    raise exception 'not a member of this household';
  end if;
  select id into v_member_id from members
    where household_id = p_household_id
      and user_id = auth.uid()
      and deleted_at is null;
  perform _exit_membership(v_member_id);
end;
$$;

revoke execute on function public.leave_household(uuid) from public, anon;
grant execute on function public.leave_household(uuid) to authenticated;
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase test db
```

Expected: PASS, 7/7.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808120000_membership_exit.sql supabase/tests/002_membership_exit_test.sql
git commit -m "Add _exit_membership and leave_household RPC"
```

---

### Task 3: The orphan cascade (F13)

**Files:**
- Modify: `supabase/migrations/20260808120000_membership_exit.sql`
- Modify: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Consumes: `_exit_membership` from Task 2.
- Produces: `public._cascade_if_orphaned(p_household_id uuid) returns boolean` (true when it stamped `households.deleted_at`; NOT granted to `authenticated`). `leave_household` and `delete_account` call it.

- [ ] **Step 1: Write the failing test**

Bump `select plan(7);` to `select plan(9);` and append before `finish()`:

```sql
-- Fran now leaves too -- she is the last claimed member, so the household
-- cascades (§2.4, D-L5).
select test_login('00000000-0000-0000-0000-0000000000f1');
select lives_ok(
  $$select leave_household('10000000-0000-0000-0000-0000000000e1'::uuid)$$,
  'fran, the last claimed member, can leave');

reset role;
select isnt(
  (select deleted_at from households
   where id = '10000000-0000-0000-0000-0000000000e1'),
  null,
  'the household cascades when its last claimed member leaves');
```

- [ ] **Step 2: Run to verify it fails**

```bash
supabase test db
```

Expected: FAIL on the last assertion — `deleted_at` is still null.

- [ ] **Step 3: Add the cascade helper and call it**

Append to the migration:

```sql
-- Internal: soft-delete a household that has no claimed members left
-- (§2.4). Child rows are deliberately left alone -- RLS already hides
-- every row once nobody is a member, so cascading them buys nothing and
-- costs a large write. `updated_at` is trigger-maintained; do not set it.
create or replace function public._cascade_if_orphaned(p_household_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed int;
begin
  select count(*) into v_claimed from members
    where household_id = p_household_id
      and user_id is not null
      and deleted_at is null;
  if v_claimed > 0 then
    return false;
  end if;
  update households set deleted_at = now()
    where id = p_household_id and deleted_at is null;
  return true;
end;
$$;

revoke execute on function public._cascade_if_orphaned(uuid)
  from public, anon, authenticated;
```

Then replace `leave_household`'s body line `perform _exit_membership(v_member_id);` with:

```sql
  perform _cascade_if_orphaned(_exit_membership(v_member_id));
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase test db
```

Expected: PASS, 9/9.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808120000_membership_exit.sql supabase/tests/002_membership_exit_test.sql
git commit -m "Cascade-soft-delete a household when its last claimed member leaves"
```

---

### Task 4: `remove_member` (F10)

**Files:**
- Modify: `supabase/migrations/20260808120000_membership_exit.sql`
- Modify: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Consumes: `_exit_membership` (Task 2).
- Produces: `public.remove_member(p_member_id uuid) returns void`.

Note §2.3: `remove_member` can never orphan a household — the caller is
always a claimed member who stays, and self-removal is rejected — so it
does NOT call `_cascade_if_orphaned`. The test below asserts that negative.

- [ ] **Step 1: Write the failing tests**

Bump `select plan(9);` to `select plan(15);` and append before `finish()`:

```sql
-- Household G: Gil and Hana both claimed, plus an unclaimed profile.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000g1', 'gil@test.local'),
       ('00000000-0000-0000-0000-0000000000h1', 'hana@test.local');

select test_login('00000000-0000-0000-0000-0000000000g1');
select create_household(
  '10000000-0000-0000-0000-0000000000g1'::uuid, 'Haus G',
  '20000000-0000-0000-0000-0000000000g1'::uuid, 'Gil', 4278190080);

reset role;
insert into members (id, household_id, name, color, role, user_id)
values ('20000000-0000-0000-0000-0000000000h1',
        '10000000-0000-0000-0000-0000000000g1', 'Hana', 4278190081,
        'member', '00000000-0000-0000-0000-0000000000h1'),
       ('20000000-0000-0000-0000-0000000000h2',
        '10000000-0000-0000-0000-0000000000g1', 'Kid', 4278190082,
        'member', null);

-- A non-member cannot remove anyone in G.
select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$select remove_member('20000000-0000-0000-0000-0000000000h1'::uuid)$$,
  'not a member of this household',
  'a non-member cannot remove a member of another household');

-- Gil cannot remove himself.
select test_login('00000000-0000-0000-0000-0000000000g1');
select throws_ok(
  $$select remove_member('20000000-0000-0000-0000-0000000000g1'::uuid)$$,
  'use leave_household to remove yourself',
  'remove_member rejects self-removal (§2.2)');

-- Gil removes Hana, a claimed member, with no role privilege (D-L2/D1).
select lives_ok(
  $$select remove_member('20000000-0000-0000-0000-0000000000h1'::uuid)$$,
  'any member can remove any other member');

reset role;
select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-0000000000h1'),
  null,
  'removal unclaims the profile');

select isnt(
  (select deleted_at from members
   where id = '20000000-0000-0000-0000-0000000000h1'),
  null,
  'removal soft-deletes the profile (unlike leaving)');

select is(
  (select deleted_at from households
   where id = '10000000-0000-0000-0000-0000000000g1'),
  null,
  'removing a member never soft-deletes the household');
-- NOTE on what this does and does not prove: it cannot distinguish
-- "_cascade_if_orphaned was never called" from "it was called and
-- correctly no-opped", because Gil is still claimed either way. It is a
-- real invariant (a removal must never take the household with it), just
-- not a proof of §2.3's mechanism. §2.3 holds structurally: self-removal
-- is rejected, so the caller is always a surviving claimed member.
```

- [ ] **Step 2: Run to verify it fails**

```bash
supabase test db
```

Expected: FAIL — `function remove_member(uuid) does not exist`.

- [ ] **Step 3: Add the RPC**

Append to the migration:

```sql
-- remove_member (§2.2): unclaims AND soft-deletes another member's
-- profile. Any member may remove any other (D-L2 -- the household is flat
-- by D1; role is not consulted). Self-removal is rejected: that is
-- leave_household, which keeps the profile claimable. Idempotent on an
-- already-removed row and tolerant of an unclaimed target, so a retry
-- after a partial failure is safe.
create or replace function public.remove_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_caller_member_id uuid;
begin
  select household_id into v_household_id from members
    where id = p_member_id;
  -- ONE message for "no such member" and "not your household" alike.
  -- This function is SECURITY DEFINER, so the lookup above bypasses RLS:
  -- two distinct messages would tell a non-member whether an arbitrary
  -- member UUID exists anywhere in the system -- an existence oracle
  -- across household boundaries, and a hole in the is_household_member
  -- perimeter this project treats as its security boundary. Say nothing.
  if v_household_id is null or not is_household_member(v_household_id) then
    raise exception 'not a member of this household';
  end if;
  select id into v_caller_member_id from members
    where household_id = v_household_id
      and user_id = auth.uid()
      and deleted_at is null;
  if v_caller_member_id = p_member_id then
    raise exception 'use leave_household to remove yourself';
  end if;
  update members
    set user_id = null,
        deleted_at = coalesce(deleted_at, now())
    where id = p_member_id;
end;
$$;

revoke execute on function public.remove_member(uuid) from public, anon;
grant execute on function public.remove_member(uuid) to authenticated;
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase test db
```

Expected: PASS, 15/15.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808120000_membership_exit.sql supabase/tests/002_membership_exit_test.sql
git commit -m "Add remove_member RPC (any member may remove any other, never self)"
```

---

### Task 5: Reject invites into a dead household (§2.5)

`list_claimable_members`, `claim_member` and `join_as_new_member` all obtain
their invite through `public._valid_invite(p_code)`. That is the single choke
point — one guard, not three.

**Files:**
- Modify: `supabase/migrations/20260808120000_membership_exit.sql`
- Modify: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Consumes: `public._valid_invite(p_code text)` from the initial schema.
- Produces: no new symbol — replaces `_valid_invite`'s body.

- [ ] **Step 1: Write the failing test**

Bump `select plan(15);` to `select plan(17);` and append before `finish()`:

```sql
-- An invite created while Haus E was alive must not work after it
-- cascaded (§2.5) -- otherwise a live code resurrects a dead household.
reset role;
insert into household_invites (household_id, code, created_by)
values ('10000000-0000-0000-0000-0000000000e1', 'DEADCODE',
        '00000000-0000-0000-0000-0000000000e1');

select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$select list_claimable_members('DEADCODE')$$,
  'invalid or expired invite',
  'a code for a cascaded household is rejected');

select throws_ok(
  $$select join_as_new_member('DEADCODE',
      '20000000-0000-0000-0000-0000000000ce'::uuid, 'Zoe', 4278190080)$$,
  'invalid or expired invite',
  'joining a cascaded household is rejected');
```

- [ ] **Step 2: Run to verify it fails**

```bash
supabase test db
```

Expected: FAIL — both calls succeed today.

- [ ] **Step 3: Replace `_valid_invite`**

Append to the migration:

```sql
-- _valid_invite gains a household-liveness check (§2.5). This one helper
-- backs list_claimable_members, claim_member and join_as_new_member, so
-- guarding it here covers the whole redemption family. Same error message
-- as the other rejections: an outsider learns nothing about why.
create or replace function public._valid_invite(p_code text)
returns public.household_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  select * into v_invite from household_invites
    where code = p_code and revoked_at is null and expires_at > now();
  if v_invite.id is null then
    raise exception 'invalid or expired invite';
  end if;
  if exists (
    select 1 from households h
    where h.id = v_invite.household_id and h.deleted_at is not null
  ) then
    raise exception 'invalid or expired invite';
  end if;
  return v_invite;
end;
$$;
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase test db
```

Expected: PASS, 17/17.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808120000_membership_exit.sql supabase/tests/002_membership_exit_test.sql
git commit -m "Reject invite redemption into a cascaded household"
```

---

### Task 6: Finish `delete_account` (F11)

Task 1 proved the `auth.users` delete. Now give it the unclaim + cascade
behaviour §2.2 requires.

**Files:**
- Modify: `supabase/migrations/20260808120000_membership_exit.sql`
- Modify: `supabase/tests/002_membership_exit_test.sql`

**Interfaces:**
- Consumes: `_exit_membership` (Task 2), `_cascade_if_orphaned` (Task 3).
- Produces: `public.delete_account() returns void`, final form.

This task also carries two Minor findings from earlier reviews, both in
files it already edits. They are Steps 6 and 7.

- [ ] **Step 1: Write the failing tests**

Bump `select plan(17);` to `select plan(22);` and append before `finish()`:

```sql
-- Task 5's block ends with role=authenticated still set (its last
-- statements are throws_ok calls after a test_login), so this superuser
-- insert needs the reset first -- see Task 2's note on test_login's
-- transaction-scoped set_config.
reset role;

-- Household J: Jo alone (claimed) plus an unclaimed profile. Deleting Jo's
-- account must unclaim her, cascade J, and remove the auth user.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000da', 'jo@test.local');

select test_login('00000000-0000-0000-0000-0000000000da');
select create_household(
  '10000000-0000-0000-0000-0000000000da'::uuid, 'Haus J',
  '20000000-0000-0000-0000-0000000000da'::uuid, 'Jo', 4278190080);

select lives_ok(
  $$select delete_account()$$,
  'jo can delete her account');

reset role;
select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-0000000000da'),
  null,
  'delete_account unclaims every membership');

select isnt(
  (select deleted_at from households
   where id = '10000000-0000-0000-0000-0000000000da'),
  null,
  'delete_account cascades a household left with no claimed members');

select is(
  (select count(*)::int from auth.users
   where id = '00000000-0000-0000-0000-0000000000da'),
  0,
  'delete_account removes the auth user (D-L4)');
```

- [ ] **Step 2: Run to verify it fails**

```bash
supabase test db
```

Expected: FAIL on the unclaim and cascade assertions — Task 1's stub only
deletes the auth user.

- [ ] **Step 3: Replace `delete_account`**

Append to the migration:

```sql
-- delete_account (§2.2, D-L4), final form: leave EVERY household where
-- the caller is claimed (user_id is UNIQUE per household, so there may be
-- several), cascade each one that is left with no claimed members, then
-- delete the auth user. Local data on the caller's own device is NOT
-- touched -- that is the client's opt-in checkbox (D-L3).
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  for v_member_id in
    select id from members where user_id = auth.uid() and deleted_at is null
  loop
    perform _cascade_if_orphaned(_exit_membership(v_member_id));
  end loop;
  delete from auth.users where id = auth.uid();
end;
$$;
```

- [ ] **Step 4: Run to verify it passes**

```bash
supabase test db
```

Expected: PASS, 22/22.

- [ ] **Step 6: Make `_cascade_if_orphaned`'s return value honest**

Task 3's review finding. The function's doc comment promises "true when it
stamped `households.deleted_at`", but it returns true whenever zero claimed
members remain — including when the household was already soft-deleted and
the UPDATE touched no rows. Harmless today (every caller uses `perform`),
a trap the moment anything branches on it.

In `supabase/migrations/20260808120000_membership_exit.sql`, add
`v_stamped int;` to `_cascade_if_orphaned`'s `declare` block and replace:

```sql
  update households set deleted_at = now()
    where id = p_household_id and deleted_at is null;
  return true;
```

with:

```sql
  update households set deleted_at = now()
    where id = p_household_id and deleted_at is null;
  -- Report what actually happened, not what was merely eligible: an
  -- already-cascaded household is eligible but stamps nothing. The doc
  -- comment above promises "stamped", so return that.
  get diagnostics v_stamped = row_count;
  return v_stamped > 0;
```

No test count change — no current caller reads the return value.

- [ ] **Step 7: Assert the invite guard covers `claim_member` too**

Task 5's review finding: `_valid_invite`'s household-liveness guard was
asserted through `list_claimable_members` and `join_as_new_member`, but not
through `claim_member`, the third caller sharing that choke point. The
guard does cover it (verified live during review); the suite just didn't
say so. Append to `supabase/tests/002_membership_exit_test.sql`, beside the
other two `DEADCODE` assertions:

```sql
select throws_ok(
  $$select claim_member('DEADCODE',
      '20000000-0000-0000-0000-0000000000f1'::uuid)$$,
  'invalid or expired invite',
  'claiming a profile in a cascaded household is rejected');
```

This is the 22nd assertion counted in Step 1's `plan(22)`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808120000_membership_exit.sql supabase/tests/002_membership_exit_test.sql
git commit -m "Finish delete_account: unclaim every membership, cascade, delete the auth user"
```

---

## Slice 2 — Claim-state gaps (§3.1)

### Task 7: G-A — unlinking clears local `members.userId`

Because pull populates `userId`, clearing the sync link strands real values
in a now-local-only household, permanently blocking deletion of profiles
nobody can ever unclaim.

**Files:**
- Modify: `lib/data/repositories/settings_repository.dart:244-256`
- Test: `test/data/repositories/settings_repository_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SettingsRepository.clearSyncLink()` — same signature, now also nulls every local `members.userId` in the same transaction.

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` of
`test/data/repositories/settings_repository_test.dart`:

```dart
  test(
    'clearSyncLink also nulls every local members.userId, so claim state '
    'from a previous link cannot block deletion in a local-only household '
    '(spec docs/specs/household-lifecycle.md §3.1 G-A)',
    () async {
      final households = HouseholdRepository(db);
      final settings = SettingsRepository(db);
      final household = await households.createLocalHousehold('Me');
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();

      // Simulate a pulled, claimed row.
      await (db.update(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).write(
        const MembersCompanion(userId: Value('auth-user-1')),
      );
      await settings.setSyncLinked(
        householdId: household.id,
        linkedAt: DateTime.utc(2026),
      );

      await settings.clearSyncLink();

      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(after.userId, isNull);
      expect(
        after.syncDirty,
        isFalse,
        reason:
            'user_id is server-owned and not UPDATE-granted; marking the '
            'row dirty would push a column the client may not write',
      );
    },
  );
```

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/data/repositories/settings_repository_test.dart
```

Expected: FAIL — `Expected: null, Actual: 'auth-user-1'`.

- [ ] **Step 3: Implement**

Replace the body of `clearSyncLink` in
`lib/data/repositories/settings_repository.dart`:

```dart
  /// Clears this device's link to an online household.
  ///
  /// Also nulls every local `members.userId` (spec
  /// `docs/specs/household-lifecycle.md` §3.1 G-A): claim state is
  /// meaningless in a local-only household, and a stale value left behind
  /// by an earlier pull would keep those profiles undeletable forever.
  /// Deliberately does NOT mark the members rows `syncDirty` -- `user_id`
  /// is server-owned and is not in the client's UPDATE grant.
  Future<void> clearSyncLink() async {
    await ensureSettings();
    await db.transaction(() async {
      await (db.update(
        db.settings,
      )..where((tbl) => tbl.id.equals(deviceId))).write(
        SettingsCompanion(
          syncHouseholdId: const Value(null),
          syncLinkedAt: const Value(null),
          syncLastPulledAt: const Value(null),
          updatedAt: Value(_isoNow()),
        ),
      );
      await db
          .update(db.members)
          .write(const MembersCompanion(userId: Value(null)));
    });
  }
```

- [ ] **Step 4: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/data/repositories/settings_repository_test.dart
```

Expected: PASS, all tests in the file.

- [ ] **Step 5: Run the disconnect tests to confirm nothing regressed**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_link_service_test.dart
```

Expected: PASS. Disconnect's user-facing behaviour is unchanged — it still
deletes no rows and still permits reconnect, because server `user_id` is
untouched.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/settings_repository.dart test/data/repositories/settings_repository_test.dart
git commit -m "Clear local members.userId when unlinking (spec §3.1 G-A)"
```

---

### Task 8: G-B — adopt sets the acting member's `userId`

`adopt` mirrors the server's role rule locally but not its claim rule, and
that write marks the row `syncDirty` — which makes `_applyPulled` skip it.
The adopter's own profile therefore reads as unclaimed until a full
push/pull round trip.

**Files:**
- Modify: `lib/data/repositories/household_repository.dart`
- Modify: `lib/application/household_link_service.dart:104-110`
- Modify: `lib/features/settings/account_section.dart` (the adopt call site)
- Test: `test/application/household_link_service_test.dart`

**Interfaces:**
- Consumes: `HouseholdRepository.setMemberRole` (existing).
- Produces: `HouseholdRepository.setMemberUserId(String memberId, String userId)` → `Future<void>`; `HouseholdLinkService.adopt({required String householdId, required String actingMemberId, required String authUserId})` — **the third parameter is new and callers must pass it**.

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` of
`test/application/household_link_service_test.dart`:

```dart
  test(
    'adopt sets the acting member userId locally, mirroring the claim the '
    'server just made (spec docs/specs/household-lifecycle.md §3.1 G-B)',
    () async {
      final households = HouseholdRepository(db);
      final household = await households.createLocalHousehold('Me');
      final me = await (db.select(
        db.members,
      )..where((tbl) => tbl.householdId.equals(household.id))).getSingle();

      await service.adopt(
        householdId: household.id,
        actingMemberId: me.id,
        authUserId: 'auth-user-1',
      );

      final after = await (db.select(
        db.members,
      )..where((tbl) => tbl.id.equals(me.id))).getSingle();
      expect(after.userId, 'auth-user-1');
    },
  );
```

- [ ] **Step 2: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_link_service_test.dart
```

Expected: FAIL to compile — `adopt` has no `authUserId` parameter.

- [ ] **Step 3: Add the repository method**

Append to `lib/data/repositories/household_repository.dart`, next to
`setMemberRole`:

```dart
  /// Records locally that [memberId] is claimed by auth user [userId].
  ///
  /// Mirrors the claim the server made in `create_household` /
  /// `claim_member` (spec `docs/specs/household-lifecycle.md` §3.1 G-B).
  /// Deliberately does NOT mark the row `syncDirty`: `user_id` is
  /// server-owned and is not in the client's column-scoped UPDATE grant,
  /// so pushing it would be rejected.
  Future<void> setMemberUserId(String memberId, String userId) async {
    await (db.update(
      db.members,
    )..where((tbl) => tbl.id.equals(memberId))).write(
      MembersCompanion(userId: Value(userId)),
    );
  }
```

- [ ] **Step 4: Thread it through `adopt`**

In `lib/application/household_link_service.dart`, change the `adopt`
signature and step 3:

```dart
  Future<void> adopt({
    required String householdId,
    required String actingMemberId,
    required String authUserId,
  }) async {
```

and replace step 3's single line with:

```dart
    // Step 3: mirror the server's role AND claim rules locally. Without
    // the claim, the row is dirty-and-unclaimed and `_applyPulled` skips
    // it, so this device would read its own profile as unclaimed until a
    // full push/pull round trip (spec §3.1 G-B).
    await households.setMemberRole(actingMemberId, MemberRole.admin);
    await households.setMemberUserId(actingMemberId, authUserId);
```

- [ ] **Step 5: Update the call site**

In `lib/features/settings/account_section.dart`, find the `adopt(` call and
add the auth user id, which the widget already has from
`currentAuthUserProvider`:

```dart
    await ref.read(householdLinkServiceProvider).adopt(
      householdId: householdId,
      actingMemberId: actingMemberId,
      authUserId: authUser.id,
    );
```

If the surrounding widget does not already hold an `authUser`, read it with
`ref.read(currentAuthUserProvider).valueOrNull` and bail out early when it
is null — the adopt row is only shown to a signed-in user, so null is
unreachable in practice.

- [ ] **Step 6: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/household_link_service_test.dart test/features/settings/account_section_test.dart
```

Expected: PASS in both files.

- [ ] **Step 7: Run analyze**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos
```

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/data/repositories/household_repository.dart lib/application/household_link_service.dart lib/features/settings/account_section.dart test/application/household_link_service_test.dart
git commit -m "Set the acting member's local userId on adopt (spec §3.1 G-B)"
```

---

### Task 9: The shared exit-confirmation sheet (§3.3, D-L3)

One confirm shape for all three exits: consequences, an **unchecked** "also
delete this phone's copy" checkbox with one line of explanation, then the
action. Slice 3 uses it for the revocation notice; slices 4–6 reuse it.

**Files:**
- Create: `lib/features/settings/exit_confirm_sheet.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/settings/exit_confirm_sheet_test.dart`

**Interfaces:**
- Consumes: `semantic()` helper; `AppLocalizations`.
- Produces: `class ExitConfirmResult { final bool confirmed; final bool alsoDeleteLocalData; }` and `Future<ExitConfirmResult> showExitConfirmSheet(BuildContext context, {required String title, required String body, required String actionLabel, required String semanticPrefix})`. Dismissal resolves to `ExitConfirmResult(confirmed: false, alsoDeleteLocalData: false)`.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`:

```json
  "exitConfirmDeleteLocalLabel": "Also delete this phone's copy",
  "@exitConfirmDeleteLocalLabel": {
    "description": "Checkbox label in the shared exit-confirmation sheet (spec docs/specs/household-lifecycle.md §3.3). Unchecked by default in every exit."
  },
  "exitConfirmDeleteLocalExplanation": "Off: the household stays on this phone as your own local copy. On: this phone's members, chores and shopping list are deleted and the app starts fresh.",
  "@exitConfirmDeleteLocalExplanation": {
    "description": "One-line explanation under the exit-confirmation checkbox, stating what each state means."
  },
  "exitConfirmCancel": "Cancel",
  "@exitConfirmCancel": {
    "description": "Cancel button of the shared exit-confirmation sheet."
  },
```

In `lib/l10n/app_de.arb` (du-form):

```json
  "exitConfirmDeleteLocalLabel": "Kopie auf diesem Handy auch löschen",
  "exitConfirmDeleteLocalExplanation": "Aus: Der Haushalt bleibt als deine eigene lokale Kopie auf diesem Handy. An: Mitglieder, Aufgaben und Einkaufsliste auf diesem Handy werden gelöscht und die App startet neu.",
  "exitConfirmCancel": "Abbrechen",
```

- [ ] **Step 2: Regenerate localizations**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
```

Expected: no output on success; `lib/l10n/app_localizations*.dart` updated.

- [ ] **Step 3: Write the failing test**

Create `test/features/settings/exit_confirm_sheet_test.dart`:

```dart
import 'package:chore_app/features/settings/exit_confirm_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the shared exit-confirmation sheet (spec
/// `docs/specs/household-lifecycle.md` §3.3, D-L3): every exit keeps this
/// phone's data unless the user opts in.
void main() {
  Future<ExitConfirmResult?> showAndTap(
    WidgetTester tester, {
    required bool checkTheBox,
    required String tapLabel,
  }) async {
    ExitConfirmResult? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showExitConfirmSheet(
                  context,
                  title: 'Leave the household?',
                  body: 'Your profile stays with the household.',
                  actionLabel: 'Leave',
                  semanticPrefix: 'settings.account.leave',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (checkTheBox) {
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('defaults to keeping this phone\'s copy', (tester) async {
    final result = await showAndTap(
      tester,
      checkTheBox: false,
      tapLabel: 'Leave',
    );
    expect(result!.confirmed, isTrue);
    expect(result.alsoDeleteLocalData, isFalse);
  });

  testWidgets('carries the opt-in when the box is checked', (tester) async {
    final result = await showAndTap(
      tester,
      checkTheBox: true,
      tapLabel: 'Leave',
    );
    expect(result!.confirmed, isTrue);
    expect(result.alsoDeleteLocalData, isTrue);
  });

  testWidgets('cancel confirms nothing and deletes nothing', (tester) async {
    final result = await showAndTap(
      tester,
      checkTheBox: true,
      tapLabel: 'Cancel',
    );
    expect(result!.confirmed, isFalse);
    expect(result.alsoDeleteLocalData, isFalse);
  });
}
```

- [ ] **Step 4: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/exit_confirm_sheet_test.dart
```

Expected: FAIL to compile — `exit_confirm_sheet.dart` does not exist.

- [ ] **Step 5: Implement the sheet**

Create `lib/features/settings/exit_confirm_sheet.dart`:

```dart
/// The shared confirmation sheet for every household exit (spec
/// `docs/specs/household-lifecycle.md` §3.3, decision D-L3): leaving,
/// being removed, and deleting an account all keep this phone's data by
/// default and offer one explicit opt-in to wipe it.
library;

import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// What the user chose in [showExitConfirmSheet].
class ExitConfirmResult {
  /// Creates a result.
  const ExitConfirmResult({
    required this.confirmed,
    required this.alsoDeleteLocalData,
  });

  /// Whether the user confirmed the exit at all.
  final bool confirmed;

  /// Whether the user additionally opted into wiping this device's data.
  /// Always `false` when [confirmed] is `false`.
  final bool alsoDeleteLocalData;
}

/// Shows the exit confirmation and resolves to the user's choice.
///
/// Dismissing resolves to a declined, non-deleting result -- never null,
/// so callers need no null handling.
Future<ExitConfirmResult> showExitConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  required String semanticPrefix,
}) async {
  final result = await showModalBottomSheet<ExitConfirmResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ExitConfirmSheet(
      title: title,
      body: body,
      actionLabel: actionLabel,
      semanticPrefix: semanticPrefix,
    ),
  );
  return result ??
      const ExitConfirmResult(confirmed: false, alsoDeleteLocalData: false);
}

class _ExitConfirmSheet extends StatefulWidget {
  const _ExitConfirmSheet({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.semanticPrefix,
  });

  final String title;
  final String body;
  final String actionLabel;
  final String semanticPrefix;

  @override
  State<_ExitConfirmSheet> createState() => _ExitConfirmSheetState();
}

class _ExitConfirmSheetState extends State<_ExitConfirmSheet> {
  /// Unchecked in every exit (D-L3): the safe default is the same one
  /// everywhere, including delete-account.
  bool _alsoDeleteLocalData = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(widget.body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          semantic(
            '${widget.semanticPrefix}.deleteLocal',
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _alsoDeleteLocalData,
              title: Text(l10n.exitConfirmDeleteLocalLabel),
              subtitle: Text(l10n.exitConfirmDeleteLocalExplanation),
              onChanged: (value) =>
                  setState(() => _alsoDeleteLocalData = value ?? false),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              semantic(
                '${widget.semanticPrefix}.cancel',
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const ExitConfirmResult(
                      confirmed: false,
                      alsoDeleteLocalData: false,
                    ),
                  ),
                  child: Text(l10n.exitConfirmCancel),
                ),
              ),
              const SizedBox(width: 8),
              semantic(
                '${widget.semanticPrefix}.confirm',
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    ExitConfirmResult(
                      confirmed: true,
                      alsoDeleteLocalData: _alsoDeleteLocalData,
                    ),
                  ),
                  child: Text(widget.actionLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Note the helper's signature is `Widget semantic(String id, {required Widget
child})` (`lib/app/semantics.dart:13`) — the widget goes in the NAMED `child:`
parameter, not positionally.

- [ ] **Step 6: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/exit_confirm_sheet_test.dart
```

Expected: PASS, 3 tests.

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/exit_confirm_sheet.dart lib/l10n/ test/features/settings/exit_confirm_sheet_test.dart
git commit -m "Add the shared exit-confirmation sheet with the opt-in local wipe (spec §3.3)"
```

---

## Slice 3 — Revocation detection and notice (§3.5)

### Task 10: Detect revocation in the pull path

While linked, `findMyMembership()` returning null **is** the revocation
signal. This is the one place `sync-backend.md` §8.3's swallow-all-errors
posture is deliberately overridden.

**Files:**
- Modify: `lib/application/sync_engine.dart` (the `pullSince` entry point)
- Modify: `lib/data/repositories/settings_repository.dart` (add the flag)
- Test: `test/application/sync_engine_test.dart`

**Files (additional):**
- Modify: `lib/data/db/tables.dart`, `lib/data/db/app_database.dart`
- Modify: `test/application/fake_sync_transport.dart`

**Interfaces:**
- Consumes: `SettingsRepository.clearSyncLink()` (Task 7), `SettingsRepository.ensureSettings()` (existing — returns `DeviceSettings`; there is no `load()`).
- Produces: `SyncTransport.hasMembership(String householdId) → Future<bool>` (new method on the existing interface, implemented by the Supabase transport and `FakeSyncTransport`); `SettingsRepository.setMembershipRevoked()` and `clearMembershipRevoked()`; the `membershipRevoked` bool on `DeviceSettings`.

- [ ] **Step 1: Add the settings column**

The notice must survive an app restart, so it needs persistence rather than
in-memory state. In `lib/data/db/tables.dart`, add to the `Settings` table:

```dart
  /// Set when a pull discovered this device's membership was revoked
  /// server-side (spec `docs/specs/household-lifecycle.md` §3.5). Cleared
  /// when the user acknowledges the notice.
  BoolColumn get membershipRevoked =>
      boolean().withDefault(const Constant(false))();
```

In `lib/data/db/app_database.dart`, change `int get schemaVersion => 9;` to
`=> 10;` and add the matching `onUpgrade` step alongside the existing ones:

```dart
        if (from < 10) {
          await m.addColumn(schema.settings, schema.settings.membershipRevoked);
        }
```

Then regenerate drift code:

```bash
env -u GIT_DIR -u GIT_INDEX_FILE dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 2: Write the failing test**

First give the fake a switch. In `test/application/fake_sync_transport.dart`,
add to `FakeSyncTransport`:

```dart
  /// What [hasMembership] returns. `false` models a revoked membership --
  /// the server-side removal this device has not noticed yet.
  bool membershipPresent = true;

  @override
  Future<bool> hasMembership(String householdId) async => membershipPresent;
```

Then append inside the existing `main()` of
`test/application/sync_engine_test.dart`, in the group that exercises
`SupabaseSyncEngine`:

```dart
    test(
      'a pull whose membership probe comes back false clears the sync link '
      'and records the revocation for the notice (spec '
      'docs/specs/household-lifecycle.md §3.5)',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        transport.membershipPresent = false;

        await engine.pullSince();

        final row = await settings.ensureSettings();
        expect(row.syncHouseholdId, isNull);
        expect(row.membershipRevoked, isTrue);
      },
    );

    test(
      'a pull whose membership probe succeeds leaves the link alone',
      () async {
        await settings.setSyncLinked(
          householdId: household.id,
          linkedAt: DateTime.utc(2026),
        );
        transport.membershipPresent = true;

        await engine.pullSince();

        final row = await settings.ensureSettings();
        expect(row.syncHouseholdId, household.id);
        expect(row.membershipRevoked, isFalse);
      },
    );
```

The local names (`settings`, `transport`, `engine`, `household`) are whatever
that group's own `setUp` already binds — `sync_engine_test.dart` builds a
`SupabaseSyncEngine(db:, transport:, settings:, householdId:)` per group, so
reuse the surrounding group's fixtures rather than creating new ones.

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/sync_engine_test.dart
```

Expected: FAIL — `membershipRevoked` is false and the link is intact.

- [ ] **Step 4: Implement the probe**

First add the probe to the network seam. In `lib/application/sync_engine.dart`,
add to the `abstract class SyncTransport`:

```dart
  /// Whether the signed-in account still has a live claimed membership in
  /// [householdId] (spec `docs/specs/household-lifecycle.md` §3.5).
  ///
  /// This is the revocation signal: RLS answers a revoked device with
  /// EMPTY RESULT SETS rather than errors, so an ordinary pull is
  /// indistinguishable from "nothing changed" and the device would look
  /// healthy forever.
  Future<bool> hasMembership(String householdId);
```

Implement it on the Supabase transport alongside the other methods, mirroring
`SupabaseHouseholdGateway.findMyMembership`'s query but scoped to the
household:

```dart
  @override
  Future<bool> hasMembership(String householdId) async {
    final rows = await _client
        .from('members')
        .select('id')
        .eq('household_id', householdId)
        .limit(1);
    return rows.isNotEmpty;
  }
```

A revoked member's own row is hidden from them by `members_select` (which
goes through `is_household_member`), so an empty result is exactly the
revocation signal — no `user_id` filter is needed or wanted.

Then, at the top of `SupabaseSyncEngine.pullSince()`, before any table fetch:

```dart
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
      return;
    }
```

Add to `SettingsRepository`:

```dart
  /// Records that this device's household membership was revoked
  /// server-side, so the UI can explain it once (spec
  /// `docs/specs/household-lifecycle.md` §3.5).
  Future<void> setMembershipRevoked() async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        membershipRevoked: const Value(true),
        updatedAt: Value(_isoNow()),
      ),
    );
  }

  /// Clears the revocation flag once the user has acknowledged the notice.
  Future<void> clearMembershipRevoked() async {
    await ensureSettings();
    await (db.update(
      db.settings,
    )..where((tbl) => tbl.id.equals(deviceId))).write(
      SettingsCompanion(
        membershipRevoked: const Value(false),
        updatedAt: Value(_isoNow()),
      ),
    );
  }
```

Order matters: set the flag **before** `clearSyncLink()`, because
`clearSyncLink` also nulls local `userId` values (Task 7) and a failure
between the two should leave the device linked-and-unflagged (retryable)
rather than unlinked-and-silent.

- [ ] **Step 5: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/application/sync_engine_test.dart
```

Expected: PASS, all tests in the file.

- [ ] **Step 6: Commit**

```bash
git add lib/ test/
git commit -m "Detect a revoked membership in the pull path and record it (spec §3.5)"
```

---

### Task 11: Show the revocation notice

**Files:**
- Create: `lib/features/settings/membership_revoked_notice.dart`
- Modify: `lib/features/settings/account_section.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`
- Test: `test/features/settings/membership_revoked_notice_test.dart`

**Interfaces:**
- Consumes: `showExitConfirmSheet` / `ExitConfirmResult` (Task 9), `SettingsRepository.clearMembershipRevoked()` (Task 10), `resetAppData(AppDatabase)` (`lib/application/data_reset.dart`).
- Produces: `MembershipRevokedNotice` — a `ConsumerWidget` that renders nothing when the flag is false.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`:

```json
  "membershipRevokedTitle": "You're no longer part of this household",
  "@membershipRevokedTitle": {
    "description": "Title of the notice shown when a pull discovers this device's membership was removed server-side (spec docs/specs/household-lifecycle.md §3.5)."
  },
  "membershipRevokedBody": "Someone removed this profile from the online household, so this phone has stopped syncing. Everything you see here is still on this phone.",
  "@membershipRevokedBody": {
    "description": "Body of the membership-revoked notice. States plainly that syncing stopped and that local data is intact."
  },
  "membershipRevokedAction": "Got it",
  "@membershipRevokedAction": {
    "description": "Confirm button of the membership-revoked notice."
  },
```

In `lib/l10n/app_de.arb` (du-form):

```json
  "membershipRevokedTitle": "Du gehörst nicht mehr zu diesem Haushalt",
  "membershipRevokedBody": "Jemand hat dieses Profil aus dem Online-Haushalt entfernt, deshalb synchronisiert dieses Handy nicht mehr. Alles, was du hier siehst, ist weiterhin auf diesem Handy.",
  "membershipRevokedAction": "Verstanden",
```

Regenerate:

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter gen-l10n
```

- [ ] **Step 2: Write the failing test**

Create `test/features/settings/membership_revoked_notice_test.dart`:

```dart
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/household_repository.dart';
import 'package:chore_app/data/repositories/settings_repository.dart';
import 'package:chore_app/features/settings/membership_revoked_notice.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the membership-revoked notice (spec
/// `docs/specs/household-lifecycle.md` §3.5): the honest replacement for a
/// device that silently stopped syncing.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpNotice(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MembershipRevokedNotice()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders nothing when the flag is not set', (tester) async {
    await HouseholdRepository(db).createLocalHousehold('Me');
    await pumpNotice(tester);
    expect(find.textContaining('no longer part'), findsNothing);
  });

  testWidgets('explains the revocation when the flag is set', (tester) async {
    await HouseholdRepository(db).createLocalHousehold('Me');
    await SettingsRepository(db).setMembershipRevoked();
    await pumpNotice(tester);
    expect(find.textContaining('no longer part'), findsOneWidget);
  });

  testWidgets('acknowledging keeps local data by default', (tester) async {
    final household = await HouseholdRepository(db).createLocalHousehold('Me');
    await SettingsRepository(db).setMembershipRevoked();
    await pumpNotice(tester);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    final households = await db.select(db.households).get();
    expect(
      households.map((h) => h.id),
      contains(household.id),
      reason: 'D-L3: the default is to keep this phone\'s copy',
    );
    final settings = await SettingsRepository(db).ensureSettings();
    expect(settings.membershipRevoked, isFalse);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/membership_revoked_notice_test.dart
```

Expected: FAIL to compile — `membership_revoked_notice.dart` does not exist.

- [ ] **Step 4: Implement the notice**

Create `lib/features/settings/membership_revoked_notice.dart`:

```dart
/// The membership-revoked notice (spec
/// `docs/specs/household-lifecycle.md` §3.5): what this device shows once
/// a pull discovers it was removed from its online household. Without it,
/// the device keeps displaying a complete, healthy-looking household that
/// silently stopped updating -- the §0.1 trap.
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/data_reset.dart';
import 'package:chore_app/features/settings/exit_confirm_sheet.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A banner shown while `settings.membershipRevoked` is set.
///
/// Renders nothing at all in the normal case, so it is safe to place
/// unconditionally in the Account section.
class MembershipRevokedNotice extends ConsumerWidget {
  /// Creates the notice.
  const MembershipRevokedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final revoked =
        ref.watch(settingsProvider).valueOrNull?.membershipRevoked ?? false;
    if (!revoked) {
      return const SizedBox.shrink();
    }

    return semantic(
      'membership.revoked.banner',
      child: Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.membershipRevokedTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.membershipRevokedBody,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: semantic(
                  'membership.revoked.acknowledge',
                  child: FilledButton(
                    onPressed: () => _acknowledge(context, ref, l10n),
                    child: Text(l10n.membershipRevokedAction),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acknowledge(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final result = await showExitConfirmSheet(
      context,
      title: l10n.membershipRevokedTitle,
      body: l10n.membershipRevokedBody,
      actionLabel: l10n.membershipRevokedAction,
      semanticPrefix: 'membership.revoked',
    );
    if (!result.confirmed) {
      return;
    }
    final database = ref.read(appDatabaseProvider);
    await ref.read(settingsRepositoryProvider).clearMembershipRevoked();
    if (result.alsoDeleteLocalData) {
      await resetAppData(database);
      ref.invalidate(settingsProvider);
    }
  }
}
```

If `settingsRepositoryProvider` is named differently, find it with
`grep -rn "SettingsRepository(" lib/app/providers.dart`.

- [ ] **Step 5: Mount it in the Account section**

In `lib/features/settings/account_section.dart`, add
`const MembershipRevokedNotice(),` as the FIRST child of the section's
column, above the existing rows. It renders nothing unless the flag is set.

- [ ] **Step 6: Run to verify it passes**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter test test/features/settings/membership_revoked_notice_test.dart test/features/settings/account_section_test.dart
```

Expected: PASS in both files.

- [ ] **Step 7: Run the full suite and analyze**

```bash
env -u GIT_DIR -u GIT_INDEX_FILE flutter analyze --fatal-infos && env -u GIT_DIR -u GIT_INDEX_FILE flutter test
```

Expected: `No issues found!` and all tests passing.

- [ ] **Step 8: Commit**

```bash
git add lib/ test/
git commit -m "Show an honest notice when this device's membership was revoked (spec §3.5)"
```

---

## Done criteria for slices 1–3

- `supabase test db` green, 21/21 in `002_membership_exit_test.sql`.
- `flutter analyze --fatal-infos` clean; `flutter test` green.
- No user-facing exit action exists yet — that is slices 4–6, which get
  their own plan once Task 1's gate result is known.
- Manual live smoke against the local stack (following `sync-backend.md`
  §7.7's method) is worth doing after Task 6, before the client slices:
  two accounts, one household, remove one from the other's device, confirm
  the removed device surfaces the notice on its next pull.
