# Famdo privacy notes

Famdo is a local-first family chores and shopping app. This document
describes what data the app handles, where it goes, who can see it, and how
to get rid of it. (Plain-language engineering notes, not legal boilerplate —
each statement below describes what the code in this repository does. The
analysis behind them lives in `docs/feedback/2026-08-01-field-feedback.md`
§C1 and `docs/feedback/2026-10-06-persona-review.md`.)

## Who is responsible

The app's author (Igor Zamyslov, github.com/igorzamyslov) writes Famdo and,
for the release builds, operates the backend described below. There is no
company behind it and no support team; questions and requests go through
the issue tracker of the repository.

## Without an account (the default)

Everything you enter — household members, chores, completion history,
shopping items, settings — is stored **only in a local database on your
device**. Nothing leaves the device. The app contains **no analytics, no
ads, and no tracking of any kind**, and it makes no network requests on
your behalf other than the ones described below. (Error reports are the
one diagnostic channel; they need an account, see below.)

- Opening links (donations, source code, this page) launches your
  browser; nothing is sent by the app.
- Notification reminders are scheduled by your phone's operating system
  from the local data; the app does not use a push service.
- "Export data" (Settings → Data) builds a JSON file of your members,
  chores, history and shopping list and hands it to the share sheet. It
  goes wherever you choose to send it.
- "Reset app data" (Settings → Data) deletes the local database and every
  saved copy of an earlier household (see below), irreversibly. Deleting
  the saved copies is best effort: a file the system refuses to delete is
  noted in the local error buffer, but the reset still completes.

## Saved copies of earlier households (on your device)

If you join or reconnect to a household while this device already holds
data of its own, that data is replaced by the household's. Before it is,
the app writes a full copy of it — the same JSON as "Export data" — into
its own storage area on the device (the app's documents folder) (`famdo-archive-<date and time>.json`).

- The copies never leave the device on their own and are not uploaded.
- Settings → Data → "Saved copies of earlier households" lists them, with
  Share and Delete for each. The app cannot open or import them itself.
- "Reset app data" deletes all of them. Uninstalling the app removes them
  with the rest of its storage.

## With an account (optional sync)

If you sign in (magic-link email) and put your household online, the
following is stored on the configured Supabase backend so your family's
devices can share it:

- your email address and sign-in timestamps (Supabase Auth; used for
  signing in only),
- the household: its name, its members (name, color, and — for the member
  profile you claimed — your account's random user id), and its invite
  codes (short-lived, 7 days, deleted with their creator's account),
- chores (title, notes, schedule, category, who they are assigned to), the
  history of completed and skipped occurrences including who did them,
  shopping items (name, quantity note, category, who added them and when
  they were checked off), and categories (name, icon, color),
- random ids and timestamps on all of the above,
- error reports (below), unless you turn them off.

That is the complete list. Settings (language, theme, notification
preferences) and the saved copies never leave the device.

Everyone in a household can see everything in it, including each other's
names and what each person completed. There is no per-person privacy inside
a household, and nobody can see another household. Access between
households is enforced server-side with row-level security: each account
can only read and write the household(s) it belongs to. The operator of the
backend can read the data in the database.

Deleting a chore, shopping item, category or member inside a household
marks the row as deleted rather than erasing it: the row stays on the
server, hidden from the apps, for as long as the household exists. It
disappears for good when the household itself is purged (see "Deleting
your data").

### Error reports

When something goes wrong in the app (a failed sync, a crash, a failed
action), the app records a short report on the device. If — and only if —
this device is signed in **and** linked to an online household **and** the
switch Settings → About → "Send error reports" is on (it is on by
default), the reports are uploaded to the backend. Reports recorded
earlier, before you signed in, are uploaded once those conditions hold.
Turning the switch off stops uploads; reports are still recorded on the
device (at most the newest 200) and are deleted by "Reset app data".

A report contains: when it happened, the app version, your operating
system and its version, a label for where in the app it happened, the
technical error type and message, the code location (stack trace), a few
technical details such as a table name, and **pseudonymous ids** — the
random id of the household you are linked to and the random id of your
account (filled in by the server). The ids are not your name or email, but
the operator can match them to your account.

The app tries hard to keep personal content out of reports: before storing
one it strips email addresses, anything inside quotation marks, long digit
runs, the parameters of database statements and the detail text of server
errors. This filtering is deliberately blunt and best-effort — it removes
more than it needs to — but it is a filter, not a guarantee, so the switch
exists.

The server deletes reports older than 90 days (and keeps at most 1000 per
account) every night, and deletes all of an account's reports when the
account is deleted.

## Who operates the backend

Release builds default to a Supabase-hosted Postgres project belonging to
the app's author, used for their own family and offered as-is. The region it
runs in is shown in that project's Supabase dashboard; the author's project
is intended to be EU-hosted — verify that in the dashboard rather than
taking this page's word for it. The sign-in emails are sent through
Supabase's authentication service.

Because Famdo is open source (MIT), you can instead point the app at your
**own** Supabase project at build time:

```
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

Self-hosting instructions: `docs/backend-supabase.md` and
`supabase/migrations/`.

## Deleting your data

- **On your device:** Settings → Data → Reset app data deletes the local
  database, the error buffer and all saved copies. Individual saved copies
  can be deleted from Settings → Data → "Saved copies of earlier
  households".
- **Leaving a household:** Settings → Household → "Leave the household"
  removes you from that household. Your member profile (name) stays in the
  household as a former member, so the chores and history you completed keep
  a name; you can change the name shown there on the confirm sheet before
  you leave.
- **Your account:** Settings → Household → "Delete my account" erases your
  account on the server — your email address, your sign-in, your invite
  codes and your error reports — in one step, and unlinks you from every
  household you were in. As with leaving, your member profile (name) stays
  with the household's history unless you rename it on the confirm sheet.
  Your own device keeps its local data unless you tick the box on that
  sheet.
- **A whole household:** when the last person with an account leaves or
  deletes their account, the online household is hidden from everyone
  immediately and then **permanently deleted from the server after 30
  days** (a job runs nightly), including every member profile, chore,
  history entry, shopping item, category and invite code in it. Devices keep
  their own local copy.
- Self-hosting? The same functions and the 30-day purge are in
  `supabase/migrations/`; you are the operator and can delete rows
  directly.
