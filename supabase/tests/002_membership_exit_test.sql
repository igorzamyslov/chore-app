-- pgTAP: membership exit (spec docs/specs/household-lifecycle.md §2.8).
-- Run: `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

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

select * from finish();
rollback;
