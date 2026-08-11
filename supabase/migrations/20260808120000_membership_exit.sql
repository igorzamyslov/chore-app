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
