-- Client error reports (spec docs/specs/client-error-reporting.md §5.1).
--
-- Write-only for clients: `authenticated` is granted INSERT (plus SELECT on
-- `id` alone, see below) and no SELECT policy, UPDATE or DELETE -- the operator reads
-- via the dashboard / MCP (service role, postgres). That is also why the
-- client upload is `upsert(..., onConflict: 'id', ignoreDuplicates: true)`
-- with no `.select()`: ON CONFLICT DO NOTHING needs no UPDATE privilege, and
-- a returning select would need SELECT (the members 42501 lesson).
--
-- `household_id` deliberately has no foreign key: error rows must never block
-- or be cascaded by household lifecycle. `user_id` does cascade on
-- `auth.users`, so deleting an account deletes its reports (PRIVACY.md).
-- Not added to the realtime publication.
create extension if not exists pg_cron with schema pg_catalog;

create table public.client_errors (
  id            uuid primary key,
  user_id       uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  household_id  uuid,
  source        text not null check (char_length(source) <= 100),
  error_type    text not null check (char_length(error_type) <= 200),
  message       text not null check (char_length(message) <= 1000),
  stack         text check (char_length(stack) <= 8000),
  context       jsonb,
  count         integer not null default 1 check (count >= 1),
  first_seen_at timestamptz not null,
  last_seen_at  timestamptz not null,
  app_version   text not null check (char_length(app_version) <= 50),
  platform      text not null check (char_length(platform) <= 100),
  received_at   timestamptz not null default now()
);

create index client_errors_user_received_idx
  on public.client_errors (user_id, received_at desc);

alter table public.client_errors enable row level security;
revoke all on table public.client_errors from anon, authenticated;
grant insert on table public.client_errors to authenticated;
-- `select (id)` only because ON CONFLICT (id) -- which PostgREST always
-- emits for the client's ignore-duplicates upsert -- needs SELECT on the
-- conflict-target column (pgTAP 005 caught this). It exposes nothing: there
-- is no SELECT policy, so RLS hides every row, and no other column is
-- readable at all.
grant select (id) on table public.client_errors to authenticated;

create policy client_errors_insert on public.client_errors
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- Nightly retention: 90 days, and at most the newest 1000 rows per user.
create or replace function public.prune_client_errors()
returns void
language sql
set search_path = public
as $$
  delete from public.client_errors
   where received_at < now() - interval '90 days';
  delete from public.client_errors c
   using (select id from (select id, row_number() over (
            partition by user_id order by received_at desc, id desc) as rn
          from public.client_errors) ranked where rn > 1000) extra
   where c.id = extra.id;
$$;
revoke execute on function public.prune_client_errors()
  from public, anon, authenticated;

select cron.schedule('prune-client-errors', '17 3 * * *',
                     'select public.prune_client_errors()');
