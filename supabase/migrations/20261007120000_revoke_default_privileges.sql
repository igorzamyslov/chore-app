-- Default-privilege leftovers (found 2026-10-07 while verifying
-- 20261006140000_privacy_and_grants.sql in prod).
--
-- Supabase grants ALL on every new `public` table to anon/authenticated via
-- `alter default privileges for role postgres`, at table creation. The
-- initial schema's explicit `grant select, insert, update` statements only
-- layered on top of that, and the later cleanups removed DELETE -- so every
-- data table still carried TRUNCATE, REFERENCES and TRIGGER for both API
-- roles. PostgREST never issues those statements and the roles are only ever
-- assumed through a JWT, so there was no API path. But the project's stated
-- posture (initial schema, "Explicit table grants") is fail-closed with every
-- privilege visible in a migration diff; this makes that true, and fixes the
-- default so future tables start clean. service_role is deliberately left
-- alone (it bypasses RLS by design and is never used by the app).
revoke truncate, references, trigger on all tables in schema public
  from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;
