-- Join funnel (persona review 2026-10-06, plan
-- docs/plans/2026-10-06-persona-review-fixes.md W5).
--
-- 1. peek_invite (W5.2, finding D3): the claim step used to offer
--    "Are you Anna?" with no word about WHICH household the code belongs
--    to, and claimed on one tap. The client now asks for the household's
--    display name first and shows it in the chooser and the confirm line
--    ("Join {household} as {name}?").

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
