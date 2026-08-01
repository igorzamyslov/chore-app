-- pgTAP: household isolation matrix + invite lifecycle + trigger contract
-- (spec docs/specs/sync-backend.md §2). Run: `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

-- ---------------------------------------------------------------------------
-- Fixtures: three auth users (inserted while still superuser), households
-- via create_household.
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-00000000000a', 'alice@test.local'),
       ('00000000-0000-0000-0000-00000000000b', 'bob@test.local'),
       ('00000000-0000-0000-0000-00000000000c', 'carol@test.local');

create or replace function test_login(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Alice bootstraps household A.
select test_login('00000000-0000-0000-0000-00000000000a');
select lives_ok(
  $$select create_household(
      '10000000-0000-0000-0000-000000000001'::uuid, 'Haus A',
      '20000000-0000-0000-0000-000000000001'::uuid, 'Alice', 4278190080)$$,
  'alice can bootstrap her household via the RPC');

-- Bob bootstraps household B.
select test_login('00000000-0000-0000-0000-00000000000b');
select lives_ok(
  $$select create_household(
      '10000000-0000-0000-0000-000000000002'::uuid, 'Haus B',
      '20000000-0000-0000-0000-000000000002'::uuid, 'Bob', 4278190081)$$,
  'bob can bootstrap his household via the RPC');

-- Alice seeds data in A.
select test_login('00000000-0000-0000-0000-00000000000a');
insert into categories (id, household_id, kind, name, icon, color, sort_order)
values ('30000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', 'chore', 'Kitchen', 'kitchen',
        4278190080, 0);
insert into chores (id, household_id, title, start_date, assignment_mode)
values ('40000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', 'Dishes', '2026-07-31',
        'anyone');
insert into chore_occurrences (id, chore_id, household_id, due_date)
values ('50000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', '2026-07-31');
insert into shopping_items (id, household_id, name)
values ('60000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', 'Milk');

-- ---------------------------------------------------------------------------
-- The isolation matrix: Bob sees NOTHING of A, on every table.
select test_login('00000000-0000-0000-0000-00000000000b');
select is((select count(*) from households
           where id = '10000000-0000-0000-0000-000000000001'), 0::bigint,
  'bob cannot see household A');
select is((select count(*) from members
           where household_id = '10000000-0000-0000-0000-000000000001'),
  0::bigint, 'bob cannot see A members');
select is((select count(*) from categories
           where household_id = '10000000-0000-0000-0000-000000000001'),
  0::bigint, 'bob cannot see A categories');
select is((select count(*) from chores
           where household_id = '10000000-0000-0000-0000-000000000001'),
  0::bigint, 'bob cannot see A chores');
select is((select count(*) from chore_occurrences
           where household_id = '10000000-0000-0000-0000-000000000001'),
  0::bigint, 'bob cannot see A occurrences');
select is((select count(*) from shopping_items
           where household_id = '10000000-0000-0000-0000-000000000001'),
  0::bigint, 'bob cannot see A shopping items');

-- Bob cannot WRITE into A (insert rejected by WITH CHECK, update a no-op).
select throws_ok(
  $$insert into chores (id, household_id, title, start_date, assignment_mode)
    values ('40000000-0000-0000-0000-00000000000f',
            '10000000-0000-0000-0000-000000000001', 'Intrusion',
            '2026-07-31', 'anyone')$$,
  '42501', null, 'bob cannot insert a chore into A');
select throws_ok(
  $$insert into shopping_items (id, household_id, name)
    values ('60000000-0000-0000-0000-00000000000f',
            '10000000-0000-0000-0000-000000000001', 'Intrusion')$$,
  '42501', null, 'bob cannot insert a shopping item into A');
update chores set title = 'Hacked'
  where id = '40000000-0000-0000-0000-000000000001';
select test_login('00000000-0000-0000-0000-00000000000a');
select is((select title from chores
           where id = '40000000-0000-0000-0000-000000000001'), 'Dishes',
  'bob''s update against A was a silent no-op');

-- Bob cannot use A's household_id lie on child tables even with a real
-- chore id from A (the WITH CHECK cross-check).
select test_login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$insert into chore_occurrences (id, chore_id, household_id, due_date)
    values ('50000000-0000-0000-0000-00000000000f',
            '40000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000002', '2026-07-31')$$,
  '42501', null,
  'bob cannot smuggle an A-chore occurrence under his own household_id');

-- DELETE is not even GRANTed (stronger than a missing policy): the
-- statement itself is rejected, for members too. Soft deletes only.
select test_login('00000000-0000-0000-0000-00000000000a');
select throws_ok(
  $$delete from chores
    where id = '40000000-0000-0000-0000-000000000001'$$,
  '42501', null, 'even a member cannot hard-delete (soft deletes only)');

-- ---------------------------------------------------------------------------
-- Invites + claiming (G5).
select test_login('00000000-0000-0000-0000-00000000000a');
-- Alice adds an unclaimed profile 'Anna' to A.
insert into members (id, household_id, name, color, role)
values ('20000000-0000-0000-0000-00000000000c',
        '10000000-0000-0000-0000-000000000001', 'Anna', 4278190082, 'member');
select lives_ok(
  $$select set_config('test.invite_code',
      create_invite('10000000-0000-0000-0000-000000000001'::uuid), true)$$,
  'alice can create an invite for her household');

-- Bob cannot create invites for A.
select test_login('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  $$select create_invite('10000000-0000-0000-0000-000000000001'::uuid)$$,
  'P0001', 'not a member of this household',
  'bob cannot mint invites for A');

-- Bob redeems Alice's code: sees exactly one claimable profile (Anna).
select is(
  (select count(*) from list_claimable_members(
    current_setting('test.invite_code'))), 1::bigint,
  'invite lists exactly the one unclaimed profile');
select lives_ok(
  format($$select claim_member(%L,
          '20000000-0000-0000-0000-00000000000c'::uuid)$$,
         current_setting('test.invite_code')),
  'bob can claim the unclaimed Anna profile');
select is(
  (select user_id from members
   where id = '20000000-0000-0000-0000-00000000000c'),
  '00000000-0000-0000-0000-00000000000b'::uuid,
  'claiming links the profile to bob''s auth user');

-- Double-claim is rejected (carol was inserted with the fixtures above,
-- while this session was still superuser).
select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  format($$select claim_member(%L,
          '20000000-0000-0000-0000-00000000000c'::uuid)$$,
         current_setting('test.invite_code')),
  'P0001', 'profile not claimable',
  'an already-claimed profile cannot be claimed again');

-- Carol joins as a brand-new member instead; now a member, sees A's data.
select lives_ok(
  format($$select join_as_new_member(%L,
          '20000000-0000-0000-0000-00000000000d'::uuid, 'Carol', 4278190083)$$,
         current_setting('test.invite_code')),
  'a fresh account can join as a new member');
select is((select count(*) from chores
           where household_id = '10000000-0000-0000-0000-000000000001'),
  1::bigint, 'a joined member gains read access to household data');

-- Idempotent retries (migration 20260801130000): re-invoking the SAME
-- claim/join by the SAME caller returns the household id instead of
-- failing — the client's join flow retries this way after an interrupted
-- download/replace.
select test_login('00000000-0000-0000-0000-00000000000b');
select is(
  claim_member(current_setting('test.invite_code'),
               '20000000-0000-0000-0000-00000000000c'::uuid),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'claim_member retry by the same claimer returns the household id');
select test_login('00000000-0000-0000-0000-00000000000c');
select is(
  join_as_new_member(current_setting('test.invite_code'),
                     '20000000-0000-0000-0000-00000000000d'::uuid,
                     'Carol', 4278190083),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'join_as_new_member retry with the same member id returns the household id');

-- Expired invite is rejected.
select test_login('00000000-0000-0000-0000-00000000000a');
update household_invites set expires_at = now() - interval '1 hour'
  where code = current_setting('test.invite_code');
select test_login('00000000-0000-0000-0000-00000000000c');
select throws_ok(
  format($$select list_claimable_members(%L)$$,
         current_setting('test.invite_code')),
  'P0001', 'invalid or expired invite', 'expired invites are rejected');

-- Bogus code is rejected.
select throws_ok(
  $$select list_claimable_members('NOPENOPE')$$,
  'P0001', 'invalid or expired invite', 'unknown codes are rejected');

-- The idempotent retry path survives invite EXPIRY too (deliberate: the
-- prior successful redemption is the proof of entitlement, so the retry
-- short-circuits before invite validation — see migration
-- 20260801130000's header).
select test_login('00000000-0000-0000-0000-00000000000b');
select is(
  claim_member(current_setting('test.invite_code'),
               '20000000-0000-0000-0000-00000000000c'::uuid),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'claim_member retry still succeeds after the invite expired');
select test_login('00000000-0000-0000-0000-00000000000c');
select is(
  join_as_new_member(current_setting('test.invite_code'),
                     '20000000-0000-0000-0000-00000000000d'::uuid,
                     'Carol', 4278190083),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'join_as_new_member retry still succeeds after the invite expired');

-- ---------------------------------------------------------------------------
-- Trigger contract: updated_at is server-authored, client values ignored.
select test_login('00000000-0000-0000-0000-00000000000b');
insert into chores (id, household_id, title, start_date, assignment_mode,
                    updated_at)
values ('40000000-0000-0000-0000-000000000002',
        '10000000-0000-0000-0000-000000000002', 'Trash', '2026-07-31',
        'anyone', '1999-01-01T00:00:00Z');
select isnt(
  (select updated_at from chores
   where id = '40000000-0000-0000-0000-000000000002'),
  '1999-01-01T00:00:00Z'::timestamptz,
  'client-sent updated_at is overwritten on insert');
select cmp_ok(
  (select updated_at from chores
   where id = '40000000-0000-0000-0000-000000000002'),
  '>', now() - interval '1 minute',
  'server stamped a fresh updated_at');

-- Anonymous role gets nothing at all — not even SELECT is granted, so the
-- query is rejected outright rather than returning an empty set.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'anon', true);
select throws_ok(
  $$select count(*) from households$$,
  '42501', null, 'anon cannot even query households');
select throws_ok(
  $$select create_invite('10000000-0000-0000-0000-000000000002'::uuid)$$,
  '42501', null, 'anon cannot execute member RPCs');

select * from finish();
rollback;
