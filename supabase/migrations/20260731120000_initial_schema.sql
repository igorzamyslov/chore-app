-- Famdo sync backend, initial schema (spec docs/specs/sync-backend.md §1-2).
-- Fail-closed posture: the project disables auto-expose and enables
-- auto-RLS; this migration still grants + enables RLS explicitly so it is
-- correct on ANY project settings.

-- ---------------------------------------------------------------------------
-- updated_at is server-maintained: the pull cursor must be monotonic per the
-- SERVER clock, so client-sent values are always overwritten (spec §1).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables (mirror lib/data/db/tables.dart; snake_case; soft deletes only).

create table public.households (
  id uuid primary key,
  name text not null,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.members (
  id uuid primary key,
  household_id uuid not null references public.households (id),
  name text not null,
  color bigint not null,
  role text not null,
  user_id uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  -- One claimed profile per account per household (spec §1).
  constraint members_one_claim_per_household unique (household_id, user_id)
);

create table public.categories (
  id uuid primary key,
  household_id uuid not null references public.households (id),
  kind text not null,
  name text not null,
  icon text not null,
  color bigint not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.chores (
  id uuid primary key,
  household_id uuid not null references public.households (id),
  title text not null,
  notes text,
  category_id uuid references public.categories (id),
  recurrence text,
  start_date text not null, -- PlainDate 'yyyy-mm-dd', identical to local
  assignment_mode text not null,
  paused_at timestamptz,
  created_by uuid references public.members (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- household_id denormalized on the two chore-child tables so RLS policies
-- and realtime filters stay one-hop (spec §2); the client fills it on push.
create table public.chore_assignees (
  chore_id uuid not null references public.chores (id),
  member_id uuid not null references public.members (id),
  household_id uuid not null references public.households (id),
  position integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (chore_id, member_id)
);

create table public.chore_occurrences (
  id uuid primary key,
  chore_id uuid not null references public.chores (id),
  household_id uuid not null references public.households (id),
  due_date text not null, -- PlainDate 'yyyy-mm-dd'
  status text not null default 'pending',
  assigned_member_id uuid references public.members (id),
  completed_by uuid references public.members (id),
  closed_on text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.shopping_items (
  id uuid primary key,
  household_id uuid not null references public.households (id),
  name text not null,
  quantity_note text,
  category_id uuid references public.categories (id),
  added_by uuid references public.members (id),
  checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  code text not null unique,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  revoked_at timestamptz
);

-- Pull-cursor index per table (spec §3: rows with updated_at > cursor).
create index households_pull_idx on public.households (updated_at);
create index members_pull_idx on public.members (household_id, updated_at);
create index categories_pull_idx on public.categories (household_id, updated_at);
create index chores_pull_idx on public.chores (household_id, updated_at);
create index chore_assignees_pull_idx on public.chore_assignees (household_id, updated_at);
create index chore_occurrences_pull_idx on public.chore_occurrences (household_id, updated_at);
create index shopping_items_pull_idx on public.shopping_items (household_id, updated_at);

-- updated_at triggers everywhere (incl. INSERT: the very first server
-- timestamp must also be server-authored).
do $$
declare t text;
begin
  foreach t in array array[
    'households','members','categories','chores','chore_assignees',
    'chore_occurrences','shopping_items','household_invites'
  ] loop
    execute format(
      'create trigger %I before insert or update on public.%I
         for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS. Membership helper is SECURITY DEFINER so policies on `members`
-- itself don't recurse.

create or replace function public.is_household_member(hid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.members m
    where m.household_id = hid
      and m.user_id = auth.uid()
      and m.deleted_at is null
  );
$$;

alter table public.households enable row level security;
alter table public.members enable row level security;
alter table public.categories enable row level security;
alter table public.chores enable row level security;
alter table public.chore_assignees enable row level security;
alter table public.chore_occurrences enable row level security;
alter table public.shopping_items enable row level security;
alter table public.household_invites enable row level security;

-- households: members read/update; direct INSERT is NOT allowed (bootstrap
-- goes through create_household so the creator's member row exists
-- atomically); no DELETE anywhere (soft deletes only).
create policy households_select on public.households
  for select using (public.is_household_member(id));
create policy households_update on public.households
  for update using (public.is_household_member(id));

-- members: members of the household read/update; INSERT allowed for
-- UNCLAIMED profiles only (the app's members screen creates those) —
-- linking a user_id to a profile happens exclusively through the claim
-- RPCs, and the user_id column is not even UPDATE-granted (see grants).
create policy members_select on public.members
  for select using (public.is_household_member(household_id));
create policy members_insert on public.members
  for insert with check (
    public.is_household_member(household_id) and user_id is null
  );
create policy members_update on public.members
  for update using (public.is_household_member(household_id));

-- Plain data tables: full member access except DELETE.
create policy categories_select on public.categories
  for select using (public.is_household_member(household_id));
create policy categories_insert on public.categories
  for insert with check (public.is_household_member(household_id));
create policy categories_update on public.categories
  for update using (public.is_household_member(household_id));

create policy chores_select on public.chores
  for select using (public.is_household_member(household_id));
create policy chores_insert on public.chores
  for insert with check (public.is_household_member(household_id));
create policy chores_update on public.chores
  for update using (public.is_household_member(household_id));

create policy chore_assignees_select on public.chore_assignees
  for select using (public.is_household_member(household_id));
create policy chore_assignees_insert on public.chore_assignees
  for insert with check (
    public.is_household_member(household_id)
    -- The denormalized household_id must actually be the chore's.
    and exists (
      select 1 from public.chores c
      where c.id = chore_id and c.household_id = chore_assignees.household_id
    )
  );
create policy chore_assignees_update on public.chore_assignees
  for update using (public.is_household_member(household_id));

create policy chore_occurrences_select on public.chore_occurrences
  for select using (public.is_household_member(household_id));
create policy chore_occurrences_insert on public.chore_occurrences
  for insert with check (
    public.is_household_member(household_id)
    and exists (
      select 1 from public.chores c
      where c.id = chore_id and c.household_id = chore_occurrences.household_id
    )
  );
create policy chore_occurrences_update on public.chore_occurrences
  for update using (public.is_household_member(household_id));

create policy shopping_items_select on public.shopping_items
  for select using (public.is_household_member(household_id));
create policy shopping_items_insert on public.shopping_items
  for insert with check (public.is_household_member(household_id));
create policy shopping_items_update on public.shopping_items
  for update using (public.is_household_member(household_id));

-- household_invites: members may list their household's invites (to revoke
-- them); creation/redemption only via RPCs. The code column never reaches
-- non-members through any policy — redemption looks it up inside a
-- SECURITY DEFINER function.
create policy household_invites_select on public.household_invites
  for select using (public.is_household_member(household_id));
create policy household_invites_update on public.household_invites
  for update using (public.is_household_member(household_id));

-- ---------------------------------------------------------------------------
-- RPCs (spec §2). All SECURITY DEFINER with pinned search_path.

-- Atomic household bootstrap: household + the creator's claimed member row.
create or replace function public.create_household(
  p_household_id uuid,
  p_name text,
  p_member_id uuid,
  p_member_name text,
  p_color bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  insert into households (id, name, created_by)
    values (p_household_id, p_name, auth.uid());
  insert into members (id, household_id, name, color, role, user_id)
    values (p_member_id, p_household_id, p_member_name, p_color, 'admin',
            auth.uid());
  return p_household_id;
end;
$$;

-- Member-only invite creation; 8 chars from an unambiguous alphabet.
create or replace function public.create_invite(p_household_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not is_household_member(p_household_id) then
    raise exception 'not a member of this household';
  end if;
  v_code := (
    select string_agg(
      substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
             1 + floor(random() * 32)::int, 1), '')
    from generate_series(1, 8)
  );
  insert into household_invites (household_id, code, created_by)
    values (p_household_id, v_code, auth.uid());
  return v_code;
end;
$$;

-- Shared validation for the redemption family.
create or replace function public._valid_invite(p_code text)
returns public.household_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  select * into v_invite from household_invites
    where code = p_code and revoked_at is null and expires_at > now();
  if v_invite.id is null then
    raise exception 'invalid or expired invite';
  end if;
  return v_invite;
end;
$$;

-- Step 1 of joining: what unclaimed profiles could I be? (G5)
create or replace function public.list_claimable_members(p_code text)
returns table (member_id uuid, member_name text, member_color bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
begin
  v_invite := _valid_invite(p_code);
  return query
    select m.id, m.name, m.color from members m
    where m.household_id = v_invite.household_id
      and m.user_id is null
      and m.deleted_at is null
    order by m.created_at;
end;
$$;

-- Step 2a: claim an existing unclaimed profile ("Are you Anna?").
create or replace function public.claim_member(p_code text, p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
  v_claimed int;
begin
  v_invite := _valid_invite(p_code);
  update members
    set user_id = auth.uid()
    where id = p_member_id
      and household_id = v_invite.household_id
      and user_id is null
      and deleted_at is null;
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    raise exception 'profile not claimable';
  end if;
  return v_invite.household_id;
end;
$$;

-- Step 2b: join as a brand-new member instead.
create or replace function public.join_as_new_member(
  p_code text,
  p_member_id uuid,
  p_member_name text,
  p_color bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
begin
  v_invite := _valid_invite(p_code);
  insert into members (id, household_id, name, color, role, user_id)
    values (p_member_id, v_invite.household_id, p_member_name, p_color,
            'member', auth.uid());
  return v_invite.household_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Explicit table grants (fail-closed project: nothing is auto-exposed, so
-- every privilege here is deliberate). RLS then scopes rows. DELETE is
-- granted NOWHERE — soft deletes only, and even a future policy mistake
-- can't enable hard deletes without a grant appearing in a migration diff.
grant usage on schema public to authenticated;
grant select, update on public.households to authenticated;
-- members: INSERT is policy-limited to unclaimed profiles; UPDATE is
-- column-scoped so user_id (the claiming link) can never be set outside
-- the SECURITY DEFINER claim RPCs, and household_id/created_at are
-- immutable from the client.
grant select, insert on public.members to authenticated;
grant update (name, color, role, deleted_at)
  on public.members to authenticated;
grant select, insert, update on public.categories to authenticated;
grant select, insert, update on public.chores to authenticated;
grant select, insert, update on public.chore_assignees to authenticated;
grant select, insert, update on public.chore_occurrences to authenticated;
grant select, insert, update on public.shopping_items to authenticated;
grant select, update on public.household_invites to authenticated;
-- anon gets nothing at all (not even USAGE beyond the platform default).

-- Lock down function execution: authenticated users only (anon gets
-- nothing; the client is always signed in before calling any of these).
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.create_household(uuid, text, uuid, text, bigint),
  public.create_invite(uuid),
  public.list_claimable_members(text),
  public.claim_member(text, uuid),
  public.join_as_new_member(text, uuid, text, bigint),
  public.is_household_member(uuid)
to authenticated;
