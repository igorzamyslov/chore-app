# App Lifecycle Review (2026-07-24)

*Walkthrough of installation → registration → household/members → usage →
deletion, in BOTH worlds: v1 local-only (now) and post-sync (planned).
Each seam lists what exists, what's missing, and where the fix belongs.*

## 1. Installation / first launch

**Today**: bootstrap silently creates 'My household' + member 'Me' +
seeded categories; user lands on the empty chores list.

Gaps found:
- **G1 — Empty-state copy is wrong for a brand-new user.** 'No chores
  pending — nice work!' congratulates someone who has done nothing yet.
  First-ever-run should guide: "Add your first chore" (+ the planned
  empty-state icon/action). Distinguish "fresh install" (no chores exist
  at all) from "all done" (chores exist, none pending) — different
  messages.
- **G2 — Nobody is ever asked their name.** The bootstrap member is 'Me'
  forever; every completion reads 'von Me'. Minimal onboarding: a single
  skippable "What's your name?" prompt on first run (feeds the member
  profile; no accounts involved). Full onboarding carousel: explicitly
  NOT wanted (overload).
- **G3 — The daily digest defaults to enabled but its OS permission is
  never proactively requested** — it's only asked when the user visits
  Settings. For everyone else the flagship notification silently never
  fires. Decide the prompt moment: recommended = right after the FIRST
  chore with a due date is created ("Want a daily summary?" pre-prompt →
  OS dialog), never at cold launch.

## 2. Registration (post-sync phase — design BEFORE building sync)

Nothing exists today by design. The hairy seam is **local → cloud
migration**, and it must be specced before the Supabase phase starts:

- **G4 — Adopt-local-data flow.** First sign-in with existing local data:
  (a) "create household from my data" (upload everything), or (b) "join
  an existing household" → what happens to local chores/history? (merge
  is hard; explicit user choice + a one-time import of open chores is
  realistic; silent data loss is unacceptable.)
- **G5 — Claiming profiles.** Partner signs in on their own device and
  joins: existing local members ('Anna' created as a profile) must be
  claimable ("Are you Anna?") — the `members.user_id` column exists for
  exactly this; the FLOW is undesigned.
- **G6 — Account deletion is a STORE REQUIREMENT** (Apple mandates
  in-app account deletion when accounts exist; Play similar). Must be in
  the sync spec from day one, not retrofitted: delete account + server
  data, local-only fallback mode or data handoff.

## 3. Household & members

- Members management UI: already planned (next-session #7).
- **G7 — Acting-member switcher.** v1's stated model is "family shares
  one device", but EVERY completion is attributed to the bootstrap
  admin (actingMemberProvider = first admin). With multiple local
  members, rotation attribution and 'Done today · von X' are fiction.
  Add a lightweight switcher with the members UI (e.g. tap your avatar
  in the app bar → pick who's acting; persisted in settings). Without
  it, the members screen creates people who can never do anything.
- Member deletion needs a reassignment story (noted in plan #7).
- Multi-household: schema-ready, UI single-household — stays deferred
  until sync makes it real.

## 4. Usage (steady state)

Covered by the existing specs/tests; lifecycle-relevant leftovers:
- **G8 — Data survives only as long as the install.** No export, no
  sync yet: uninstall = everything gone. Mitigations to verify/do:
  (a) VERIFY OS auto-backup actually covers the DB: iOS backs up
  Documents/ (where chore_app.sqlite lives — likely fine, verify);
  Android auto-backup includes databases < 25MB unless allowBackup is
  off — check the manifest/flags. (b) Consider a manual JSON
  export/share as cheap insurance until sync lands (small task,
  debatable value — decide next session).
- Occurrence history grows unbounded — a non-issue at family scale for
  years; revisit with sync (server storage + sync payload size).
- Midnight rollover while app open: already in the backlog (catch-up on
  resume/day-change).

## 5. Deletion / offboarding

- **G9 — No reset story in-app.** v1: "delete all data" = uninstall.
  A Settings → 'Reset app data' (destructive, double-confirm) is cheap
  and honest; pairs naturally with the About section work.
- Chore/category/item deletion: exists with sane semantics (soft
  deletes, history retention).
- Post-sync: leave household (data stays with household), delete
  account (G6), household ownership transfer when the creator leaves —
  put all three in the sync spec.

## Priority fold-in

Next session additions (cheap, high value): G1 (two empty states),
G2 (name prompt), G7 (acting-member switcher — bundle with members UI).
Decide-next-session: G3 (digest permission moment), G8b (manual export
yes/no), G9 (reset entry).
Sync-spec prerequisites (block the backend phase until specced):
G4, G5, G6 + post-sync deletion set.
