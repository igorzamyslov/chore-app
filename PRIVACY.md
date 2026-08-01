# Famdo privacy notes

Famdo is a local-first family chores and shopping app. This document
describes what data the app handles, where it goes, and how to get rid
of it. (Plain-language engineering notes, not legal boilerplate — the
analysis behind them lives in
`docs/feedback/2026-08-01-field-feedback.md` §C1.)

## Without an account (the default)

Everything you enter — household members, chores, completion history,
shopping items, settings — is stored **only in a local database on your
device**. Nothing leaves the device. The app contains **no analytics, no
crash reporting, no ads, and no tracking of any kind**, and it makes no
network requests on your behalf other than the ones described below.

- Opening links (donations) launches your browser; nothing is sent.
- "Export data" writes a JSON file wherever you choose to share it.
- "Reset app data" deletes the local database irreversibly.

## With an account (optional sync)

If you sign in (magic-link email) and put your household online, the
following is stored on the configured Supabase backend so your family's
devices can share it:

- your email address (authentication only),
- household name, member names and colors,
- chores, their completion history, and shopping items.

That is the complete list. Settings (language, theme, notification
preferences) never leave the device.

Access is enforced server-side with row-level security: each account can
only read and write the household(s) it belongs to.

## Who operates the backend

Release builds default to a privately operated Supabase project
belonging to the app's author, used for their own family and offered
as-is. Because Famdo is open source (MIT), you can instead point the app
at your **own** Supabase project at build time:

```
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

Self-hosting instructions: `docs/backend-supabase.md` and
`supabase/migrations/`.

## Deleting your data

- Local: Settings → Reset app data.
- Server: account deletion (removing your email and unlinking your
  member profile; household history stays with the household, per the
  design in `docs/specs/sync-backend.md`) ships with the sync feature's
  final phase. Until then, contact the backend operator or delete the
  rows via your own project if self-hosting.
