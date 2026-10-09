# Open items after the persona review — 2026-10-09 (from v0.15.1+23)

*One consolidated, prioritised list of everything still open after the
2026-10-06 persona + technical review (`2026-10-06-persona-review.md`), the
two releases that followed (PRs #61, #62: v0.15.0, v0.15.1) and the clean-up
PRs (#63 grants, #64 README, #65 screenshots). Two sources, merged: what the
personas asked for and was deferred, and the loose ends the overnight
implementation left behind. Anything not listed here shipped and was
verified on CI; the "Closed 2026-10-06" section of `../backlog.md` has the
per-finding bookkeeping.*

Priority = value to a household actually using the app, weighed against the
risk of leaving it open. Effort uses the backlog's key (XS < 1 h · S half a
day · M 1–3 days · L a week · XL multi-week).

## 0. Recommended order

1. **Verify on a phone + run iOS E2E** (A1, A2) — half a day; everything else
   in 0.15 that could only be reasoned about gets observed once.
2. **Import of the JSON export** (B1) — the top of both the organiser's and
   the privacy persona's lists; the archive story (B3 in the review) still
   ends in a file nobody can open.
3. **Sign-in row: OTP fallback, expired-link handling, honest error copy**
   (B2) — the only remaining P2 in the joiner's first ten minutes; blocked on
   one dashboard edit by Igor.
4. **Deterministic occurrence ids** (C1) — the structural end to the
   ghost-occurrence races the 0.15 sync fixes only contain.
5. **Reminder Done/Snooze actions** (B4) — the member persona's main ask that
   did not ship.
6. The rest of §B and §C as they come up; §D needs decisions before anyone
   starts.

## A. Left from the overnight work (verification and hygiene)

| # | Item | Why it matters | Prio | Effort |
|---|------|----------------|------|--------|
| A1 | **Device verification of the 0.15 features that no test observes**: the pause-until date picker, the archive "Share…" action and the Settings → Data archives list, the notification-isolate error sink (H5), "Done from a notification" showing as waiting-to-sync, the Technical details sheet, Done recently | Each crosses a process or OS boundary; the handover says these were reasoned about, not seen | P1 | S |
| A2 | **Dispatch the iOS E2E workflow on main** (Actions → E2E → Run workflow) | It is on-demand only and has not run for 0.15.0 or 0.15.1; the Maestro suite changed (Done recently header, progress card copy) | P1 | XS |
| A3 | **`test_live` case for paging past 1,000 rows** | A2 of the review (paging) is covered only by fake-transport tests; the live stack would prove the PostgREST cap is really crossed | P2 | S |
| A4 | **`ui_state` key/value column** (schema v20) | W2 stored shopping collapse state and forgotten suggestions as extra `ui_state` rows (key in `id`, value in `last_tab`) to avoid a schema bump it did not own; works, documented, but a trap for the next reader | P3 | S (bundle with the next schema bump) |
| A5 | **Prod migration bookkeeping** | The MCP stamps its own `schema_migrations` versions, so prod's history does not mirror `supabase/migrations/` filenames; a future `supabase db push` would try to re-apply everything. Document in `backend-supabase.md`, or re-stamp once | P3 | XS |
| A6 | **PRIVACY.md hosting region** | Says "intended EU, see the dashboard"; one word from Igor makes it a fact | P3 | XS |
| A7 | **Main checkout is stale** (`~/Projects/chore-app` on `08d337e`, five releases behind); the simulator still holds the demo household from the screenshots | Housekeeping | P3 | XS |
| A8 | **Oversized files**: `providers.dart` (~1,900 lines), `chores_list_screen.dart`, `account_section.dart` | Every reviewer pays for it; split opportunistically, never as its own PR | P3 | M |

## B. Left from the personas (deferred product items)

| # | Item | Review id | Persona cost | Prio | Effort | Blocker / decision |
|---|------|-----------|--------------|------|--------|--------------------|
| B1 | **Import of the JSON export / restore from an archive** | G-3, F12, B3 | Maria: "an export that can't be imported looks like a backup and isn't"; Priya: switching phones has no route for a local-only household | P1 | M | none |
| B2 | **Sign-in row**: 6-digit email OTP beside the magic link, code entry before sign-in, expired/used-link handling, rate-limit vs failure copy, resend cooldown | D2 | Leon and Priya: leave the app, find the email, open it on the same phone; one generic error for everything | P1 | M | Igor must add `{{ .Token }}` to the Supabase magic-link email template |
| B3 | **Several shopping lists** (collapsible sections, parked design 1c) | G-8 | Tom's three stores; the 0.15 collapsible categories are the interim | P2 | XL | product call: is the interim enough? |
| B4 | **Reminder notification Done / Snooze actions** (slice 7) | E8, G-6 | Leon ignores anything he can't act on from the shade | P2 | M | needs a phone to verify (A1) |
| B5 | **Share-to-app** ("add to shopping list" from any share sheet) | F-2 | Tom's partner's "oat milk, sourdough" message is exactly his input | P2 | L | none (the parser already splits on newlines for this path) |
| B6 | **In-app viewer for pending error reports** | B8 | Priya cannot see what would be sent | P3 | S | none |
| B7 | **Keep-screen-on toggle on the Shopping tab** | F8 | the screen sleeps between aisles | P3 | S | adds a dependency (wakelock) |
| B8 | **Bottom-anchored quick-add** (or a setting) | F2 | one-handed reach with a trolley | P3 | M | design call against the 2026-08-18 canvas |
| B9 | **Home-screen widget** | F-3 | the supermarket entry is three steps | P3 | XL | none |
| B10 | **Search with filters on long lists** | G-7 | a weekly family list exceeds the 15-row gate in the 1e design | P3 | M | none |
| B11 | **Fork a removed member's local copy / account in several households** | G-10, G-11 | Priya's flat-share lifecycle; after leaving, the only forward path is Reset | P3 | M | none |
| B12 | **Light-theme 12 sp labels below 4.5:1; widget tests cannot measure text** | G-13, G-14 | low-vision users; why large-text overflow is not caught by CI | P3 | S | none |
| B13 | **Role / permission model** | E4 | any member can delete anything; the delete dialog now says so | — | L | closed by decision D1; revisit only if older kids become a target |

Shipped-then-reversed by Igor's own feedback (closed, listed so nobody
reopens them): the per-row added-by mark (F1), the overdue/today split in the
progress card (E5), Disconnect while signed in (D9).

