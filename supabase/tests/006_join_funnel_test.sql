-- pgTAP: join funnel (migration 20261006120000_join_funnel.sql, plan
-- docs/plans/2026-10-06-persona-review-fixes.md W5.2 peek_invite, W5.6
-- leave_household soft delete).
-- Run: `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000006a1', 'olga@test.local'),
       ('00000000-0000-0000-0000-0000000006b1', 'jo@test.local');

create or replace function test_login(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Olga bootstraps "Haus O" and mints an invite.
select test_login('00000000-0000-0000-0000-0000000006a1');
select create_household(
  '10000000-0000-0000-0000-0000000006a1'::uuid, 'Haus O',
  '20000000-0000-0000-0000-0000000006a1'::uuid, 'Olga', 4278190080);
select set_config('test.peek_code',
  create_invite('10000000-0000-0000-0000-0000000006a1'::uuid), true);

-- ---------------------------------------------------------------------------
-- peek_invite (W5.2).

-- Jo, not yet a member, holds the code: he sees the household's name.
select test_login('00000000-0000-0000-0000-0000000006b1');
select is(
  peek_invite(current_setting('test.peek_code')),
  'Haus O',
  'peek_invite returns the household name for an active code');

select throws_ok(
  $$select peek_invite('NOPENOPE')$$,
  'P0001', 'invalid code',
  'peek_invite rejects an unknown code');

-- Olga revokes it (the client's revokeActiveInvites path).
select test_login('00000000-0000-0000-0000-0000000006a1');
update household_invites set revoked_at = now()
  where code = current_setting('test.peek_code');

select test_login('00000000-0000-0000-0000-0000000006b1');
select throws_ok(
  format($$select peek_invite(%L)$$, current_setting('test.peek_code')),
  'P0001', 'invalid code',
  'peek_invite rejects a revoked code');

-- A fresh code, then expired.
select test_login('00000000-0000-0000-0000-0000000006a1');
select set_config('test.peek_code_2',
  create_invite('10000000-0000-0000-0000-0000000006a1'::uuid), true);
-- Backdating `expires_at` is a superuser setup step since 20261006140000:
-- members may only UPDATE `revoked_at`.
reset role;
update household_invites set expires_at = now() - interval '1 hour'
  where code = current_setting('test.peek_code_2');

select test_login('00000000-0000-0000-0000-0000000006b1');
select throws_ok(
  format($$select peek_invite(%L)$$, current_setting('test.peek_code_2')),
  'P0001', 'invalid code',
  'peek_invite rejects an expired code');

-- A third, live code -- anon still cannot ask about it.
select test_login('00000000-0000-0000-0000-0000000006a1');
select set_config('test.peek_code_3',
  create_invite('10000000-0000-0000-0000-0000000006a1'::uuid), true);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'anon', true);
select throws_ok(
  format($$select peek_invite(%L)$$, current_setting('test.peek_code_3')),
  '42501', null,
  'anon cannot execute peek_invite');

reset role;
select ok(
  not has_function_privilege('anon', 'public.peek_invite(text)', 'execute'),
  'peek_invite is not executable by anon');

-- ---------------------------------------------------------------------------
-- leave_household soft-deletes the leaver's profile (W5.6, finding D8).

-- Jo joins Haus O as a new member (a fresh live code), so Olga stays
-- claimed and the household must survive his leaving.
select test_login('00000000-0000-0000-0000-0000000006a1');
select set_config('test.peek_code_4',
  create_invite('10000000-0000-0000-0000-0000000006a1'::uuid), true);
select test_login('00000000-0000-0000-0000-0000000006b1');
select join_as_new_member(current_setting('test.peek_code_4'),
  '20000000-0000-0000-0000-0000000006b1'::uuid, 'Jo', 4278190081);

select lives_ok(
  $$select leave_household('10000000-0000-0000-0000-0000000006a1'::uuid)$$,
  'jo can leave haus O');

reset role;
select isnt(
  (select deleted_at from members
   where id = '20000000-0000-0000-0000-0000000006b1'),
  null,
  'after leaving, the leaver''s member row has deleted_at');
select is(
  (select count(*) from members
   where id = '20000000-0000-0000-0000-0000000006b1'
     and user_id is null),
  1::bigint,
  'after leaving, the leaver''s member row is unclaimed');
select is(
  (select count(*) from households
   where id = '10000000-0000-0000-0000-0000000006a1'
     and deleted_at is null),
  1::bigint,
  'the household survives: olga is still claimed (no cascade)');

select * from finish();
rollback;
