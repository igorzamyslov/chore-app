-- Join funnel (persona review 2026-10-06, plan
-- docs/plans/2026-10-06-persona-review-fixes.md W5).
--
-- 1. peek_invite (W5.2, finding D3): the claim step used to offer
--    "Are you Anna?" with no word about WHICH household the code belongs
--    to, and claimed on one tap. The client now asks for the household's
--    display name first and shows it in the chooser and the confirm line
--    ("Join {household} as {name}?").
-- 2. leave_household soft-deletes the caller's own member row (W5.6,
--    finding D8) -- see the second half of this file.

-- peek_invite: the household name an active invite code would join.
--
-- Validation is delegated to _valid_invite (20260808120000_membership_exit.sql
-- is its latest form), so the rules stay in ONE place: not revoked, not
-- expired, household not cascaded. Every rejection is re-raised as the same
-- plain 'invalid code' -- an outsider learns nothing about why, exactly like
-- the redemption family. The client maps any message containing `invalid`
-- or `expired` to its "check the code" copy (join_flow_steps.dart
-- joinCodeErrorMessage).
--
-- Reveals no more than list_claimable_members already does for the same
-- code (which hands out every unclaimed member's name): a code holder is
-- by definition invited to see this household.
create or replace function public.peek_invite(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
  v_name text;
begin
  begin
    v_invite := _valid_invite(p_code);
  exception when raise_exception then
    raise exception 'invalid code';
  end;
  select h.name into v_name from households h
    where h.id = v_invite.household_id;
  if v_name is null then
    raise exception 'invalid code';
  end if;
  return v_name;
end;
$$;

revoke execute on function public.peek_invite(text) from public, anon;
grant execute on function public.peek_invite(text) to authenticated;

-- 2. leave_household soft-deletes the leaver's own profile (W5.6, finding
--    D8). Before this, leaving only unclaimed the row: the person stayed in
--    every rotation and every assignee list, and nobody was told. Now the
--    family stops seeing them in rotations at the next pull (the client's
--    pulled-member hook detaches a newly soft-deleted member from its
--    chores, ChoreRepository.detachMemberFromChores); their history stays,
--    because soft-deleted members are still rendered in Chore history.
--
--    The reclaim-via-invite path this used to preserve is gone on purpose
--    (spec docs/specs/household-lifecycle.md §2.2, amendment 2026-10-06):
--    rejoining means "I'm new here" or an unclaimed profile.
--
--    Order matters: the soft delete is stamped BEFORE _exit_membership and
--    the orphan cascade, all in this one transaction. _cascade_if_orphaned
--    counts claimed live rows, which the unclaim alone already removes, so
--    the cascade decision is unchanged -- the last claimed member leaving
--    still cascades the household (D-L5).
--
--    coalesce(): idempotent on a row someone already soft-deleted through
--    the members UPDATE grant (the state membership_exit.sql documents) --
--    keep the original stamp.
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
  update members
    set deleted_at = coalesce(deleted_at, now())
    where id = v_member_id;
  perform _cascade_if_orphaned(_exit_membership(v_member_id));
end;
$$;

revoke execute on function public.leave_household(uuid) from public, anon;
grant execute on function public.leave_household(uuid) to authenticated;
