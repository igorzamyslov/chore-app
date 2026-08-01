# Spec: UX Round 2 (user feedback, 2026-07-24)

*Source: first hands-on session feedback. Each item lists the decision and
the exact behavior; implementation is split across tasks 12–14.*

## A. Chores

### A1. Tile information density (redesign of the metadata row)
Tile layout becomes:

```
[complete circle]  Title                                    [⋮ menu]
                   [avatar·name] [category chip] [due text]
                   [note icon + note text, 1 line, ellipsized]   (only if note)
```

- **Avatar**: 20dp circle in the member's color with their initial,
  followed by the first name, shown when the occurrence is assigned.
  Unassigned ('anyone') shows nothing (no "Anyone" noise).
- **Due text on tiles where it adds information** (refined 2026-07-24
  after user feedback): HIDDEN in the Today and Tomorrow sections (the
  header already says it — repeating it is noise); SHOWN in Overdue
  ('overdue · N days' in error color — the count adds info), This week,
  This month, and Later ('in N days' up to 7 days out, locale-formatted
  date beyond, e.g. 'Fri, Jul 31'). All localized (plural rules).
- **Note line** appears only when the chore has a note.
- Fix vertical alignment: title + metadata block vertically centered
  against the leading circle (user: current top-alignment "offputting").

### A2. Sections
Add **This month** between "This week" and "Later": due after the coming
Sunday but still in the current calendar month. Final order:
Overdue · Today · Tomorrow · This week · This month · Later.
(No "in 2 days" section — the per-tile due text covers day-level
granularity without section spam.)

### A3. Done today section (+ accidental-complete protection)
Collapsed-by-default section at the very bottom: **'Done today (N)'** —
occurrences closed (done or skipped) with `closed_on == today`, shown with
strikethrough title, who closed them, done-vs-skipped marker, and a
**Reopen** action per row.

- `ChoreService.reopenOccurrence(id)`: in one transaction — delete the
  chore's current pending occurrence, reset the closed occurrence to
  pending (clear closed_on/completed_by, keep assignee). Throws StateError
  if the chore is deleted or the occurrence isn't closed-today.
- Needs `ChoreRepository.watchClosedOnDate(householdId, PlainDate)`.
- Amended 2026-08-01 (field feedback B2): with several closed-today rows
  for ONE chore, the Reopen action is rendered only on that chore's
  latest row (due date, then close time) — see the LIFO rule in
  `docs/specs/occurrence-lifecycle.md` §reopenOccurrence.

### A4. Undo snackbar on complete AND skip
After completing: 'Done — next due <due text>' (recurring) or 'Done'
(one-off), with UNDO action (calls reopenOccurrence). After skipping:
'Skipped — next due <due text>' + UNDO. This is both the answer to
"where did my skipped task go" and the second layer of
accidental-complete protection. Snackbar duration 5s, standard M3.

### A5. Paused visibility (already task #10, folded here)
Collapsed 'Paused (N)' section above 'Done today': chore title + category
+ 'paused' badge + **Resume** action (unpauseChore). Semantic ids:
`chores.paused.header`, `chores.paused.<choreId>.resume`,
`chores.done.header`, `chores.done.<occurrenceId>.reopen`.

## B. Shopping

### B1. Manual category ordering (store-layout planning)
First real content for the Settings tab: **Manage categories** (one screen,
two tabs or a kind switcher): drag-to-reorder (persists `sort_order` via a
new `CategoryRepository.reorderCategories(householdId, kind,
orderedCategoryIds)` batch update in one transaction), rename, change
icon/color, add, delete (existing soft-delete semantics). Semantic ids
under `settings.categories.*`. The shopping list order follows
automatically (it already sorts by sort_order).

### B2. Suggestions / reuse ("how do I restore Milk?")
Type-ahead suggestions under the quick-add field while typing (≥ 1 char):
top 8 matches from **all** items ever added in the household (including
soft-deleted/cleared), ranked by frequency then recency, deduplicated by
normalized name, each showing name + its most recent category. Tapping a
suggestion adds it immediately **with that category**. This is the
"restore Milk" path: one keystroke + one tap.
- Normalized name = trim, lowercase, collapse inner whitespace.
- New repository query `suggestions(householdId, prefix, {limit})`.
- NO browsable full-history list (standing decision: no walls of 900
  entries — suggestions + B3 cover reuse without one).

### B3. Duplicate prevention on add
On quick-add submit (and suggestion tap), match normalized name against
ACTIVE items:
- exists unchecked → no new row; snackbar 'Already on the list'.
- exists checked → **uncheck it** (restore); snackbar 'Moved back to the
  list'. (Adding something you already bought = you need it again.)
- otherwise → insert, inheriting the most recent category for that
  normalized name from history when the user didn't pick one.

### B4. Cart friction removal (decided 2026-07-24, user-approved)
The "In the cart" section stays (trip overview + uncheck-to-restore +
future multi-user semantics), but its friction goes:
- **'Clear checked' acts immediately — no confirmation dialog.** Items are
  soft-deleted and suggestions (B2) make recovery one keystroke away, so
  the confirm fails design-language rule 3 (confirm only what's costly).
  The `shopping.clear.confirm`/`shopping.clear.cancel` ids and dialog are
  removed; `shopping.clear` keeps its id.
- **24h auto-clear** (restores the original DESIGN.md §1 behavior that was
  lost in spec translation): during bootstrap, active checked items whose
  `checked_at` is older than 24 hours are soft-deleted. New
  `ShoppingRepository.clearCheckedOlderThan(householdId, {required
  DateTime cutoffUtc})`; called from `bootstrapProvider` with
  `clock.now() - 24h`. The list self-cleans between shopping trips; the
  Clear button becomes optional tidying.
- Tests: clear-without-dialog (update existing); auto-clear boundary
  (checked 23h ago survives bootstrap, 25h ago doesn't) with fixed clock;
  E2E clear step loses its confirm tap.

## C. Chores filters (feedback round 3, 2026-07-24)

### C1. Active-filter visibility
When a member or category filter is active, its app-bar icon button shows
a Material `Badge` dot and is tinted `colorScheme.primary` (inactive:
default `onSurfaceVariant`). Both signals, not color alone
(design-language: color never the sole carrier).

### C2. Filters apply to ALL sections
The member/category filters also filter the Paused and Done-today
sections (previously always-full — implementing agent flagged the
ambiguity, user confirmed sections must follow the filter):
- Pending occurrences: existing behavior (assigned member / chore
  category).
- Done today: match on the chore's category; member matches the person
  the row displays (completed_by for done, assigned member for skipped).
- Paused: match on the chore's category; member matches "member is among
  the chore's assignees".
- Section headers/counts reflect the filtered numbers; an aux section
  with zero matching rows disappears entirely (same rule as main
  sections).

## Test requirements
Every behavior above gets widget-test coverage (happy + edge: reopen after
catch-up day boundary → StateError path; duplicate-add all three branches;
reorder persistence round-trip; due-text boundaries 7/8 days; This-month
vs Later at month end). E2E additions: skip→undo journey; suggestion
restore journey ('Milk' add→check→clear→type 'Mi'→tap suggestion→same
category); category reorder persists across app restart
(`launchApp` without clearState).
