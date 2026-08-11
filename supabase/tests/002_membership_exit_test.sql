-- pgTAP: membership exit (spec docs/specs/household-lifecycle.md §2.8).
-- Run: `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

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

select * from finish();
rollback;
