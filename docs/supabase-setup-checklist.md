# Supabase production setup — Igor's click-by-click checklist

One-time dashboard setup so real phones can sign in and sync against
https://poflqmcogcrihaptiaqr.supabase.co. Everything here is idempotent;
nothing breaks if run twice. ~10 minutes.

## 1. Apply the schema (paste-SQL workflow)

1. Dashboard → your project → **SQL Editor** → **New query**.
2. Open `supabase/migrations/20260731120000_initial_schema.sql` from the
   repo, copy the ENTIRE file, paste, **Run**. Then do the same for EACH
   later migration in `supabase/migrations/` in filename order — they add
   the idempotent-claim retries, `server_now()`, pinned function
   search_paths, and (important for live multi-device updates) the
   **realtime publication** (`20260801160000_realtime_publication.sql`).
   Without that last one, sync still works but changes only appear on the
   other device when it's reopened, not live.
3. Expected result: "Success. No rows returned". Re-running later would
   fail on "already exists" — that's fine, it means it's applied.
4. Sanity check: **Table Editor** should now list `households`,
   `members`, `categories`, `chores`, `chore_assignees`,
   `chore_occurrences`, `shopping_items`, `household_invites`, all with
   RLS enabled (shield icon).

## 2. Auth settings

1. **Authentication → Sign In / Up → Email**: make sure the Email
   provider is **enabled**. Famdo uses magic links only — disable
   "Email + password" sign-ups if offered separately; leave OTP/magic
   link on. ("Confirm email" toggles don't apply to magic links — the
   link IS the confirmation.)
2. **Authentication → URL Configuration → Redirect URLs**: add
   ```
   famdo://auth-callback
   ```
   (exact string, no trailing slash). Without this the magic link opens
   a browser error instead of bouncing back into the app.
3. Optional hardening, recommended: **Authentication → Rate Limits** —
   the defaults are fine; just confirm email sending is rate-limited.
4. Email sender: the built-in Supabase mailer is fine for family scale
   (a few links per month). No SMTP setup needed.

## 3. Verify region & keys (1 minute)

- **Settings → General**: note the project region (for the privacy
  docs; EU region preferred — if it's not EU and you care, now is the
  cheapest moment to recreate the project, BEFORE real data lands).
- **Settings → API**: confirm the publishable key matches what's baked
  into the app (`sb_publishable_cvRY2-oho4l-adK88B6Pwg_rR12ZIKc`, also
  in `docs/backend-supabase.md`). Never copy the `service_role` key
  anywhere.

## 4. First real test (after the P2 app build is on your phone)

1. Settings → Account → enter your email → "Send sign-in link".
2. Open the email ON THE PHONE → tap the link → app opens, shows your
   email as signed in.
3. Tap "Put my household online". After it completes, Members shows an
   "Invite" row.
4. Second phone: sign in with the OTHER family member's email → "Join an
   existing household" → enter the invite code → claim your profile.

If step 2 bounces to a browser error page, re-check §2.2. If step 3
fails with a permissions error, §1 wasn't applied (or only partially) —
re-run the SQL and read the error it prints.
