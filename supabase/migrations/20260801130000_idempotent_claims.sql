-- Idempotent claim/join retries (2026-08-01, closes the client join flow's
-- documented retry gap — lib/application/household_join_service.dart
-- "Known limitation"): a join that fails AFTER claim_member /
-- join_as_new_member succeeded (download/replace interrupted) is retried
-- by re-invoking the same RPC. Before this migration the second call
-- always failed ('profile not claimable' / unique violation), permanently
-- bricking the join for that account. Now:
--
--   * claim_member: if p_member_id is ALREADY claimed by the caller,
--     return its household id as success — before invite validation, so a
--     retry still works when the invite expired between attempts (the
--     caller already redeemed it; the claimed row is the proof).
--   * join_as_new_member: same short-circuit when p_member_id already
--     exists and belongs to the caller. (The client passes the SAME member
--     uuid on retry — generated once per join attempt series, not per
--     call.)
--
-- Claims by a DIFFERENT user keep failing exactly as before. Both
-- functions stay SECURITY DEFINER with the same grants; no schema change.

create or replace function public.claim_member(p_code text, p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite household_invites;
  v_existing uuid;
  v_claimed int;
begin
  -- Idempotent retry: this exact profile is already the caller's. Only a
  -- previously successful redemption can have produced this state, so the
  -- invite is deliberately NOT re-validated (it may have expired since).
  select household_id into v_existing from members
    where id = p_member_id and user_id = auth.uid();
  if v_existing is not null then
    return v_existing;
  end if;

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
  v_existing uuid;
begin
  -- Idempotent retry — same reasoning as claim_member above.
  select household_id into v_existing from members
    where id = p_member_id and user_id = auth.uid();
  if v_existing is not null then
    return v_existing;
  end if;

  v_invite := _valid_invite(p_code);
  insert into members (id, household_id, name, color, role, user_id)
    values (p_member_id, v_invite.household_id, p_member_name, p_color,
            'member', auth.uid());
  return v_invite.household_id;
end;
$$;
