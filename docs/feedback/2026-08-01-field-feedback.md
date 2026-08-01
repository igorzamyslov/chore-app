# Field feedback triage — 2026-08-01

Source: Igor's first real-use feedback batch. Each item was investigated
in code before prioritizing. Priority = impact on the family actually
using the app; Effort = implementation cost including tests. Decisions
were made unilaterally per Igor's instruction ("better for you to make
decisions and document them than block the implementation") — every
decision is recorded here with its reasoning and can be revisited.

## Matrix

| ID | Item | Priority | Effort | Verdict |
|----|------|----------|--------|---------|
| B2 | Reopen ×2 loses today's occurrence | **P0** | M | Fix now (LIFO reopen) |
| B3 | Skipping a future completion-anchored occurrence re-adds the same date | **P0** | S | Fix now (skip anchors at due date) |
| B1 | "Done" snackbar can stay on screen indefinitely | P1 | S | Fix now (repro test first) |
| B4 | Export row stranded under Daily summary | P1 | XS | Fix now ("Data" section with Reset) |
| G2 | No light/dark theme switch | P1 | S–M | Build now (Appearance setting) |
| G1 | Cart section collapses while unchecking | P1 | S | Fix now (+ "put all back" action) |
| G3 | Repeat form wording/mental model | P1 value, M–L effort | M | Copy+plural fixes now; structural redesign specced separately |
| F1 | Top-5 suggestions on input focus | P2 | S | Build now (infra exists) |
| F3 | Avatars everywhere names appear | P2 | S | Build now |
| F7 | Settings overcrowded → submenus | P2 | M | Light regroup now (with B4); submenu split deferred |
| C1 | EU/GDPR personal-data check | P1 (doc) | S | Analysis written; in-app disclosure lands with sync UI |
| F2 | Delete ALL personal data (local+remote) | P2 | — | Already roadmapped: local reset exists; remote = sync spec P4 (delete account) |
| F5 | Fine-grained notifications | P2 | L | Backlog (N2, already planned) |
| F4 | Custom avatars, color as ring | P3 | M | Backlog |
| F6 | More icons/colors to pick from | P3 | S | Backlog |

## Bugs — findings and decisions

### B2 — reopen double-click loses the today occurrence (P0)

Reproduced by code inspection (`ChoreService.reopenOccurrence`,
`lib/application/chore_service.dart`). The service deletes **all** pending
occurrences of the chore before restoring the reopened row, on the spec's
assumption that "a chore has at most one pending occurrence, and it's the
one inserted by this close". That assumption breaks exactly in Igor's
scenario (completion-anchored chore, complete today's occurrence A, then
also complete the newly generated future occurrence B, then reopen both):
the second reopen deletes the sibling the first reopen just restored —
today's occurrence is destroyed with no undo.

**Decision: LIFO reopen.** Closed-today occurrences of one chore can only
be reopened newest-first (by due date, then close time). The service
rejects non-latest reopens; the Done-today UI only offers Reopen on each
chore's latest closed-today row (the affordance reappears on the next row
as the chain unwinds). Unwinding "complete A, complete B" therefore takes
two taps in reverse order and restores exactly the original state — a
true undo, which is what the button promises. Rationale: the alternative
(allowing out-of-order reopens and keeping multiple pending occurrences)
breaks the one-pending-per-chore invariant the whole app is built on.

### B3 — future-occurrence close semantics (P0, same cluster)

`nextDueDateAfterClosing` (recurrence engine): schedule-anchored chores
already advance past `max(closedDueDate, closedOn)` — closing a future
occurrence behaves sanely. Completion-anchored chores always anchor at
`closedOn`, so skipping a future occurrence (due today+3) today creates a
replacement at… today+3. Looks like "the skip did nothing".

