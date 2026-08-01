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
  with prefix matching. Change: focusing the empty quick-add field shows
  the top 5 (empty-prefix query). Ranking stays "most added, recency as
  tiebreak" — "most checked" would hide staples you add but haven't
  bought yet. CORRECTION (found during implementation): type-ahead never
  excluded on-list items, and mustn't — retyping an on-list item is how
  the duplicate-prevention snackbars are reached. Exclusion therefore
  applies ONLY to the focus (empty-prefix) path, where surfacing items
  already visible on screen would be pure noise.
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

## Round 2 (2026-08-01, shopping suggestions)

F1 (focus-suggestions) shipped earlier today; Igor's first real use of it
surfaced four bugs, all in `ShoppingRepository.suggestions` and the
quick-add row/list screen that consume it. Root-caused individually
before any fix landed.

### Bug 1 — explicitly deleted items still got proposed

`suggestions()`'s empty-prefix (focus) path builds its candidate pool
from the household's FULL history, including soft-deleted rows — correct
for items cleared after shopping (`clearChecked` soft-deletes checked
items; re-suggesting those staples is the point of F1), but wrong for
items the user deleted outright without ever buying them: those kept
coming back every time the field was focused.

**Product decision — the deleted-vs-cleared rule:** the distinguishing
signal is `checked_at`, not just `deleted_at`. Only the MOST RECENT
history row for a normalized name is consulted:
- most recent row deleted while still unchecked (`deleted_at != null &&
  checked_at == null`) → "I removed this, stop offering it" → excluded
  from focus-suggestions.
- most recent row checked THEN deleted (`checked_at != null`, i.e. a
  `clearChecked` sweep after a shopping trip) → stays eligible; this is
  exactly the staple-restocking case F1 exists for.
- Because only the latest row counts, re-adding a name after an explicit
  deletion (a newer row) makes it eligible again regardless of the
  earlier deletion — there's no permanent "blocklist".

This exclusion applies ONLY to the empty-prefix (focus) path. The
non-empty-prefix (type-ahead) path is unchanged on purpose: retyping an
on-list or recently-deleted name is how B3's duplicate-prevention
snackbars ("Already on the list" / "Moved back to the list") are
reached, and narrowing that pool would regress it.

### Bug 2 — proposals sometimes didn't appear until switching tabs

The quick-add field's suggestion refresh was wired only to
`FocusNode`'s listener, which fires on a focus CHANGE. Returning to the
Shopping tab with the field still focused (it never actually lost focus,
since `ShoppingListScreen` stays mounted in the tab `IndexedStack`), or
tapping a field that was already focused, produced no change event, so
nothing re-queried. Fix: an explicit `onTap` on the `TextField` calls the
same `_updateSuggestions()` unconditionally, independent of whether
focus itself changed.

### Bug 3 — proposals never went away while the user worked the list

The field keeps focus while its suggestion list is showing, so the list
stayed open indefinitely while the user checked items off underneath it
— nothing dismissed it except an explicit blur. Fix: the quick-add field
is now unfocused (reusing the existing blur-hides-suggestions path)
whenever the user turns to the list — on a user-driven scroll
(`NotificationListener<ScrollNotification>` reacting only to
`ScrollStartNotification` with non-null `dragDetails`, so programmatic
scrolls and overscroll glow are ignored) and on any item check/tap. No
blanket `GestureDetector` was added, to avoid swallowing taps elsewhere
on the screen.

### Bug 4 — tapping a proposal left it visibly still proposed

`_addOrRestore` cleared the input and re-requested focus at the end,
relying on the text-changed listener to refresh suggestions — which
works after a typed submit (the controller goes from non-empty to
empty, so `clear()` does notify), but a suggestion tap never typed
anything: the controller is already empty, so `clear()` is a no-op and
never notifies. The just-added item stayed in the proposed list until
some other event forced a refresh. Fix: `_addOrRestore` now calls
`_updateSuggestions()` explicitly at the end on every path. Since the
newly-added item is immediately active, Bug 1's own exclusion rule drops
it out of the pool right away, and the next-best candidate moves into
the top 5 — the behavior Igor asked for.

### Fallout on existing tests

One pre-existing widget test ("focusing the empty quick-add field shows
the top-5...") seeded its cleared-history fixtures by deleting items
directly without ever checking them first — i.e. it was unknowingly
exercising the exact "deleted-while-unchecked" shape Bug 1's fix now
excludes. Updated the fixture to check each item before deleting it
(mirroring a real `clearChecked` trip), which is what the test always
intended to simulate; behavior asserted by the test (cleared items stay
suggested) is unchanged, only the seeding got more precise.
