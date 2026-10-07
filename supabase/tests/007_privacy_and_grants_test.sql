-- pgTAP: migration 20261006140000_privacy_and_grants.sql (persona review W6).
--   H4  column-scoped UPDATE grants on households / household_invites, and
--       CSPRNG invite codes;
--   B2  purge_orphaned_households() and its nightly cron job.
--
-- A column-scoped grant fails at PLAN time (42501) whenever the SET list names
-- an ungranted column, before RLS is consulted -- the same lesson as
-- 004_members_push_shape_test.sql, and why the client pushes `{'name': ...}`
-- only.
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000007a1', 'gina@test.local'),
  ('00000000-0000-0000-0000-0000000007b1', 'hugo@test.local'),
  ('00000000-0000-0000-0000-0000000007c1', 'ida@test.local');

create or replace function test_login(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Gina's household (the grants subject), Hugo's (an outsider to it).
select test_login('00000000-0000-0000-0000-0000000007a1');
select create_household(
  '10000000-0000-0000-0000-0000000007a1'::uuid, 'Haus G',
  '20000000-0000-0000-0000-0000000007a1'::uuid, 'Gina', 4278190080);
select test_login('00000000-0000-0000-0000-0000000007b1');
select create_household(
  '10000000-0000-0000-0000-0000000007b1'::uuid, 'Haus H',
  '20000000-0000-0000-0000-0000000007b1'::uuid, 'Hugo', 4278190081);

-- ---------------------------------------------------------------------------
-- H4: households.

select test_login('00000000-0000-0000-0000-0000000007a1');
select lives_ok(
  $$update households set name = 'Haus G2'
      where id = '10000000-0000-0000-0000-0000000007a1'$$,
  'a member can update households.name');
select is(
  (select name from households
    where id = '10000000-0000-0000-0000-0000000007a1'),
  'Haus G2',
  'the rename landed');
select throws_ok(
  $$update households set created_at = now() - interval '1 year'
      where id = '10000000-0000-0000-0000-0000000007a1'$$,
  '42501', null,
  'a member cannot update households.created_at');
select throws_ok(
  $$update households set deleted_at = now()
      where id = '10000000-0000-0000-0000-0000000007a1'$$,
  '42501', null,
  'a member cannot update households.deleted_at');

-- An outsider's rename: the column grant lets the statement PLAN, RLS then
-- matches no row. Asserted in two steps (a data-modifying WITH is not
-- allowed inside the is() subquery): the update runs without error as Hugo,
-- and Gina still sees her own name afterwards.
select test_login('00000000-0000-0000-0000-0000000007b1');
select lives_ok(
  $$update households set name = 'Hacked'
      where id = '10000000-0000-0000-0000-0000000007a1'$$,
  'an outsider''s households.name update plans (grant) but is not an error');
select test_login('00000000-0000-0000-0000-0000000007a1');
select is(
  (select name from households
    where id = '10000000-0000-0000-0000-0000000007a1'),
  'Haus G2',
  'an outsider''s households.name update matched no row (RLS still applies)');

-- ---------------------------------------------------------------------------
-- H4: invites.

select test_login('00000000-0000-0000-0000-0000000007a1');
select set_config('test.code_1',
  create_invite('10000000-0000-0000-0000-0000000007a1'::uuid), true);
select set_config('test.code_2',
  create_invite('10000000-0000-0000-0000-0000000007a1'::uuid), true);

select matches(
  current_setting('test.code_1'),
  '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$',
  'create_invite returns 8 characters from the unambiguous alphabet');
select isnt(
  current_setting('test.code_1'), current_setting('test.code_2'),
  'two codes for the same household differ');

select lives_ok(
  format($$update household_invites set revoked_at = now()
             where code = %L$$, current_setting('test.code_1')),
  'a member can set household_invites.revoked_at');
select throws_ok(
  format($$update household_invites
             set expires_at = now() + interval '1 year'
             where code = %L$$, current_setting('test.code_2')),
  '42501', null,
  'a member cannot update household_invites.expires_at');
select throws_ok(
  format($$update household_invites set code = 'AAAAAAAA'
             where code = %L$$, current_setting('test.code_2')),
  '42501', null,
  'a member cannot update household_invites.code');

-- ---------------------------------------------------------------------------
-- B2: the purge job.

select throws_ok(
  $$select purge_orphaned_households()$$,
  '42501', null,
  'authenticated cannot call purge_orphaned_households()');

-- Ida's household is the one that will be purged; Hugo's stays.
select test_login('00000000-0000-0000-0000-0000000007c1');
select create_household(
  '10000000-0000-0000-0000-0000000007c1'::uuid, 'Haus I',
  '20000000-0000-0000-0000-0000000007c1'::uuid, 'Ida', 4278190082);

-- Back to the superuser to seed children and backdate the soft deletes.
reset role;
insert into categories (id, household_id, kind, name, icon, color)
  values ('30000000-0000-0000-0000-0000000007c1',
          '10000000-0000-0000-0000-0000000007c1', 'chore', 'Kitchen', 'x', 1),
         ('30000000-0000-0000-0000-0000000007b1',
          '10000000-0000-0000-0000-0000000007b1', 'chore', 'Kitchen', 'x', 1);
insert into chores (id, household_id, title, start_date, assignment_mode)
  values ('40000000-0000-0000-0000-0000000007c1',
          '10000000-0000-0000-0000-0000000007c1', 'Dishes', '2026-01-01',
          'anyone'),
         ('40000000-0000-0000-0000-0000000007b1',
          '10000000-0000-0000-0000-0000000007b1', 'Dishes', '2026-01-01',
          'anyone');
insert into chore_assignees (chore_id, member_id, household_id, position)
  values ('40000000-0000-0000-0000-0000000007c1',
          '20000000-0000-0000-0000-0000000007c1',
          '10000000-0000-0000-0000-0000000007c1', 0),
         ('40000000-0000-0000-0000-0000000007b1',
          '20000000-0000-0000-0000-0000000007b1',
          '10000000-0000-0000-0000-0000000007b1', 0);
insert into chore_occurrences (id, chore_id, household_id, due_date)
  values ('50000000-0000-0000-0000-0000000007c1',
          '40000000-0000-0000-0000-0000000007c1',
          '10000000-0000-0000-0000-0000000007c1', '2026-01-01'),
         ('50000000-0000-0000-0000-0000000007b1',
          '40000000-0000-0000-0000-0000000007b1',
          '10000000-0000-0000-0000-0000000007b1', '2026-01-01');
insert into shopping_items (id, household_id, name)
  values ('60000000-0000-0000-0000-0000000007c1',
          '10000000-0000-0000-0000-0000000007c1', 'Milk'),
         ('60000000-0000-0000-0000-0000000007b1',
          '10000000-0000-0000-0000-0000000007b1', 'Milk');
insert into household_invites (household_id, code, created_by)
  values ('10000000-0000-0000-0000-0000000007c1', 'PURGE001',
          '00000000-0000-0000-0000-0000000007c1');

-- Ida's household was orphaned 31 days ago; Hugo's one day ago.
update households set deleted_at = now() - interval '31 days'
  where id = '10000000-0000-0000-0000-0000000007c1';
update households set deleted_at = now() - interval '1 day'
  where id = '10000000-0000-0000-0000-0000000007b1';

select is(purge_orphaned_households(), 1,
  'the purge removes exactly the household stamped 31 days ago');

select is(
  (select count(*) from households
    where id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from members
      where household_id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from categories
      where household_id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from chores
      where household_id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from chore_assignees
      where household_id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from chore_occurrences
      where household_id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from shopping_items
      where household_id = '10000000-0000-0000-0000-0000000007c1')
  + (select count(*) from household_invites
      where household_id = '10000000-0000-0000-0000-0000000007c1'),
  0::bigint,
  'the purged household and every child row are gone');

select is(
  (select count(*) from households
    where id = '10000000-0000-0000-0000-0000000007b1'),
  1::bigint,
  'the household stamped 1 day ago is untouched');

select is(
  (select count(*) from members
    where household_id = '10000000-0000-0000-0000-0000000007b1')
  + (select count(*) from categories
      where household_id = '10000000-0000-0000-0000-0000000007b1')
  + (select count(*) from chores
      where household_id = '10000000-0000-0000-0000-0000000007b1')
  + (select count(*) from chore_assignees
      where household_id = '10000000-0000-0000-0000-0000000007b1')
  + (select count(*) from chore_occurrences
      where household_id = '10000000-0000-0000-0000-0000000007b1')
  + (select count(*) from shopping_items
      where household_id = '10000000-0000-0000-0000-0000000007b1'),
  6::bigint,
  'its children are untouched too');

select is(
  (select count(*) from cron.job where jobname = 'purge-orphaned-households'),
  1::bigint,
  'the purge-orphaned-households cron job is scheduled');

select * from finish();
rollback;
