-- pgTAP: membership exit (spec docs/specs/household-lifecycle.md §2.7).
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
