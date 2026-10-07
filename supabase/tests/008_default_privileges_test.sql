-- pgTAP: migration 20261007120000_revoke_default_privileges.sql.
-- The API roles hold exactly the privileges the migrations grant: never
-- TRUNCATE, REFERENCES, TRIGGER (Supabase default-privilege leftovers) and
-- never DELETE (soft deletes only, initial schema "Explicit table grants").
begin;
create extension if not exists pgtap with schema extensions;

select plan(2);

select is(
  (select count(*) from information_schema.table_privileges
    where grantee in ('anon', 'authenticated')
      and table_schema = 'public'
      and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')),
  0::bigint,
  'no API role holds TRUNCATE, REFERENCES or TRIGGER on any public table');

select is(
  (select count(*) from information_schema.table_privileges
    where grantee in ('anon', 'authenticated')
      and table_schema = 'public'
      and privilege_type = 'DELETE'),
  0::bigint,
  'DELETE is granted to no API role (soft deletes only)');

select * from finish();
rollback;
