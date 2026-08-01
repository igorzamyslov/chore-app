-- server_now(): the P3 sync engine's pull-cursor clock source (spec
-- docs/specs/sync-backend.md §8.3) — the client NEVER trusts the device
-- clock for `syncLastPulledAt`, it stores this value fetched in the same
-- round trip as the pull. SECURITY INVOKER; safe for any authenticated
-- caller; no table access.
create or replace function public.server_now()
returns timestamptz
language sql
stable
as $$ select now(); $$;

revoke execute on function public.server_now() from public, anon;
grant execute on function public.server_now() to authenticated;
