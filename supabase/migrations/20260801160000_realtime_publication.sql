-- Realtime for the P3 sync engine (spec docs/specs/sync-backend.md §8.3d).
-- Found live 2026-08-01 during the two-device test: push + pull-on-resume
-- worked, but a change on one device did NOT appear LIVE on the other —
-- the `supabase_realtime` publication was empty, so Supabase broadcast no
-- postgres_changes events at all. Realtime only fires for tables
-- explicitly in this publication; add the seven synced tables.
--
-- RLS still applies to realtime: each subscriber only receives change
-- events for rows its household membership can see (the client further
-- filters on the denormalized household_id). No data leak — the same RLS
-- policies that gate SELECT gate the realtime stream.
--
-- `settings` is deliberately excluded (device-scoped, never synced).
alter publication supabase_realtime add table
  public.households,
  public.members,
  public.categories,
  public.chores,
  public.chore_assignees,
  public.chore_occurrences,
  public.shopping_items;
