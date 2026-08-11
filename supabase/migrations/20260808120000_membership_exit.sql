-- Membership exit (spec docs/specs/household-lifecycle.md §2): leave,
-- remove-a-member, delete-account, and the orphan-household cascade.
-- All three public RPCs are SECURITY DEFINER over internal helpers that
-- are never granted to authenticated.

-- The auth.users foreign keys (§2.7). Three constraints reference
-- auth.users with NO ACTION. The unclaim handles members.user_id; these
-- two are NOT NULL and would block `delete from auth.users` for every
-- account that ever created a household or an invite -- which is every
-- account delete_account exists for. Both columns are write-only (no RLS
-- policy, RPC or client reads them), so relaxing them is safe:
--   * a household outlives its creator by design (§0: the household owns
--     its data), so a null creator is the honest representation;
--   * invites are ephemeral 7-day codes and should die with their creator.
alter table public.households
  alter column created_by drop not null;
alter table public.households
  drop constraint households_created_by_fkey;
alter table public.households
  add constraint households_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null;

alter table public.household_invites
  drop constraint household_invites_created_by_fkey;
alter table public.household_invites
  add constraint household_invites_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete cascade;

-- delete_account (§2.2, D-L4), first form: unclaim every membership, then
-- delete the auth user. The auth.users delete works because this function
-- is owned by `postgres`, which has rights on the auth schema -- no edge
-- function and no service-role key. Task 1's pgTAP case proves that.
--
-- The unclaim is NOT optional padding: members.user_id is the third
-- NO ACTION foreign key to auth.users, and unlike the two created_by
-- columns it must NOT be relaxed -- is_household_member() reads it, so it
-- is load-bearing for every RLS policy. Nulling it here is what the
-- finished form does anyway (§2.2 loops over memberships), so this stub is
-- a true subset of the final behaviour rather than a throwaway.
--
-- Still deliberately INCOMPLETE: no orphan cascade, and no reuse of the
-- _exit_membership / _cascade_if_orphaned helpers, which do not exist yet.
-- Task 6 replaces this body entirely. Do not add the cascade here.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  update members set user_id = null where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- Internal: sever one member row's claim. Returns the household id so
-- callers can run the cascade check. NEVER granted to authenticated --
-- unclaiming must go through the three authorized RPCs.
create or replace function public._exit_membership(p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
begin
  update members set user_id = null
    where id = p_member_id
    returning household_id into v_household_id;
  if v_household_id is null then
    raise exception 'no such member';
  end if;
  return v_household_id;
end;
$$;

revoke execute on function public._exit_membership(uuid)
  from public, anon, authenticated;

-- leave_household (§2.2): unclaims ONLY. The profile stays active so the
-- family keeps seeing the person and their history, and they can reclaim
-- it later through the invite path. Takes the household id explicitly --
-- user_id is UNIQUE per household, so an account may belong to several.
create or replace function public.leave_household(p_household_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_id uuid;
begin
  if not is_household_member(p_household_id) then
    raise exception 'not a member of this household';
  end if;
  select id into v_member_id from members
    where household_id = p_household_id
      and user_id = auth.uid()
      and deleted_at is null;
  perform _cascade_if_orphaned(_exit_membership(v_member_id));
end;
$$;

revoke execute on function public.leave_household(uuid) from public, anon;
grant execute on function public.leave_household(uuid) to authenticated;

-- Internal: soft-delete a household that has no claimed members left
-- (§2.4). Child rows are deliberately left alone -- RLS already hides
-- every row once nobody is a member, so cascading them buys nothing and
-- costs a large write. `updated_at` is trigger-maintained; do not set it.
create or replace function public._cascade_if_orphaned(p_household_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed int;
begin
  select count(*) into v_claimed from members
    where household_id = p_household_id
      and user_id is not null
      and deleted_at is null;
  if v_claimed > 0 then
    return false;
  end if;
  update households set deleted_at = now()
    where id = p_household_id and deleted_at is null;
  return true;
end;
$$;

revoke execute on function public._cascade_if_orphaned(uuid)
  from public, anon, authenticated;

-- remove_member (§2.2): unclaims AND soft-deletes another member's
-- profile. Any member may remove any other (D-L2 -- the household is flat
-- by D1; role is not consulted). Self-removal is rejected: that is
-- leave_household, which keeps the profile claimable. Idempotent on an
-- already-removed row and tolerant of an unclaimed target, so a retry
-- after a partial failure is safe.
create or replace function public.remove_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_caller_member_id uuid;
begin
  select household_id into v_household_id from members
    where id = p_member_id;
  if v_household_id is null then
    raise exception 'no such member';
  end if;
  if not is_household_member(v_household_id) then
    raise exception 'not a member of this household';
  end if;
  select id into v_caller_member_id from members
    where household_id = v_household_id
      and user_id = auth.uid()
      and deleted_at is null;
  if v_caller_member_id = p_member_id then
    raise exception 'use leave_household to remove yourself';
  end if;
  update members
    set user_id = null,
        deleted_at = coalesce(deleted_at, now())
    where id = p_member_id;
end;
$$;

revoke execute on function public.remove_member(uuid) from public, anon;
grant execute on function public.remove_member(uuid) to authenticated;