## C. Left from the technical review (structural)

| # | Item | Why | Prio | Effort |
|---|------|-----|------|--------|
| C1 | **Deterministic occurrence ids** (`uuid v5(choreId + dueDate)` for catch-up and next occurrences) | Two devices running catch-up on the same morning still create two rows and rely on the convergent survivor key; identical ids make the race disappear | P2 | M |
| C2 | **Two-device `test_live` scenarios** for the 0.15 invariants (tombstone-vs-done, assignee set replacement, field-level shopping merge) | The engine tests prove them against a fake transport; a real pair would prove them against PostgREST | P2 | M |
| C3 | **Default-privilege audit as a pgTAP invariant for every future table** | #63 fixed the existing tables and the `postgres` default; a test that fails on any new table with a stray grant keeps it fixed | P3 | XS |

## D. Decisions needed before anyone starts

- **B3 several lists vs. keep the interim** — the single biggest product
  decision left; everything about "what to buy where" hangs on it.
- **B8 bottom quick-add** — contradicts the design canvas; needs a yes/no.
- **B2's dashboard step** — the OTP fallback cannot ship without it.
- **A6** — one word (the region).

## E. Closed since the review (for the record)

Grants cleanup (#63, applied to prod and verified), docs catch-up for 0.15.1
(#63), README rewritten user-first (#64), screenshots for README and the
F-Droid metadata (#65), all twenty agent/wave worktrees removed, memory notes
for the MCP migration gotchas, local test flags and Igor's product taste.
