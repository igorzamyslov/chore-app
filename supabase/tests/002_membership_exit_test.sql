-- pgTAP: membership exit (spec docs/specs/household-lifecycle.md §2.8).
-- Run: `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(37);

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

-- Household G: Gil and Hana both claimed, plus an unclaimed profile.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000a2', 'gil@test.local'),
       ('00000000-0000-0000-0000-0000000000b2', 'hana@test.local');

select test_login('00000000-0000-0000-0000-0000000000a2');
select create_household(
  '10000000-0000-0000-0000-0000000000a2'::uuid, 'Haus G',
  '20000000-0000-0000-0000-0000000000a2'::uuid, 'Gil', 4278190080);

reset role;
insert into members (id, household_id, name, color, role, user_id)
values ('20000000-0000-0000-0000-0000000000b2',
        '10000000-0000-0000-0000-0000000000a2', 'Hana', 4278190081,
        'member', '00000000-0000-0000-0000-0000000000b2'),
       ('20000000-0000-0000-0000-0000000000b3',
        '10000000-0000-0000-0000-0000000000a2', 'Kid', 4278190082,
        'member', null);

-- A non-member cannot remove anyone in G.
select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$select remove_member('20000000-0000-0000-0000-0000000000b2'::uuid)$$,
  'not a member of this household',
  'a non-member cannot remove a member of another household');

-- Gil cannot remove himself.
select test_login('00000000-0000-0000-0000-0000000000a2');
select throws_ok(
  $$select remove_member('20000000-0000-0000-0000-0000000000a2'::uuid)$$,
  'use leave_household to remove yourself',
  'remove_member rejects self-removal (§2.2)');

-- Gil removes Hana, a claimed member, with no role privilege (D-L2/D1).
select lives_ok(
  $$select remove_member('20000000-0000-0000-0000-0000000000b2'::uuid)$$,
  'any member can remove any other member');

reset role;
select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-0000000000b2'),
  null,
  'removal unclaims the profile');

select isnt(
  (select deleted_at from members
   where id = '20000000-0000-0000-0000-0000000000b2'),
  null,
  'removal soft-deletes the profile (unlike leaving)');

select is(
  (select deleted_at from households
   where id = '10000000-0000-0000-0000-0000000000a2'),
  null,
  'removing a member never soft-deletes the household');

-- NOTE on what this does and does not prove: it cannot distinguish
-- "_cascade_if_orphaned was never called" from "it was called and
-- correctly no-opped", because Gil is still claimed either way. It is a
-- real invariant (a removal must never take the household with it), just
-- not a proof of §2.3's mechanism. §2.3 holds structurally: self-removal
-- is rejected, so the caller is always a surviving claimed member.

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

select throws_ok(
  $$select claim_member('DEADCODE',
      '20000000-0000-0000-0000-0000000000f1'::uuid)$$,
  'invalid or expired invite',
  'claiming a profile in a cascaded household is rejected');

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

-- BLOCKING FIX 1: Household L. Lena is claimed, then another member
-- soft-deletes her profile directly (the members UPDATE grant covers
-- `deleted_at`, and does not require `user_id` to change) -- exactly the
-- state a "remove another member" abuse of that grant produces. Before
-- the fix, delete_account()'s unclaim loop filtered on
-- `deleted_at is null` and skipped this row, so the DELETE FROM
-- auth.users below hit members_user_id_fkey and the whole function
-- raised -- permanently blocking Lena's GDPR account deletion.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000d4', 'lena@test.local');

select test_login('00000000-0000-0000-0000-0000000000d4');
select create_household(
  '10000000-0000-0000-0000-0000000000d4'::uuid, 'Haus L',
  '20000000-0000-0000-0000-0000000000d4'::uuid, 'Lena', 4278190080);

-- Simulate another member soft-deleting Lena's own profile via the
-- members UPDATE grant, leaving her claim (user_id) untouched.
reset role;
update members set deleted_at = now()
  where id = '20000000-0000-0000-0000-0000000000d4';

select test_login('00000000-0000-0000-0000-0000000000d4');
select lives_ok(
  $$select delete_account()$$,
  'a member whose profile was soft-deleted while still claimed can still '
  'delete her account (blocking fix 1)');

reset role;
select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-0000000000d4'),
  null,
  'delete_account unclaims a soft-deleted-but-claimed row too');

select is(
  (select count(*)::int from auth.users
   where id = '00000000-0000-0000-0000-0000000000d4'),
  0,
  'delete_account removes the auth user even though her own profile was '
  'already soft-deleted');

-- BLOCKING FIX 3(b): Household K. Kai creates it (so households.created_by
-- = Kai) and Uli is a second claimed member. Kai deletes her account: she
-- is unclaimed but the household must survive (Uli is still claimed), and
-- households_created_by_fkey's `on delete set null` must fire rather than
-- leaving a dangling reference -- pinning that this is SET NULL, not
-- CASCADE. The suite's only other delete_account cases (Task 1, Jo) both
-- cascade their household, so neither ever exercises this branch: a
-- migration that flipped the FK to `on delete cascade` -- hard-deleting a
-- household Uli still lives in, in violation of this project's
-- soft-deletes-only invariant -- would pass 69/69 without this case.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000000d5', 'kai@test.local'),
       ('00000000-0000-0000-0000-0000000000d6', 'uli@test.local');

select test_login('00000000-0000-0000-0000-0000000000d5');
select create_household(
  '10000000-0000-0000-0000-0000000000d5'::uuid, 'Haus K',
  '20000000-0000-0000-0000-0000000000d5'::uuid, 'Kai', 4278190080);

reset role;
insert into members (id, household_id, name, color, role, user_id)
values ('20000000-0000-0000-0000-0000000000d6',
        '10000000-0000-0000-0000-0000000000d5', 'Uli', 4278190081,
        'member', '00000000-0000-0000-0000-0000000000d6');

select test_login('00000000-0000-0000-0000-0000000000d5');
select lives_ok(
  $$select delete_account()$$,
  'kai, the household creator, can delete her account while Uli is still '
  'claimed (blocking fix 3b)');

reset role;
-- This existence check comes FIRST and is not redundant with the two
-- assertions below it. A scalar subquery over a missing row yields NULL,
-- and pgTAP's is() treats NULL as equal to NULL -- so if the household
-- were ever HARD-deleted, both `is(..., null)` assertions below would
-- pass VACUOUSLY and this block would stay green while the project's
-- soft-deletes-only invariant was being violated. The realistic route to
-- that is someone adding `on delete cascade` to the child FKs to make
-- household deletion "actually work". Assert the row is still there.
select is(
  (select count(*)::int from households
   where id = '10000000-0000-0000-0000-0000000000d5'),
  1,
  'the household row still EXISTS -- a hard delete would make both NULL '
  'assertions below pass vacuously');

select is(
  (select deleted_at from households
   where id = '10000000-0000-0000-0000-0000000000d5'),
  null,
  'the household survives delete_account when a second claimed member '
  'remains -- pins ON DELETE SET NULL, not CASCADE');

select is(
  (select created_by from households
   where id = '10000000-0000-0000-0000-0000000000d5'),
  null,
  'households_created_by_fkey nulls created_by once the creator''s auth '
  'row is gone, rather than leaving it dangling');

select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-0000000000d5'),
  null,
  'delete_account still unclaims the deleting member even though the '
  'household survives');

-- BLOCKING FIX 3(a): pin the grant matrix itself, not merely behaviour
-- reachable through it. Nothing else in this suite (or 001) asserts a
-- has_function_privilege/has_table_privilege fact, so a future migration
-- containing `grant execute on all functions in schema public to
-- authenticated` would pass 69/69 unnoticed. These three internal
-- helpers are SECURITY DEFINER and must only ever be reachable through
-- the public RPCs that wrap them.
select is(
  has_function_privilege(
    'authenticated', 'public._exit_membership(uuid)', 'EXECUTE'),
  false,
  '_exit_membership is never granted to authenticated');

select is(
  has_function_privilege(
    'authenticated', 'public._cascade_if_orphaned(uuid)', 'EXECUTE'),
  false,
  '_cascade_if_orphaned is never granted to authenticated');

select is(
  has_function_privilege(
    'authenticated', 'public._valid_invite(text)', 'EXECUTE'),
  false,
  '_valid_invite is never granted to authenticated');

-- ---------------------------------------------------------------------------
-- The boundary the P2d RECONNECT PROBE rests on (spec
-- docs/specs/sync-backend.md §7.6). `SupabaseHouseholdGateway
-- .findMyMembership` runs `select ... from members where user_id = auth.uid()`
-- and, on a hit, renders a row whose tap runs a DESTRUCTIVE local replace.
-- The client also filters `deleted_at` on both selects, but those predicates
-- are defense in depth: the thing that actually closes this is
-- `public.is_household_member`'s `deleted_at is null` clause.
--
-- HONESTY NOTE, so nobody mistakes these for a fix: assertions A, B and C
-- are CHARACTERIZATION tests. They passed the moment they were written,
-- because they pin behaviour that already holds. There is no red phase for
-- them and none was manufactured. Their value is regression -- weaken
-- `is_household_member`'s `deleted_at` clause, or the households/members
-- SELECT policies, and they go red instead of a destructive replace quietly
-- going live. Assertion D is different: it is a genuinely NEW contract that
-- the Dart client's `HouseholdIdTakenFailure` branch depends on.

-- A. A removed member's own row is gone from the probe's query.
-- Gil removed Hana from Haus G above. Note honestly what this does and does
-- not isolate: `remove_member` BOTH unclaims (user_id -> null) AND
-- soft-deletes, so either one alone would produce 0 here. This pins the
-- PROBE's result -- exactly the query findMyMembership issues -- while
-- assertion B is the one that isolates RLS.
select test_login('00000000-0000-0000-0000-0000000000b2');
select is(
  (select count(*) from members
   where user_id = '00000000-0000-0000-0000-0000000000b2'),
  0::bigint,
  'a removed member''s account finds no membership row (the reconnect '
  'probe''s own query)');

-- B. A soft-deleted-but-STILL-CLAIMED row is invisible to its claimant.
-- This is the case the reconnect probe genuinely depends on RLS for: the
-- row keeps its user_id, so nothing but `is_household_member`'s
-- `deleted_at is null` clause can hide it. Build it the only way it is
-- reachable -- a direct `deleted_at` update through the members UPDATE
-- grant, the state 20260808120000_membership_exit.sql:45-61 documents.
-- Uli is used because her auth row still exists (Lena's and Hana's paths
-- above both end with the account or the claim gone).
reset role;
update members set deleted_at = now()
  where id = '20000000-0000-0000-0000-0000000000d6';

select test_login('00000000-0000-0000-0000-0000000000d6');
select is(
  (select count(*) from members
   where user_id = '00000000-0000-0000-0000-0000000000d6'),
  0::bigint,
  'a soft-deleted-but-still-claimed row is invisible to its own claimant '
  '-- only is_household_member''s deleted_at clause can do this, since '
  'user_id is untouched');

-- C. After the cascade, the departed account sees no household row either.
-- Fran left Haus E last, so E cascaded (asserted above). Her members row
-- survives, unclaimed and NOT soft-deleted (leaving keeps it claimable), so
-- `is_household_member(E)` is false for her and households_select filters
-- the row out. Asserted as count(*), never as a column against null: a
-- scalar subquery over no rows yields NULL and pgTAP's is() treats NULL as
-- equal to NULL, so `is(<col>, null)` would pass vacuously here.
select test_login('00000000-0000-0000-0000-0000000000f1');
select is(
  (select count(*) from households
   where id = '10000000-0000-0000-0000-0000000000e1'),
  0::bigint,
  'the account that left last cannot read the cascaded household row');

-- D. NEW CONTRACT (not characterization): create_household on an id that
-- already exists raises 23505. Its first statement is a plain
-- `insert into households (id, name, created_by)`
-- (20260731120000_initial_schema.sql), so a taken id is a unique_violation.
-- Run as the outsider, who is NOT a member of Haus G -- the revoked user's
-- exact position, and the only position in which this matters: after a
-- revocation the device still holds the household's id locally, so adopt
-- re-sends it. lib/application/household_gateway.dart maps precisely this
-- SQLSTATE to HouseholdIdTakenFailure, which
-- HouseholdLinkService.adopt turns into its terminal state. If this code
-- ever changes, that branch silently stops firing and adopt goes back to
-- offering a retry that can never succeed.
select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  $$select create_household(
      '10000000-0000-0000-0000-0000000000a2'::uuid, 'Haus Dup',
      '20000000-0000-0000-0000-0000000000cf'::uuid, 'Outsider', 4278190080)$$,
  '23505', null,
  'create_household on a taken household id raises unique_violation');

select * from finish();
rollback;
