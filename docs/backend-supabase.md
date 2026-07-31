# Supabase project (backend/sync phase)

*Connection facts recorded 2026-07-31, provided by Igor. The sync phase
itself is still blocked on its spec prerequisites (docs/app-lifecycle.md
G4 adopt-local-data, G5 profile claiming, G6 account deletion).*

- Project URL: `https://poflqmcogcrihaptiaqr.supabase.co`
  (Igor supplied it with the `/rest/v1/` Data API suffix;
  `supabase_flutter` takes the bare project URL above.)
- Publishable (anon) key:
  `sb_publishable_cvRY2-oho4l-adK88B6Pwg_rR12ZIKc`
  Public by design — it ships inside the app binary; every data-access
  guarantee comes from RLS, never from this key being secret. The
  service-role key, if ever needed (CI seed scripts etc.), must NOT be
  committed — env var only.
- Project security settings (recommended 2026-07-31, chosen at project
  creation): Data API enabled; "automatically expose new tables"
  disabled; automatic RLS enabled — i.e. both levers fail closed, every
  migration must explicitly grant + write policies for its tables.
- Planned auth: magic-link email (DESIGN.md); household isolation via
  RLS on every table; RLS covered by tests before any client code
  (docs/specs/testing-strategy.md).
