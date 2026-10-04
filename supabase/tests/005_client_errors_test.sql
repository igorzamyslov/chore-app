-- pgTAP: client error reports (spec docs/specs/client-error-reporting.md
-- §5.2). Clients may only INSERT their own rows; nothing else is reachable.
--
-- An UPDATE/DELETE, or a SELECT of any column but `id`, has no grant and fails
-- with 42501 before RLS is consulted. `id` alone is readable because
-- ON CONFLICT (id) needs it, but with no SELECT policy RLS returns no rows.
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'eve@test.local'),
  ('00000000-0000-0000-0000-0000000000e2', 'finn@test.local'),
  ('00000000-0000-0000-0000-0000000000e3', 'gus@test.local');

create or replace function test_login(uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- 1. insert without user_id: the default fills auth.uid().
select test_login('00000000-0000-0000-0000-0000000000e1');
select lives_ok(
  $$insert into client_errors
      (id, source, error_type, message, first_seen_at, last_seen_at,
       app_version, platform)
    values ('30000000-0000-0000-0000-0000000000e1'::uuid, 'sync.pushDirty',
            'StateError', 'boom', now(), now(), '0.13.0+20', 'android 14')$$,
  'an authenticated user inserts a row without user_id');

-- 2. another user's user_id is rejected by the policy.
select throws_ok(
  $$insert into client_errors
      (id, user_id, source, error_type, message, first_seen_at, last_seen_at,
       app_version, platform)
    values ('30000000-0000-0000-0000-0000000000e2'::uuid,
            '00000000-0000-0000-0000-0000000000e2'::uuid, 'sync.pushDirty',
            'StateError', 'boom', now(), now(), '0.13.0+20', 'android 14')$$,
  '42501',
  'new row violates row-level security policy for table "client_errors"',
  'inserting with another user''s user_id is rejected');

-- 3. the client upload shape: re-sending the same id is a silent no-op.
select lives_ok(
  $$insert into client_errors
      (id, source, error_type, message, first_seen_at, last_seen_at,
       app_version, platform)
    values ('30000000-0000-0000-0000-0000000000e1'::uuid, 'sync.pushDirty',
            'StateError', 'boom', now(), now(), '0.13.0+20', 'android 14')
    on conflict (id) do nothing$$,
  're-inserting the same id with on conflict do nothing lives');

-- 4. no SELECT / UPDATE / DELETE grant.
select throws_ok(
  $$select message from client_errors$$,
  '42501', null,
  'authenticated cannot select any content column (no grant)');
select is(
  (select count(*) from client_errors), 0::bigint,
  'the id-only grant exposes no rows: RLS has no SELECT policy');
select throws_ok(
  $$update client_errors set count = 2$$,
  '42501', null,
  'authenticated cannot update client_errors');
select throws_ok(
  $$delete from client_errors$$,
  '42501', null,
  'authenticated cannot delete client_errors');

-- 5. anon cannot insert.
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('role', 'anon', true);
select throws_ok(
  $$insert into client_errors
      (id, source, error_type, message, first_seen_at, last_seen_at,
       app_version, platform)
    values ('30000000-0000-0000-0000-0000000000e3'::uuid, 'sync.pushDirty',
            'StateError', 'boom', now(), now(), '0.13.0+20', 'android 14')$$,
  '42501', null,
  'anon cannot insert');

-- 8. authenticated cannot execute the prune function.
select test_login('00000000-0000-0000-0000-0000000000e1');
select throws_ok(
  $$select public.prune_client_errors()$$,
  '42501', null,
  'authenticated cannot execute prune_client_errors()');

reset role;

-- 6. deleting the auth user cascades their error rows.
select is(
  (select count(*) from client_errors
    where user_id = '00000000-0000-0000-0000-0000000000e1'), 1::bigint,
  'precondition: eve has one error row');
delete from auth.users where id = '00000000-0000-0000-0000-0000000000e1';
select is(
  (select count(*) from client_errors
    where user_id = '00000000-0000-0000-0000-0000000000e1'), 0::bigint,
  'deleting the user cascades their error rows');

-- 7. prune_client_errors(): 90-day age cut and the 1000-per-user cap.
-- Fresh rows for gus: 1002 recent ones plus 3 older than 90 days.
insert into client_errors
  (id, user_id, source, error_type, message, first_seen_at, last_seen_at,
   app_version, platform, received_at)
select ('40000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-0000000000e3', 'sync.pushDirty', 'StateError',
       'm' || g, now(), now(), '0.13.0+20', 'android 14',
       now() - (g || ' seconds')::interval
  from generate_series(1, 1002) g;
insert into client_errors
  (id, user_id, source, error_type, message, first_seen_at, last_seen_at,
   app_version, platform, received_at)
select ('50000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
       '00000000-0000-0000-0000-0000000000e3', 'sync.pushDirty', 'StateError',
       'old' || g, now(), now(), '0.13.0+20', 'android 14',
       now() - interval '91 days'
  from generate_series(1, 3) g;
select public.prune_client_errors();
select is(
  (select count(*) from client_errors
    where user_id = '00000000-0000-0000-0000-0000000000e3'), 1000::bigint,
  'prune keeps the newest 1000 rows per user and drops rows older than 90 days');

-- 9. the nightly job exists.
select is(
  (select count(*) from cron.job where jobname = 'prune-client-errors'),
  1::bigint,
  'the prune-client-errors cron job is scheduled');

select * from finish();
rollback;
