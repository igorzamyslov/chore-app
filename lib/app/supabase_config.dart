/// Compile-time Supabase configuration (spec `docs/specs/sync-backend.md`
/// §5; connection facts recorded in `docs/backend-supabase.md`).
///
/// [supabaseUrl] and [supabaseAnonKey] default to the real project's own
/// values. Both are public-by-design: the publishable (anon) key ships
/// inside the app binary on every platform, and every data-access
/// guarantee comes from the server's RLS policies, never from this key
/// being secret (spec §0: "RLS is the security boundary -- not the anon
/// key, not the client"). So a normal `flutter build`/`flutter run`, with
/// no `--dart-define` at all, already points at the real Supabase project
/// -- nothing else to configure for a production build.
///
/// Override either via `--dart-define` to point at a local stack for
/// development instead: `supabase start` (run from `supabase/`) prints its
/// own local URL and anon key; pass each as its own `--dart-define`, e.g.
/// `--dart-define=SUPABASE_URL=(local URL)
/// --dart-define=SUPABASE_ANON_KEY=(local anon key)`.
///
/// Tests (widget and E2E) need the app fully offline (spec §0: "the app
/// remains fully functional offline and for never-signed-in users") --
/// `lefthook.yml`, `.github/workflows/ci.yml`, and `tool/e2e.sh` all pass
/// BOTH defines as explicitly empty strings, which is the only way
/// [supabaseConfigured] becomes `false`. See `authGatewayProvider`
/// (`lib/app/providers.dart`), which reads this flag to decide between the
/// real `SupabaseAuthGateway` and the offline `NoopAuthGateway`
/// (`lib/application/auth_gateway.dart`).
library;

/// The Supabase project URL. Defaults to the real project
/// (`docs/backend-supabase.md`); override via `--dart-define=SUPABASE_URL=`.
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://poflqmcogcrihaptiaqr.supabase.co',
);

/// The Supabase publishable (anon) key. Defaults to the real project
/// (`docs/backend-supabase.md`); override via
/// `--dart-define=SUPABASE_ANON_KEY=`.
const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_cvRY2-oho4l-adK88B6Pwg_rR12ZIKc',
);

/// Whether Supabase is configured. `false` only when [supabaseUrl] is
/// explicitly overridden to the empty string (the two defines are always
/// set together -- see this file's header) -- the escape hatch tests, E2E,
/// and never-signing-in users all rely on to keep the app fully offline
/// (spec §0).
const bool supabaseConfigured = supabaseUrl != '';
