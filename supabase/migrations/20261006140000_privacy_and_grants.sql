-- Persona-review W6 (docs/plans/2026-10-06-persona-review-fixes.md): server
-- hygiene that backs the privacy promises.
--
--   B2  An orphaned household is soft-deleted at once (`_cascade_if_orphaned`,
--       docs/specs/household-lifecycle.md §2.4) but its rows used to stay on
--       the server for ever. A nightly job now hard-deletes everything of a
--       household that has been soft-deleted for more than 30 days.
--   H4  `households` and `household_invites` carried TABLE-level UPDATE, so
--       any member could rewrite `created_at`, `deleted_at`, an invite's
--       `expires_at` or its `code`, ... The only columns the client
--       ever writes are `households.name` and `household_invites.revoked_at`;
--       the grants now say exactly that. (`chores` and the other plain data
--       tables stay table-level on purpose: the client pushes them as
--       full-row upserts, and a column-scoped UPDATE grant makes Postgres
--       refuse a SET list that names an ungranted column AT PLAN TIME --
--       the members 42501 lesson, docs/specs/sync-backend.md §8.3.)
--       CLIENT CONTRACT: after this migration `updateHousehold` must send
--       only `{'name': ...}` and `revokeActiveInvites` only `{'revoked_at':
--       ...}`; either one naming another column fails with 42501.
--   H4  Invite codes came from `random()`, which is not a CSPRNG and is
--       seedable/predictable across calls. They now come from
--       `gen_random_bytes` (pgcrypto, installed in the `extensions` schema),
--       mapped onto the same 32-symbol alphabet; still 8 characters.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------------------
-- H4: column-scoped UPDATE grants.
revoke update on public.households from authenticated;
grant update (name) on public.households to authenticated;

revoke update on public.household_invites from authenticated;
grant update (revoked_at) on public.household_invites to authenticated;

-- ---------------------------------------------------------------------------
-- H4: CSPRNG invite codes. Same signature, security and search_path as the
-- initial schema's version; only the code generation changes. 256 is a
-- multiple of 32, so `byte % 32` maps a uniformly random byte onto the
-- alphabet with no modulo bias. The qualified `extensions.gen_random_bytes`
-- is deliberate: the pinned search_path is `public` only.
create or replace function public.create_invite(p_household_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
begin
  if not is_household_member(p_household_id) then
    raise exception 'not a member of this household';
  end if;
  v_bytes := extensions.gen_random_bytes(8);
  v_code := (
    select string_agg(
      substr(v_alphabet, 1 + (get_byte(v_bytes, i) % 32), 1), '' order by i)
    from generate_series(0, 7) as i
  );
  insert into household_invites (household_id, code, created_by)
    values (p_household_id, v_code, auth.uid());
  return v_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- B2: the purge. Deletes children in FK order, then the household row, for
-- every household soft-deleted more than 30 days ago. Returns how many
-- households it removed. Never callable by API roles; the nightly job runs
-- it as the migration owner.
create or replace function public.purge_orphaned_households()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_ids
    from households
    where deleted_at is not null
      and deleted_at < now() - interval '30 days';
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  delete from chore_occurrences where household_id = any (v_ids);
  delete from chore_assignees where household_id = any (v_ids);
  delete from chores where household_id = any (v_ids);
  delete from shopping_items where household_id = any (v_ids);
  delete from categories where household_id = any (v_ids);
  delete from household_invites where household_id = any (v_ids);
  delete from members where household_id = any (v_ids);
  delete from households where id = any (v_ids);
  return cardinality(v_ids);
end;
$$;
revoke execute on function public.purge_orphaned_households()
  from public, anon, authenticated;

select cron.schedule('purge-orphaned-households', '41 3 * * *',
                     'select public.purge_orphaned_households()');
