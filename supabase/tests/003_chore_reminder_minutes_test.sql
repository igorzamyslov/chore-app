-- pgTAP: chores.reminder_minutes (spec docs/specs/notifications-n2.md
-- §8.2). Run: `supabase db reset && supabase test db` -- `supabase test db`
-- does NOT apply migrations on its own, so without the reset this file
-- asserts against whatever schema the stack happens to be carrying.
--
-- This file never calls test_login(), so no `reset role;` is needed: the
-- role stays whatever psql connected as for the whole transaction.
begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

select has_column('public', 'chores', 'reminder_minutes',
  'chores.reminder_minutes exists (schema v13, spec notifications-n2 §8.2)');

select col_type_is('public', 'chores', 'reminder_minutes', 'integer',
  'reminder_minutes is integer -- minutes since local midnight, not a time');

select col_is_null('public', 'chores', 'reminder_minutes',
  'reminder_minutes is nullable -- NULL is the "no individual reminder" '
  'value (D1), not an error state, so a NOT NULL here would break every '
  'chore that has no reminder');

-- The column-privilege check that matters for PostgREST: `.upsert()`
-- verifies UPDATE on EVERY payload column at plan time. `chores` has a
-- table-level UPDATE grant, so this passes for the new column too and the
-- push needs no `ignoreDuplicates` workaround. This assertion is here so a
-- future narrowing of the grant to a column list fails HERE rather than as
-- a runtime PostgREST error nobody can read.
select ok(
  has_column_privilege('authenticated', 'public.chores', 'reminder_minutes',
    'update'),
  'authenticated can UPDATE reminder_minutes, so an upsert carrying it '
  'plans successfully');

select * from finish();
rollback;
