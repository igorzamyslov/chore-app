# Plan: next session (feedback round 4, captured 2026-07-24)

*Analysis done, nothing implemented yet. Ordered by severity.*

## 1. BUG (confirmed by code inspection): done → pause → unpause resurrects today's instance

User repro: recurring task → complete today's instance → pause → unpause →
today's instance is back as "not done".

Root cause, traced in `ChoreService.unpauseChore`
(lib/application/chore_service.dart): for a schedule-anchored rule the
fresh occurrence is created at `nextScheduledOnOrAfter(rule, startDate,
today)` — and **today is itself a valid slot**, so the already-completed
slot gets a second pending occurrence. The done row still exists (check
"Done today"), but the list shows the chore as open again.

Fix: unpause must schedule at the first slot that is BOTH ≥ today AND
strictly after the latest closed occurrence's due date:
`nextScheduledOnOrAfter(rule, startDate, maxPlainDate(today,
latestClosed.dueDate.addDays(1)))` (completion-anchored: analogous —
`latestClosed.closedOn + interval` if that's > today, else today...
decide exact rule in spec update; update occurrence-lifecycle.md §2
unpauseChore + service tests incl. the exact user repro as a scenario).

## 2. BUG (confirmed by code inspection): "Done" snackbars stack and overstay

User report: snackbar covers the tab bar and "doesn't seem to disappear".
Two compounding causes:
- `SnackBarBehavior.fixed` (default) overlays the bottom tab bar.
- `ScaffoldMessenger.showSnackBar` QUEUES: completing N chores quickly
  shows N snackbars back-to-back at 5s each — subjectively "never goes
  away". `_showSnackbar` in chores_list_screen.dart never calls
  `clearSnackBars()`.

Fix plan:
- `behavior: SnackBarBehavior.floating` with margin above the tab bar.
- `clearSnackBars()` before showing a new one (latest action wins).
- Duration 5s → 4s.
- KEEP the snackbar for now (it carries the next-due info + undo; the
  user floated removing it — revisit after the fix lands; if still
  annoying, fallback design: only show for skip + recurring completes,
  never for one-offs, since Done-today already covers reopen).

## 3. VERIFY (believed correct, needs tests): past/future completes in "Done today"

The section filters on `closed_on == today`, not due date — so completing
an overdue (past-due) occurrence or a future-due occurrence today SHOULD
appear there. Believed working by design; add explicit widget tests for
both cases (overdue completed today; tomorrow-due completed today) and
extend the done_today E2E journey with the overdue case.

## 4. Duplicate chore names: allowed by design, must be WELL TESTED

User decision (2026-07-24): no prohibition, no warning hint — duplicates
are legitimate ("Water plants" bedroom vs balcony). The requirement is
confidence that nothing misbehaves when two chores share a title.

Test matrix to add (all operations must target the right ROW, never
match by title):
- two same-named chores, different categories/assignees: complete one →
  only that occurrence closes; the other stays pending; Done-today shows
  exactly one entry with the right closer.
- skip/pause/delete via the menu on one → the sibling untouched.
- undo/reopen restores the correct one.
- both visible under the same section, filters treat them independently.
- edit one's title → sibling unchanged.
- E2E journey with two same-named chores driven purely by occurrence-id
  selectors (our id-first selector convention exists precisely for this).

## 5. Settings: language override + About section

- **Language**: Settings row with System / English / Deutsch. Persist in
  the existing `settings` table (new nullable `locale` column → schema
  v3 migration; null = follow system). MaterialApp gets `locale:` from a
  provider. Note: gen_l10n localeName is already threaded through
  recurrence labels, so override propagates for free.
- **About**: app name + version/build (needs `package_info_plus`),
  licenses page (Flutter's built-in `showLicensePage` — required
  hygiene), placeholder row for future donation/tip-jar link (disabled
  until the IAP phase). Semantic ids under `settings.about.*`.

## 6. Design exploration: depth without overload (NOT a requirement)

User direction: current UI is very flat; likes glass ONLY as a
background layer with solid, readable cards on top (reference screenshot:
dark card on soft glassy backdrop). Guardrail: must not get "overloaded".

Plan: prototype TWO variants on the simulator next session, screenshot
side-by-side, let the user pick (or reject both):
- **Variant A — cards**: tiles/sections become M3 surfaceContainerLow
  cards (solid, 12dp radius), background stays plain. Zero readability
  risk, subtle depth.
- **Variant B — glass backdrop**: variant A's solid cards PLUS a soft
  blurred gradient wash (seed-color tinted) as the scaffold background
  layer only. Text never sits on glass. Check dark mode + contrast +
  E2E determinism (no animated backgrounds).
Update design-language.md with whichever wins BEFORE rolling out.

## Sequencing proposal

1. Bug #1 (unpause) + bug #2 (snackbar) with tests — small, high impact.
2. Verifications #3 + #4 (tests first, then the duplicate-name hint).
3. #5 language + About (schema v3).
4. #6 design prototypes → user picks → rollout + visual QA pass.
5. Then back to the roadmap checkpoint: backend/sync phase (needs the
   user's Supabase account), N2 notifications, release prep.