**Decision (matches Igor's instinct):**
- **Done** stays anchored at `closedOn` — "watered the plants again today
  → next watering 3 days from today" is the whole point of
  completion-anchoring. Completing a future occurrence early on the same
  day yields a successor at the same date; correct, if visually
  anticlimactic.
- **Skip** anchors at `max(closedOn, closedDueDate)` — skipping the
  attempt scheduled for Friday means "next attempt 3 days after Friday",
  not "3 days after the day I tapped skip". For overdue/today skips
  nothing changes (`closedOn` is the max).

### B1 — sticky "Done" snackbar (P1)

All snackbars go through `showAppSnackbar` with an explicit 4s duration,
so a plain timer bug is ruled out. Leading suspects: the app shell's
nested `ScaffoldMessenger` over an `IndexedStack` (a tab switch mutes the
hidden tab's tickers mid-animation, which can freeze the dismiss
sequence), and app suspension pausing timers. **Decision:** the fix must
start from a failing widget test that reproduces the stuck state
(complete → switch tab → pump past 4s → switch back); mechanism-blind
patches are not acceptable. Regardless of root cause, tab switches also
now clear any showing snackbar — a "Done" toast is contextual to the tab
it happened on.

### B4 — settings layout (P1, trivial)

Agreed. Export and Reset become one "Data" section at the bottom
(header + export row + reset row). Done together with a light regrouping
pass (see F7).

## Gaps — decisions

### G1 — cart section collapses while unchecking (P1)

`ShoppingCheckedSection` is an uncontrolled, collapsed-by-default
`ExpansionTile`; rebuilds can reset it while the user is working inside
it. **Decision:** hoist expansion into controlled state that survives
item moves, PLUS add a "Put all back" action for the bulk case Igor
described (payment failed → whole cart returns to the list). Use cases
covered: single mis-tap (stays open), bulk restore ("Put all back"),
finished shopping ("Clear checked" — existing).

### G2 — theme switch (P1)

Settings gains an Appearance row (sheet like the Language picker):
System / Light / Dark, persisted as a nullable `themeMode` settings
column (client schema v7 — settings are device-scoped, never synced),
`null` = follow system, applied via `MaterialApp.themeMode`. The dark
`ColorScheme` derives from the same seed as light.

### G3 — repeat form wording (P1 value; staged)

Igor's walkthrough identified real comprehension traps. Two stages:

**Stage 1 (now, copy-level):**
- Pluralize units with the interval ("2 months", not "2 Month") — proper
  `plural` l10n messages for day/week/month in both languages.
- Anchor options renamed to say what they do, not what they are:
  "On a fixed schedule" → "On fixed days" with subtitle naming the
  computed pattern; "After last completion" subtitle becomes a concrete
  sentence ("3 days after the last time it was done").
- The monthly "On the 1st Saturday" row gains a subtitle pointing at the
  lever that actually controls it: "Follows the start date — change the
  start date to change the day."

**Stage 2 (specced later, structural):** make the pattern directly
editable (weekday picker for weekly, day-of-month picker for monthly)
instead of deriving everything from the start date. That is a
recurrence-engine + form redesign; not a quick fix, deliberately not
rushed alongside sync work.

## Features

- **F1 (now):** the suggestion engine already ranks by frequency+recency
  with prefix matching and list-exclusion. Change: focusing the empty
  quick-add field shows the top 5 (empty-prefix query). Ranking stays
  "most added, recency as tiebreak" — "most checked" would hide staples
  you add but haven't bought yet.
- **F3 (now):** reuse `MemberAvatar` wherever members are named — chore
  form assignee chips, acting-member sheet, rotation order list.
- **F7 (light now, rest later):** with B4's Data section the settings
  screen gets clear section grouping; a full submenu split (General /
  Notifications / Data / About) is deferred until after the sync UI
  settles, since Account/household rows are still landing there.
- **F2:** local wipe exists (Reset app data); remote wipe is the sync
  spec's P4 "delete account" (server-side edge function + G6 semantics).
  One combined "delete everything" entry point will be added there.
- **F4/F5/F6:** backlog, in that order of likely value (N2 notifications
  first when picked up).

## C1 — EU privacy check (analysis)

Current state: the app is local-first; without sign-in, NO personal data
leaves the device (no analytics, no crash reporting, no tracking of any
kind). With sync (rolling out now): email address (auth), member names,
colors, chore/shopping content are stored in the operator's Supabase
project (EU hosting selectable; Igor's project region should be
verified in the dashboard — Settings → General).

Assessment for a self-hosted family app distributed as open source:
- Igor operating a Supabase instance for his own family is squarely the
  GDPR "purely personal or household activity" exemption (Art. 2(2)(c)).
  No consent banner is needed for that use.
- BUT the app is publicly distributed, so strangers may point it at
  their own backends or Igor's build defaults. What we owe users is
  transparency, data minimalism (already true), and deletion. Actions:
  1. In-app: the sign-in screen gets one plain sentence above the email
     field stating what is stored and where (lands with the sync UI
     polish, before any public announcement of sync).
  2. Repo: a PRIVACY.md stating the local-first posture, what sync
     stores, that the default backend is operated privately with no
     analytics, and how to self-host instead. (F-Droid also likes this.)
  3. Deletion: P4 delete-account completes the story (export already
     exists for portability).
- No consent checkbox is added: magic-link sign-in is itself an
  unambiguous, affirmative act for exactly the processing described next
  to the field; a pre-ticked-checkbox ritual would add friction without
  adding lawfulness.

## Execution order (today)

1. Wave 1 — chores lifecycle (B2+B3+B1), spec-first. ← highest impact
2. Wave 2 — settings (B4 + G2 + light F7 regroup).
3. Wave 3 — shopping (G1 + F1).
4. Wave 4 — polish (F3 avatars + G3 stage 1 copy).
5. PRIVACY.md + sign-in disclosure line (C1) — with the sync UI work.

Sync P2c (join household) continues in parallel throughout; it remains
the top standing priority (multi-phone).
