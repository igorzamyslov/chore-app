-- Supabase linter 0011 (function_search_path_mutable), reported from the
-- production dashboard 2026-08-01: `set_updated_at` and `server_now` were
-- created without a pinned search_path (every other function already sets
-- it). Pinning prevents name-resolution hijacking via a manipulated
-- search_path; no behavior change.
--
-- The linter's OTHER warning batch — 0029, SECURITY DEFINER functions
-- executable by `authenticated` — is INTENTIONAL and accepted for all six
-- RPCs: they are the deliberate narrow API for signed-in users, required
-- precisely because invite redemption/claiming must touch rows the caller
-- isn't yet RLS-entitled to; each does its own auth/validation internally,
-- proven by the pgTAP suite (anon rejected, cross-user claims rejected,
-- expired invites rejected). Recorded in docs/backend-supabase.md.
alter function public.set_updated_at() set search_path = public;
alter function public.server_now() set search_path = public;
