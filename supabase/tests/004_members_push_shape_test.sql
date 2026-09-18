-- pgTAP: the CLIENT's actual `members` push shape is accepted by
-- `members_insert` (spec docs/specs/sync-backend.md §8.3).
--
-- Why this file exists: 001 proves the POLICY is correct in isolation, and
-- 002 works around it (`reset role` to plant a claimed row). Neither ever
-- asserted that the shape `SupabaseSyncEngine._pushMembers` and
-- `SupabaseHouseholdGateway.uploadHouseholdData` actually send is one the
-- policy accepts. It is not, and that shipped: `memberRow` carried
-- `user_id`, so every push of a dirty CLAIMED member row was rejected 403
-- and pull-to-refresh reported "Couldn't reach the household".
--
-- Note the timestamps are passed as `timestamptz`, not text: the server's
-- `created_at`/`updated_at` are `timestamptz` while the local drift columns
-- are ISO-8601 TEXT. The client never notices because PostgREST coerces the
-- JSON string on the way in; raw SQL here does not get that for free.
--
-- The trap worth pinning: `on conflict do nothing` does NOT rescue it.
-- Postgres applies the INSERT `with check` to the proposed tuple whether or
-- not a conflict later skips it, so a row already present server-side is
-- still rejected. That is the half a Dart-side shape test cannot prove.
begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

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

select test_login('00000000-0000-0000-0000-0000000000d1');
select lives_ok(
  $$select create_household(
      '10000000-0000-0000-0000-0000000000d1'::uuid, 'Haus D',
      '20000000-0000-0000-0000-0000000000d1'::uuid, 'Dana', 4278190080)$$,
  'dana bootstraps her household via the RPC');

-- The shape the client pushes today, for a NEW member: no user_id.
select lives_ok(
  $$insert into members
      (id, household_id, name, color, role, created_at, updated_at, deleted_at)
    values ('20000000-0000-0000-0000-0000000000d2'::uuid,
            '10000000-0000-0000-0000-0000000000d1'::uuid,
            'Partner', 4278190081, 'member', now(), now(), null)
    on conflict do nothing$$,
  'the client push shape (no user_id) is accepted for a new member');

-- The same shape for a row that ALREADY EXISTS -- what a re-push of a dirty
-- member does. Must be a silent no-op, not a policy violation.
select lives_ok(
  $$insert into members
      (id, household_id, name, color, role, created_at, updated_at, deleted_at)
    values ('20000000-0000-0000-0000-0000000000d1'::uuid,
            '10000000-0000-0000-0000-0000000000d1'::uuid,
            'Dana', 4278190080, 'admin', now(), now(), null)
    on conflict do nothing$$,
  're-pushing an EXISTING member row is a no-op, not a violation');

-- The regression itself: carrying user_id is rejected even though the row
-- already exists and `on conflict do nothing` would have skipped it.
select throws_ok(
  $$insert into members
      (id, household_id, name, color, role, user_id, created_at, updated_at)
    values ('20000000-0000-0000-0000-0000000000d1'::uuid,
            '10000000-0000-0000-0000-0000000000d1'::uuid,
            'Dana', 4278190080, 'admin',
            '00000000-0000-0000-0000-0000000000d1'::uuid,
            now(), now())
    on conflict do nothing$$,
  '42501',
  'new row violates row-level security policy for table "members"',
  'pushing user_id is rejected even ON CONFLICT DO NOTHING over an existing row');

select * from finish();
rollback;
