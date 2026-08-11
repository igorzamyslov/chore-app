# Chore History ("who actually does the chores", G-1 / F19) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Settings-hosted **Chore history** surface that answers "who
actually cleans the bathroom" without becoming a leaderboard, and that makes a
deleted chore's retained history reachable — so the softened delete copy can be
replaced with the honest, stronger promise (triage D2 step 2).

**Architecture:** Three read-only aggregate queries in a new `StatsRepository`
(SQL `GROUP BY`, never row-by-row in Dart), assembled by a new `StatsService`
that owns the window math (last 30 days, clamped to the household's own start
date) and the active/deleted split. Two screens under `lib/features/stats/`:
an overview (household share card + per-chore rollup + a collapsed *Deleted
chores* section) and a per-chore completion log reached by tapping a row. One
new SQLite index and a schema bump to v10 keep the windowed query a range scan
as occurrence history grows unbounded.

**Tech Stack:** Flutter 3.44, Riverpod, drift/SQLite, `package:clock`,
`package:intl`, gen_l10n (EN template + DE du-form), Maestro for E2E.

**Spec:** `docs/specs/stats.md` — **does not exist yet; Task 1 writes it**, and
every task after it implements against it. The full spec text is embedded in
Task 1; do not paraphrase it.

---

## Why this is committed work, not backlog

`docs/research/triage.md` **D2** (and `docs/backlog.md` row **G-1**): the chore
delete dialog used to promise "its history is kept". That was true in the
database (`ChoreRepository.softDeleteChore` soft-deletes the chore and retains
its done/skipped/missed occurrences) but unverifiable by the user, because every
read path filters `deletedAt IS NULL` and no history screen existed. Igor
decided the app keeps its promises: step 1 softened the copy (shipped —
`choresDeleteDialogBody` currently says "You can't view it again yet"), step 2
is this plan. **Restoring the stronger copy is part of this plan's definition of
done (Task 12), not a follow-up.** The plan is not complete until a user can
delete a chore and then find its history.

---

## The central design problem, and how this resolves it

`DESIGN.md` §1 frames occurrences as "the source of history/stats ('who actually
cleans the bathroom')". `DESIGN.md` §8 phase 3 parks streaks as "polarizing in
families". `design-language.md` demands "never gamified-loud". A fairness view
that turns into a scoreboard creates friction in exactly the households this app
is for.

The resolution, made binding by the spec in Task 1:

**A leaderboard ranks people. A fairness view describes work.** So:

1. **Only `done` is ever attributed to a person.** `skipped` and `missed` never
   appear next to a name anywhere in this feature. Two independent reasons, both
   already recorded in the project:
   - `DESIGN.md` §2: *"'skip this one' advances the schedule without crediting
     anyone **and without wrecking stats**"* — skipping is a legitimate action,
     excluded from stats by explicit product design.
   - triage **T2.1**: `missed` rows are *machine-generated* by
     `ChoreService.catchUpOverdue` when the user was away; the project already
     treats surfacing them as reading like an accusation. Counting a missed
     chore against the person it happened to be assigned to would be the
     accusation the app has been careful to avoid.
2. **Members are listed in roster order (creation order), never sorted by
   count.** No rank numbers, no medals, no "top", no highlighting a winner.
3. **No streaks, no all-time personal records, no trends or "up from last
   month" arrows.** A bounded 30-day window means nothing accumulates into a
   permanent score you can fall behind on.
4. **The per-chore list is the primary structure of the screen**, ordered
   alphabetically. "Who cleans the bathroom" is a question *about a chore*
   answered by naming people; asked the other way round it becomes
   "Anna: 47, Ben: 12".
5. **No per-member drill-down.** "Everything Anna did" is the leaderboard
   direction; the spec records it as a non-goal.

The household share card survives all of that because the fairness question
("are we actually splitting this?") is real and is what `DESIGN.md` promised.
It is shown as one proportional bar plus name/count/percent rows in fixed roster
order — a description of how one month's work divided, not a ranking.

---

## Risks and sequencing (read before starting)

- **A-5 (acting-member misattribution, triage T1.3) should land before or with
  this.** Every number on this screen comes from
  `chore_occurrences.completed_by`, which today is written from the *device-
  scoped* `actingMemberId` with an unconditional app-bar switcher and no
  linked-household gate. A fairness view is only as honest as `completedBy`.
  Shipping G-1 first does not corrupt any data — but it makes existing
  misattribution *visible and authoritative*, on the one screen whose entire
  point is "who did it". If A-5 is still open when this is executed, ship it
  anyway (the screen is honest about what the database says) but expect the
  first field report to be "it says Ben did it and that's wrong", and treat
  that as A-5 evidence, not a stats bug.
- **Sync:** occurrences are a synced table. This screen reads local data only,
  so a device that has not pulled recently shows a partial picture — the same
  property every other screen already has. No special handling; the spec says so
  explicitly so nobody adds a "syncing…" state here later.
- **`reopenOccurrence`** flips a `done` row back to `pending`; the counts drop
  by one on the next read. That is correct and needs no code.

---

## Global Constraints

- **Never run `flutter`/`dart` commands concurrently with other agents.** Run at
  most 2 concurrent `flutter test` / `build_runner` processes.
- Every user-visible string goes through gen_l10n: add to `lib/l10n/app_en.arb`
  (template, with an `@key` description block) **and** `lib/l10n/app_de.arb`
  (**du**-form). Never hardcode display text. Counts need ICU plurals in both
  locales.
- **No string concatenation for user-facing phrases** where word order differs
  across languages — use ARB placeholders. Joining whole *sentences* with `". "`
  for a screen-reader label is allowed (precedent: `ChoreProgressCard`).
- Every interactive widget gets a stable id via `semantic('<screen>.<element>')`
  from `lib/app/semantics.dart`. Never remove, rename, or move an existing id —
  they are API for 12 Maestro flows and 600+ widget tests.
- Widget tests are integration-style: real in-memory `AppDatabase` + fixed clock
  via `testChoreApp` (`test/test_utils/pump_app.dart`), overriding ONLY
  `appDatabaseProvider` and `clockProvider`. **Never mock a repository or
  service.** Seed through the real repositories/services.
- Deadlock traps: never `await` a drift stream outside a widget pump; never bare-
  `await bootstrapProvider.future` in a `ProviderContainer` test; `tester.pump(
  Duration(milliseconds: 50))` between `container.dispose()` and
  `database.close()`.
- Strict lints: `very_good_analysis`, `flutter analyze --fatal-infos
  --fatal-warnings` must be clean. **Every public member needs a doc comment.**
- `dart format` must be clean (`dart format --set-exit-if-changed .` in CI).
- Theme rules (`docs/specs/theme-v2.md` is BINDING): cards are `DepthCard`
  (radius 16, `surfaceContainerLow`, `elevation: 0`, 1px `outlineVariant`);
  never hardcode a font size — reference `Theme.of(context).textTheme` roles;
  member/category colors go through `categoryTone(context, argb)`; **no custom
  animation** (E2E determinism); all touch targets ≥ 48×48dp; text scale 2.0 is
  a release gate.
- **Naming convention, deliberate and load-bearing:** the code namespace is
  `stats` (spec `docs/specs/stats.md`, semantic ids `stats.*`, ARB keys
  `stats*`, directory `lib/features/stats/`), while every **user-visible** string
  says "Chore history" / "Aufgaben-Verlauf". Do not "fix" one to match the other.
- Never add `Co-Authored-By:` (or any co-author trailer) to a commit message.
- Commit after every task. Do not create branches; do not push.

---

## Open product decisions

These are genuinely open. **The plan below is written to be fully executable
under the recommended answer in each case** — if Igor picks a different option,
the note says which task changes.

### OPD-1 — Where does it live?

- **(a) A row in Settings → Household, under Members and Categories.**
  Quiet, costs no top-level real estate, sits beside the other
  household-administration surfaces. Cost: discoverability — a user who never
  opens Settings never finds it.
- **(b) A fourth bottom tab.** Discoverable, but a permanent 25% of the app's
  navigation for a screen a family opens maybe monthly, and it would need the
  `IndexedStack`/`shell.tab.*` work in D-1 to stay coherent.
- **(c) An action in the chores-list app bar.** Contextual, but the chores app
  bar already carries the acting-member button as `leading` and has no overflow
  menu to hang it on — one would have to be introduced.

**Recommendation: (a).** A fourth tab is a big commitment for a low-frequency
screen, and (a)'s discoverability cost is largely paid off by Task 12: the
restored delete-dialog copy names the exact path, so the moment a user has a
reason to care about retained history, they are told where it is. **Revisit** if
field feedback shows nobody finds it — promoting a Settings row to (c) later is
a small change, whereas backing out of a fourth tab is not. Changing this answer
rewrites **Task 11** only.

### OPD-2 — What time window?

- **(a) One fixed window: the last 30 days**, labelled explicitly, clamped to
  the household's own start date when the household is younger than that.
- **(b) A segmented selector: 30 days / 12 months / all time.** More power,
  but a config surface on a screen whose whole design goal is calm, and
  "all time" is exactly the permanent-record framing the anti-gamification
  stance argues against.
- **(c) All time only.** Simplest query, but the number only ever grows, it
  rewards whoever joined the household first, and a member who joined last
  month can never catch up — the most scoreboard-like option available.

**Recommendation: (a).** A bounded, explicitly-labelled window is what keeps the
share card a description of *this month* rather than a standing score, and the
clamp makes the two-day-old household honest instead of empty. Note the *per-
chore* numbers are deliberately **all-time** (see spec §3.2) — the window
belongs to the fairness question, not to "how often does this chore get done".
Changing this answer rewrites **Task 4** (service) and adds a control to
**Task 9**.

### OPD-3 — Should un-done work (skipped / missed) ever be shown?

- **(a) Never, anywhere in this feature.** Only `done` occurrences exist as far
  as Chore history is concerned.
- **(b) An unattributed per-chore count** ("Bathroom · not done 3 times"), with
  no name attached — describes the chore, not a person.
- **(c) A full per-chore status breakdown** (done / skipped / missed).

**Recommendation: (a) for v1.** `DESIGN.md` §2 already rules that a skip must
not wreck stats, and triage T2.1 already rules that machine-generated `missed`
rows read as an accusation. (b) is defensible and tempting — "the bathroom keeps
getting skipped" is real signal — but in a two-person household with a
fixed-assignee chore, an unattributed count is transparently about one person,
so it buys honesty at the cost of the exact friction this design is avoiding.
**Revisit** with real household feedback; the query for (b) is a one-line change
to the aggregate in Task 3 if it is ever wanted. Changing this answer touches
**Tasks 1, 3, 9**.

### OPD-4 — How is the member share ordered?

- **(a) Household roster order** (member creation order, matching
  `HouseholdRepository.watchMembers`), with any departed member who has
  contributions in the window appended, and the unattributed bucket last.
- **(b) Descending by count.** The most readable at a glance, and the most
  unambiguously a ranking.
- **(c) Alphabetical by name.** Neutral, but arbitrary and it reshuffles when
  someone is renamed.

**Recommendation: (a).** Stable, never re-orders as work happens, and refuses to
answer "who's winning" by construction — the single cheapest anti-leaderboard
decision in the whole design. Changing this answer touches **Task 4** only.

---

## File structure

**Created:**

| Path | Responsibility |
|---|---|
| `docs/specs/stats.md` | The binding contract for everything below (Task 1). |
| `lib/data/repositories/stats_repository.dart` | Three read-only aggregate queries + their three result types. No window math, no UI concepts. New file rather than growing `chore_repository.dart` (662 lines, already the app's largest repository) — these are read-only reporting queries with no overlap with its write primitives. |
| `lib/application/stats_service.dart` | Window math (30 days, clamped to household start), the active/deleted split, the roster-order share assembly. Pure orchestration over `StatsRepository` + `AppDatabase`; no Flutter import. |
| `lib/features/stats/stats_screen.dart` | The overview screen: share card, per-chore list, deleted section, empty/error states. |
| `lib/features/stats/stats_share_card.dart` | The household share card widget, isolated so it can be widget-tested alone. |
| `lib/features/stats/chore_history_screen.dart` | One chore's completion log (all-time, newest first, capped). |
| `test/data/repositories/stats_repository_test.dart` | Query-level tests over a real in-memory DB. |
| `test/application/stats_service_test.dart` | Window clamp, split, roster-order assembly. |
| `test/features/stats/stats_screen_test.dart` | Overview screen, integration-style. |
| `test/features/stats/chore_history_screen_test.dart` | Drill-down screen, integration-style. |
| `e2e/flows/settings/chore_history.yaml` | End-to-end proof of the D2 promise. |

**Modified:**

| Path | Change |
|---|---|
| `lib/data/db/tables.dart` | Add `@TableIndex(name: 'chore_occurrences_status_closed_on_idx', columns: {#status, #closedOn})` on `ChoreOccurrences`. |
| `lib/data/db/app_database.dart` | `schemaVersion` 9 → 10; `from < 10` branch creating the new index. |
| `lib/data/db/app_database.g.dart` | Regenerated (`build_runner`). |
| `lib/app/providers.dart` | `statsRepositoryProvider`, `statsServiceProvider`, `statsOverviewProvider` (autoDispose), `choreHistoryProvider` (autoDispose family). |
| `lib/features/settings/settings_screen.dart` | A `settings.stats` row in the Household group. |
| `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb` | ~16 new keys + the restored `choresDeleteDialogBody`. |
| `docs/specs/design-language.md` | The "hides history" parenthetical in Interaction rule 3 is no longer true. |
| `docs/backlog.md`, `docs/research/triage.md` | Mark G-1 / D2 step 2 delivered. |
| `test/data/db/schema_migration_test.dart` | A v9 → v10 test. |
| `test/features/settings/settings_test_utils.dart` | An `openChoreHistory(tester)` helper. |

---

## Task 1: Write the binding spec

**Files:**
- Create: `docs/specs/stats.md`

**Interfaces:**
- Produces: the contract every later task cites. Tasks 3–13 reference its
  section numbers (§2.1, §3.2, §4.3, …).

- [ ] **Step 1: Create `docs/specs/stats.md` with exactly this content**

````markdown
# Spec: Chore history ("who actually does the chores")

*Backlog G-1 / F19. Promoted out of the backlog by `docs/research/triage.md`
decision **D2**: the chore-delete dialog's "its history is kept" promise was
softened on the commitment that this screen gets built, at which point the
stronger copy comes back and is true. Restoring that copy is part of this
spec's definition of done, not a follow-up.*

*Binding for all work on this feature. Deviations need a reason in the commit
message.*

## 0. The stance this spec exists to protect

`DESIGN.md` §1 calls occurrences "the source of history/stats ('who actually
cleans the bathroom')". `DESIGN.md` §8 phase 3 parks streaks as "polarizing in
families". `docs/specs/design-language.md` requires "never gamified-loud".

**A leaderboard ranks people; a fairness view describes work.** Five rules make
that binding. They are not style guidance — a change to any of them needs a
product decision, not a PR.

1. **Only `done` is attributed to a person.** `skipped` and `missed` never
   appear next to a name anywhere in this feature, and are excluded from every
   count in it.
   - `skipped`: `DESIGN.md` §2 — "'skip this one' advances the schedule without
     crediting anyone **and without wrecking stats**".
   - `missed`: these rows are generated by `ChoreService.catchUpOverdue` when
     the user was simply away (`docs/specs/occurrence-lifecycle.md`
     §catchUpOverdue). `docs/research/triage.md` T2.1 already records that
     surfacing them reads as an accusation; counting them against the assigned
     member would make the app the accuser.
2. **Members appear in household roster order** (member creation order, the
   order `HouseholdRepository.watchMembers` returns), never sorted by count. No
   rank numbers, no medals, no "top", no winner styling.
3. **No streaks, no personal records, no trends, no period-over-period
   comparison.** The share window is bounded so nothing accumulates into a
   standing score.
4. **The per-chore list is the screen's primary structure**, ordered
   alphabetically by title. The question is about a chore, answered by naming
   people — not about a person, answered by counting chores.
5. **No per-member drill-down.** "Everything Anna did" is out of scope
   permanently, not deferred (§7).

## 1. Placement and naming

- Reached from **Settings → Household → Chore history**, below Members and
  Categories (semantic id `settings.stats`, icon `Icons.history_outlined`).
  Not a fourth tab: a family opens this monthly, and the bottom bar's three
  destinations are the daily ones.
- **Naming convention, deliberate:** the code namespace is `stats` (this spec,
  `lib/features/stats/`, ids `stats.*`, ARB keys `stats*`); every user-visible
  string says **"Chore history"** (DE: **"Aufgaben-Verlauf"**). Do not
  reconcile the two.

## 2. Data rules

### 2.1 What counts

An occurrence contributes to this feature **iff** `status == done`. It is
attributed to `completed_by`.

- `pending`, `skipped`, `missed` are excluded from every query (§0 rule 1).
- **Deleted chores are included.** `chores.deleted_at IS NOT NULL` is *not*
  filtered here — that filter on every other read path is precisely what made
  the old delete promise hollow (triage T1.2). This is the one screen that
  reads through it.
- **Paused chores are included.** Pausing is a vacation, not a retraction.
- **Soft-deleted members are still resolved.** The `members` joins in this
  feature are DISPLAY joins and must NOT filter `deleted_at` — the same rule
  `ChoreRepository.watchClosedOnDate` documents, so past attribution stays
  readable (`docs/feedback/2026-08-01-ux-audit.md` A1).
- A `done` row with a NULL `completed_by` (possible via sync or an imported
  archive; the local `completeOccurrence` path always sets it) is counted in
  the household total and rendered as one trailing **"Someone else"** bucket,
  shown only when its count is > 0.

### 2.2 The share window

- **30 days, inclusive of today**: `windowEnd = today`,
  `windowStart = today.addDays(-29)`, where `today =
  PlainDate.fromDateTime(clock.now())` — the app's injected clock, computed once
  per read.
- **Clamped to the household's own start**: if the household's `created_at`
  (converted to a local calendar date) is after that `windowStart`, the window
  starts there instead, and the UI says so (§4.2). A household two days old then
  reports honestly on two days rather than showing a near-empty 30-day view.
- `closed_on` is a `yyyy-mm-dd` TEXT column, so ISO strings compare
  lexicographically and the window is a plain string range — no date parsing in
  SQL.

### 2.3 Query shape and scale

Occurrence history grows unbounded by design (`lib/data/db/tables.dart`:
"history rows are otherwise retained forever"). Arithmetic at family scale: 4
members, ~20 recurring chores, roughly 15 occurrences closed per day → ~5.5k
rows/year, ~27k after five years. That is small for SQLite, but two properties
still matter:

1. **Aggregate in SQL, never in Dart.** Every query here is a `GROUP BY`
   returning at most (members) or (chores) rows — dozens. Materializing 27k
   joined rows into Dart objects to count them would be the one genuinely bad
   implementation.
2. **The windowed query gets an index.** `chore_occurrences` has
   `(chore_id, status)` and `(status, due_date)`; neither serves a `closed_on`
   range. Schema v10 adds
   `chore_occurrences_status_closed_on_idx (status, closed_on)`.
3. **Reads are one-shot `Future`s, not drift streams.** This screen is a
   snapshot of the past. A `.watch()` here would re-run a whole-history
   aggregate on every unrelated occurrence write for the rest of the session.
   Providers are `autoDispose`, so re-entering the screen re-queries; there is
   no live-update requirement and no refresh control.

## 3. What the overview screen shows

### 3.1 The household share card (`stats.share`)

Rendered only when the window's total is > 0 **and** the share has ≥ 2 entries.
With exactly one entry (a single-member household), the card is replaced by a
one-line total (`stats.total`), because a bar reading 100% is noise.

- A window label: "In the last 30 days", or "Since you started, {date}" when
  §2.2's clamp applied.
- The total: "{n} chores done" (ICU plural).
- One proportional horizontal bar, 12dp tall, radius 6, segments in each
  member's `categoryTone` color, in roster order. Members with 0 contribute no
  segment.
- One row per entry: `MemberAvatar` + name + "{count} · {percent}".
  `percent` is formatted with `NumberFormat.percentPattern(localeName)`.
- **Entries** = every member currently in the roster (creation order, count
  included even when 0 — hiding a zero would make the card dishonest), **plus**
  any soft-deleted member with a count > 0 in the window (appended, in creation
  order), **plus** the "Someone else" bucket last when > 0.
- Accessibility: the card carries one `Semantics` label built by joining the
  visible sentences with ". "; every descendant text node is excluded, exactly
  as `ChoreProgressCard` does.

### 3.2 The per-chore list

Every chore of the household with **at least one `done` occurrence ever**,
ordered alphabetically by title — never by count (§0 rule 4).

Each row (`stats.chore.<choreId>`) shows the chore title, its category badge
when it has one, and one metadata line: **"{n} times · last {date}"**, both
**all-time**, not windowed. Rationale: the window belongs to the fairness
question. "How often does this get done, and when last?" is a property of the
chore, and windowing it would hide long-dormant and deleted chores from a screen
whose D2 obligation is that nothing is hidden.

Tapping a row opens §5.

### 3.3 Deleted chores (`stats.deleted`)

Deleted chores are **not** interleaved into §3.2. They go into one collapsed
`ExpansionTile` headed "Deleted chores ({n})", below the main list, shown only
when at least one deleted chore has history. Same row rendering, same tap
target. This section is the direct, findable answer to "where did my deleted
chore go", which is the whole point of D2.

### 3.4 Empty state (`stats.empty`)

When the household has no `done` occurrence at all: the theme's empty-state
pattern (`docs/specs/theme-v2.md` §4.1 item 6) — a 76dp `primaryContainer` tile
with a `primaryOutline` border and a `history_outlined` glyph, a `titleLarge`
headline, then one `bodyMedium` line. Copy teaches rather than apologizes
(`design-language.md` interaction rule 5): "No completed chores yet" / "As your
household ticks chores off, this is where you'll see who did what."

### 3.5 Error state (`stats.error.retry`)

Message + an `OutlinedButton` retry that invalidates the provider — the same
shape as `ManageMembersScreen`'s `_ErrorState`.

## 4. Copy rules

- All strings through gen_l10n, EN template + DE **du**-form; counts use ICU
  plurals in both.
- Dates are formatted with `intl` against `Localizations.localeOf(context)` —
  never a hand-built date string, never a hardcoded month or weekday name.
- Percentages via `NumberFormat.percentPattern(localeName)`.

## 5. The per-chore log (`ChoreHistoryScreen`)

One chore's completions, **all-time**, newest first.

- App bar title = the chore title.
- When the chore is deleted, a `bodySmall` notice under the app bar
  (`stats.history.deletedNotice`): "This chore was deleted. Its history is kept
  here." — the sentence that makes the restored delete-dialog copy true.
- A header line: "{n} chores done" (the chore's all-time `done` total).
- Rows (`stats.history.row.<occurrenceId>`): locale-formatted `closed_on` date,
  `MemberAvatar`, member name — or the "Someone else" label when
  `completed_by` is NULL.
- Ordered by `closed_on` descending, then `updated_at` descending (the same
  tiebreak `ChoreRepository.latestClosedOccurrence` uses).
- **Capped at 50 rows.** When the total exceeds the cap, a trailing
  `bodySmall` line says "Showing the {shown} most recent of {total}". A cap plus
  an honest total keeps the promise without rendering a wall of entries —
  `DESIGN.md` §1 already rejected browsable history walls for shopping ("no
  walls of 900 historic entries").
- Read-only. Nothing on this screen mutates anything.

## 6. The restored delete copy (D2 step 2)

`choresDeleteDialogBody` becomes, in EN:

> This removes '{choreTitle}' from your lists. Its history is kept — you'll
> find it under Settings › Chore history.

and the DE du-form equivalent. The ARB description's `TODO(F19)` is removed and
replaced with a pointer to this spec. **This change may not be made before §3.3
and §5 are working**, per D2's ordering: shipping the strong copy ahead of the
mechanism would be deliberately keeping a promise known to be empty.

## 7. Non-goals (permanent, not deferred)

- **A per-member view.** "Everything Anna did" is the leaderboard direction
  (§0 rule 5).
- **Streaks, badges, awards, points, trends, period-over-period comparison.**
- **Skipped/missed counts** anywhere in this feature (§0 rule 1). Revisit only
  with household evidence, and only in the unattributed per-chore form.
- **Editing history.** Read-only. Reopening a completion stays where it is
  (the chores list's Done-today section, LIFO-restricted per
  `docs/specs/occurrence-lifecycle.md`).
- **Following the chores list's member/category filter.** Separate screen,
  separate scope.
- **A sync/freshness indicator.** This screen reads local data like every other
  screen; a device that has not pulled shows a partial picture, which is a
  property of the app, not of this feature.

## 8. Testing requirements

- **Repository**, over a real in-memory `AppDatabase` with counter ids and
  literal timestamps: window boundary inclusive at both ends; `skipped`/
  `missed`/`pending` excluded; deleted chores included; paused chores included;
  soft-deleted members still resolved; NULL `completed_by` bucketed; another
  household's rows never leak in.
- **Service**: the window clamp when the household is younger than 30 days; no
  clamp when older; the active/deleted split; roster order preserved; a
  zero-count roster member still present; a departed member with a count still
  present; the "Someone else" bucket last.
- **Widget**, integration-style through the real query path (`testChoreApp`,
  real in-memory DB, fixed clock, no mocks): empty state; single-member total
  line instead of the card; multi-member card; per-chore row copy; deleted
  section presence and contents; navigation into the log; the deleted notice;
  the 50-row cap line.
- **E2E** (Maestro): complete a chore → open Chore history from Settings → see
  it → delete the chore → find it under Deleted chores. This flow is the
  executable form of the D2 promise.

Done criteria: `dart format` clean; `flutter analyze --fatal-infos
--fatal-warnings` clean; `flutter test` fully green; all 12+ Maestro flows green
in CI; visual QA per `design-language.md` (light + dark, text scale 1.0 and 2.0,
no overflow).
````

- [ ] **Step 2: Commit**

```bash
git add docs/specs/stats.md
git commit -m "docs: spec the chore-history view (G-1 / F19, triage D2)"
```

---

## Task 2: Schema v10 — the `(status, closed_on)` index

**Files:**
- Modify: `lib/data/db/tables.dart` (the `@TableIndex` block above `ChoreOccurrences`, currently lines 375–383)
- Modify: `lib/data/db/app_database.dart:56` (`schemaVersion`) and the `onUpgrade` body
- Modify: `lib/data/db/app_database.g.dart` (regenerated)
- Test: `test/data/db/schema_migration_test.dart`

**Interfaces:**
- Produces: `AppDatabase.schemaVersion == 10` and a generated
  `Index choreOccurrencesStatusClosedOnIdx` on the database class.

- [ ] **Step 1: Write the failing migration test**

Append to `test/data/db/schema_migration_test.dart`, inside `main()`:

```dart
  test(
    'schemaVersion 9 -> 10 upgrade creates the (status, closed_on) index',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chore_app_migration_test',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final file = File('${dir.path}/test.sqlite');

      // Materialize the current schema against a real file, then simulate a
      // pre-v10 install by dropping the index this migration adds and
      // rewinding `user_version` -- the same collateral-drop pattern the
      // column migrations above use.
      final seed = AppDatabase(NativeDatabase(file));
      await seed.customStatement('SELECT 1');
      await seed.customStatement(
        'DROP INDEX IF EXISTS chore_occurrences_status_closed_on_idx',
      );
      await seed.customStatement('PRAGMA user_version = 9');
      await seed.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      final rows = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'chore_occurrences_status_closed_on_idx'",
          )
          .get();
      expect(rows, hasLength(1));
      await upgraded.close();
    },
  );
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/db/schema_migration_test.dart`
Expected: FAIL — `Expected: an object with length of <1> / Actual: []` (the
index does not exist yet, and nothing recreates it).

- [ ] **Step 3: Declare the index**

In `lib/data/db/tables.dart`, add a third `@TableIndex` above
`class ChoreOccurrences` (keep the two existing ones untouched):

```dart
@TableIndex(
  name: 'chore_occurrences_status_closed_on_idx',
  columns: {#status, #closedOn},
)
```

Extend the class's existing doc comment with:

```dart
/// The `(status, closed_on)` index (schema v10, spec `docs/specs/stats.md`
/// §2.3) serves the chore-history window query -- `status = 'done' AND
/// closed_on BETWEEN ? AND ?`. Neither existing index covers it:
/// `(chore_id, status)` leads with the wrong column and `(status, due_date)`
/// ranges over the wrong date. `closed_on` is `yyyy-mm-dd` TEXT, so the range
/// is a lexicographic scan.
```

- [ ] **Step 4: Bump the schema version and add the migration branch**

In `lib/data/db/app_database.dart`, change line 56 to:

```dart
  int get schemaVersion => 10;
```

and append this branch inside `onUpgrade`, immediately after the closing brace
of the existing `if (from < 9) { ... }` block:

```dart
      if (from < 10) {
        // v9 -> v10 (spec `docs/specs/stats.md` §2.3): adds the
        // `(status, closed_on)` index on `chore_occurrences`, which serves
        // the chore-history window aggregate. Index-only: no column is
        // added and no row is rewritten, so this is safe to run on any
        // install regardless of which branch above ran.
        await migrator.createIndex(choreOccurrencesStatusClosedOnIdx);
      }
```

- [ ] **Step 5: Regenerate drift's code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: succeeds; `lib/data/db/app_database.g.dart` now contains
`late final Index choreOccurrencesStatusClosedOnIdx = Index(` with the
`CREATE INDEX chore_occurrences_status_closed_on_idx ON chore_occurrences
(status, closed_on)` statement.

- [ ] **Step 6: Run the migration suite**

Run: `flutter test test/data/db/schema_migration_test.dart`
Expected: PASS, all tests including the pre-existing v1→, v2→, v3→ ones (their
"upgrade to 9" wording is now "upgrade to 10" in effect — if any of them asserts
a literal `9`, update the literal to `10`; do not change what they assert).

- [ ] **Step 7: Commit**

```bash
git add lib/data/db/tables.dart lib/data/db/app_database.dart \
        lib/data/db/app_database.g.dart test/data/db/schema_migration_test.dart
git commit -m "feat(db): schema v10 -- index chore_occurrences (status, closed_on)"
```

---

## Task 3: `StatsRepository` — the three queries

**Files:**
- Create: `lib/data/repositories/stats_repository.dart`
- Test: `test/data/repositories/stats_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (Task 2's v10 schema), `PlainDate`.
- Produces:
  - `class MemberDoneCount { final String? memberId; final int doneCount; }`
  - `class ChoreDoneRollup { final Chore chore; final Category? category; final int doneAllTime; final PlainDate lastDoneOn; }`
  - `class ChoreCompletion { final ChoreOccurrence occurrence; final Member? completedByMember; }`
  - `class StatsRepository`, constructed as `StatsRepository(db)`, with:
    - `Future<List<MemberDoneCount>> doneCountsByMember(String householdId, {required PlainDate windowStart, required PlainDate windowEnd})`
    - `Future<List<ChoreDoneRollup>> choreRollups(String householdId)`
    - `Future<int> doneCountForChore(String choreId)`
    - `Future<List<ChoreCompletion>> recentCompletions(String choreId, {int limit = 50})`

- [ ] **Step 1: Write the failing tests**

Create `test/data/repositories/stats_repository_test.dart`:

```dart
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds a household row and returns its id.
Future<String> _household(AppDatabase db, String id) async {
  await db
      .into(db.households)
      .insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  return id;
}

Future<String> _member(
  AppDatabase db,
  String id,
  String householdId, {
  String? deletedAt,
}) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          householdId: householdId,
          name: id,
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deletedAt),
        ),
      );
  return id;
}

Future<String> _chore(
  AppDatabase db,
  String id,
  String householdId, {
  String title = 'Chore',
  String? deletedAt,
  String? pausedAt,
}) async {
  await db
      .into(db.chores)
      .insert(
        ChoresCompanion.insert(
          id: id,
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deletedAt),
          pausedAt: Value(pausedAt),
        ),
      );
  return id;
}

Future<void> _occurrence(
  AppDatabase db,
  String id,
  String choreId, {
  required OccurrenceStatus status,
  String? closedOn,
  String? completedBy,
  String updatedAt = '2026-01-01T00:00:00.000Z',
}) async {
  await db
      .into(db.choreOccurrences)
      .insert(
        ChoreOccurrencesCompanion.insert(
          id: id,
          choreId: choreId,
          dueDate: PlainDate(2026, 1, 1),
          status: Value(status),
          completedBy: Value(completedBy),
          closedOn: Value(closedOn == null ? null : PlainDate.parse(closedOn)),
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: updatedAt,
        ),
      );
}

void main() {
  late AppDatabase db;
  late StatsRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = StatsRepository(db);
  });

  tearDown(() => db.close());

  test(
    'doneCountsByMember counts only done rows, inclusive at both window '
    'edges, and ignores skipped/missed/pending',
    () async {
      final hh = await _household(db, 'hh');
      final anna = await _member(db, 'anna', hh);
      final chore = await _chore(db, 'c1', hh);

      await _occurrence(db, 'o1', chore,
          status: OccurrenceStatus.done,
          closedOn: '2026-07-13', completedBy: anna); // window start
      await _occurrence(db, 'o2', chore,
          status: OccurrenceStatus.done,
          closedOn: '2026-08-11', completedBy: anna); // window end
      await _occurrence(db, 'o3', chore,
          status: OccurrenceStatus.done,
          closedOn: '2026-07-12', completedBy: anna); // before window
      await _occurrence(db, 'o4', chore,
          status: OccurrenceStatus.skipped,
          closedOn: '2026-08-01', completedBy: anna);
      await _occurrence(db, 'o5', chore,
          status: OccurrenceStatus.missed, closedOn: '2026-08-02');
      await _occurrence(db, 'o6', chore, status: OccurrenceStatus.pending);

      final counts = await repo.doneCountsByMember(
        hh,
        windowStart: PlainDate(2026, 7, 13),
        windowEnd: PlainDate(2026, 8, 11),
      );

      expect(counts, hasLength(1));
      expect(counts.single.memberId, 'anna');
      expect(counts.single.doneCount, 2);
    },
  );

  test(
    'doneCountsByMember buckets a NULL completed_by separately and never '
    'leaks another household',
    () async {
      final hh = await _household(db, 'hh');
      final other = await _household(db, 'other');
      final anna = await _member(db, 'anna', hh);
      final chore = await _chore(db, 'c1', hh);
      final otherChore = await _chore(db, 'c2', other);

      await _occurrence(db, 'o1', chore,
          status: OccurrenceStatus.done,
          closedOn: '2026-08-01', completedBy: anna);
      await _occurrence(db, 'o2', chore,
          status: OccurrenceStatus.done, closedOn: '2026-08-02');
      await _occurrence(db, 'o3', otherChore,
          status: OccurrenceStatus.done, closedOn: '2026-08-03');

      final counts = await repo.doneCountsByMember(
        hh,
        windowStart: PlainDate(2026, 7, 13),
        windowEnd: PlainDate(2026, 8, 11),
      );

      expect(counts.map((c) => c.memberId), containsAll(<String?>[null, 'anna']));
      expect(counts.length, 2);
      expect(
        counts.firstWhere((c) => c.memberId == null).doneCount,
        1,
      );
    },
  );

  test(
    'choreRollups includes deleted and paused chores, excludes chores with '
    'no done history, and reports all-time count plus last done date',
    () async {
      final hh = await _household(db, 'hh');
      await _chore(db, 'live', hh, title: 'Bathroom');
      await _chore(db, 'gone', hh,
          title: 'Attic', deletedAt: '2026-08-05T00:00:00.000Z');
      await _chore(db, 'rest', hh,
          title: 'Garden', pausedAt: '2026-08-05T00:00:00.000Z');
      await _chore(db, 'never', hh, title: 'Zebra');

      await _occurrence(db, 'o1', 'live',
          status: OccurrenceStatus.done, closedOn: '2026-06-01');
      await _occurrence(db, 'o2', 'live',
          status: OccurrenceStatus.done, closedOn: '2026-08-01');
      await _occurrence(db, 'o3', 'gone',
          status: OccurrenceStatus.done, closedOn: '2026-05-01');
      await _occurrence(db, 'o4', 'rest',
          status: OccurrenceStatus.done, closedOn: '2026-07-01');
      await _occurrence(db, 'o5', 'never', status: OccurrenceStatus.pending);

      final rollups = await repo.choreRollups(hh);

      expect(rollups.map((r) => r.chore.title), ['Attic', 'Bathroom', 'Garden']);
      final bathroom = rollups.firstWhere((r) => r.chore.id == 'live');
      expect(bathroom.doneAllTime, 2);
      expect(bathroom.lastDoneOn, PlainDate(2026, 8, 1));
    },
  );

  test(
    'recentCompletions returns newest first, resolves a soft-deleted member, '
    'and honours the limit; doneCountForChore reports the untruncated total',
    () async {
      final hh = await _household(db, 'hh');
      final ghost = await _member(db, 'ghost', hh,
          deletedAt: '2026-08-06T00:00:00.000Z');
      await _chore(db, 'c1', hh);

      await _occurrence(db, 'o1', 'c1',
          status: OccurrenceStatus.done,
          closedOn: '2026-08-01', completedBy: ghost);
      await _occurrence(db, 'o2', 'c1',
          status: OccurrenceStatus.done,
          closedOn: '2026-08-03', completedBy: ghost);
      await _occurrence(db, 'o3', 'c1',
          status: OccurrenceStatus.skipped, closedOn: '2026-08-04');

      expect(await repo.doneCountForChore('c1'), 2);

      final recent = await repo.recentCompletions('c1', limit: 1);
      expect(recent, hasLength(1));
      expect(recent.single.occurrence.id, 'o2');
      expect(recent.single.completedByMember?.name, 'ghost');
    },
  );
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/data/repositories/stats_repository_test.dart`
Expected: FAIL at compile — `Target of URI doesn't exist:
'package:chore_app/data/repositories/stats_repository.dart'`.

- [ ] **Step 3: Implement the repository**

Create `lib/data/repositories/stats_repository.dart`:

```dart
/// Read-only aggregate queries backing the chore-history screens (spec
/// `docs/specs/stats.md`).
///
/// Deliberately separate from `ChoreRepository`: nothing here writes, and
/// every method aggregates in SQL rather than materializing history rows
/// (spec §2.3 -- occurrence history grows unbounded by design).
///
/// The one rule that governs all of it (spec §2.1): an occurrence counts
/// **iff** `status == done`. `skipped` and `missed` are excluded everywhere,
/// deliberately -- see the spec's §0 for why that is a product rule and not
/// an implementation detail.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:drift/drift.dart';

/// How many chores one member completed inside a window.
class MemberDoneCount {
  /// Creates a per-member done count.
  const MemberDoneCount({required this.memberId, required this.doneCount});

  /// The completing member's id, or `null` for the unattributed bucket (a
  /// `done` row whose `completed_by` is NULL -- possible via sync or an
  /// imported archive; spec §2.1).
  final String? memberId;

  /// The number of `done` occurrences credited to [memberId] in the window.
  final int doneCount;
}

/// One chore's all-time completion rollup.
class ChoreDoneRollup {
  /// Creates a rollup for [chore].
  const ChoreDoneRollup({
    required this.chore,
    required this.doneAllTime,
    required this.lastDoneOn,
    this.category,
  });

  /// The chore itself. May be soft-deleted and/or paused -- both are
  /// deliberately included (spec §2.1).
  final Chore chore;

  /// The chore's category, or `null` if uncategorized.
  final Category? category;

  /// How many times this chore has ever been completed. Always >= 1: chores
  /// with no completions are not returned at all.
  final int doneAllTime;

  /// The most recent date this chore was completed on.
  final PlainDate lastDoneOn;
}

/// One completion of a chore, with the member who did it resolved.
class ChoreCompletion {
  /// Creates a completion record.
  const ChoreCompletion({required this.occurrence, this.completedByMember});

  /// The `done` occurrence row.
  final ChoreOccurrence occurrence;

  /// The completing member, or `null` when unattributed. Resolved through a
  /// DISPLAY join that does NOT filter `deleted_at`, so a since-removed
  /// member is still named (spec §2.1).
  final Member? completedByMember;
}

/// Read-only reporting queries over `chore_occurrences` (spec
/// `docs/specs/stats.md`).
class StatsRepository {
  /// Creates a repository backed by [db].
  StatsRepository(this.db);

  /// The database this repository reads from. It never writes.
  final AppDatabase db;

  /// Counts `done` occurrences in [householdId] closed between
  /// [windowStart] and [windowEnd] (both inclusive), grouped by the
  /// completing member.
  ///
  /// `closed_on` is a `yyyy-mm-dd` TEXT column, so the window is a plain
  /// lexicographic string range -- no date parsing in SQL (spec §2.2).
  /// Deleted and paused chores are included on purpose (spec §2.1).
  Future<List<MemberDoneCount>> doneCountsByMember(
    String householdId, {
    required PlainDate windowStart,
    required PlainDate windowEnd,
  }) async {
    final doneCount = db.choreOccurrences.id.count();
    final query = db.selectOnly(db.choreOccurrences)
      ..addColumns([db.choreOccurrences.completedBy, doneCount])
      ..join([
        innerJoin(
          db.chores,
          db.chores.id.equalsExp(db.choreOccurrences.choreId),
          useColumns: false,
        ),
      ])
      ..where(
        db.chores.householdId.equals(householdId) &
            db.choreOccurrences.status.equalsValue(OccurrenceStatus.done) &
            db.choreOccurrences.closedOn.isBiggerOrEqualValue(
              windowStart.toIso8601(),
            ) &
            db.choreOccurrences.closedOn.isSmallerOrEqualValue(
              windowEnd.toIso8601(),
            ),
      )
      ..groupBy([db.choreOccurrences.completedBy]);

    final rows = await query.get();
    return [
      for (final row in rows)
        MemberDoneCount(
          memberId: row.read(db.choreOccurrences.completedBy),
          doneCount: row.read(doneCount) ?? 0,
        ),
    ];
  }

  /// Every chore of [householdId] with at least one `done` occurrence ever,
  /// with its all-time completion count and last completion date, ordered
  /// alphabetically by title (spec §3.2 -- never by count).
  ///
  /// Two queries rather than one: the aggregate returns at most one row per
  /// chore (dozens), and the follow-up fetch of those chores + categories is
  /// an ordinary join. This avoids relying on SQLite's bare-column-with-max
  /// behaviour, which is correct but non-obvious.
  Future<List<ChoreDoneRollup>> choreRollups(String householdId) async {
    final doneCount = db.choreOccurrences.id.count();
    final lastDone = db.choreOccurrences.closedOn.max();
    final aggregate = db.selectOnly(db.choreOccurrences)
      ..addColumns([db.choreOccurrences.choreId, doneCount, lastDone])
      ..join([
        innerJoin(
          db.chores,
          db.chores.id.equalsExp(db.choreOccurrences.choreId),
          useColumns: false,
        ),
      ])
      ..where(
        db.chores.householdId.equals(householdId) &
            db.choreOccurrences.status.equalsValue(OccurrenceStatus.done),
      )
      ..groupBy([db.choreOccurrences.choreId]);

    final aggregateRows = await aggregate.get();
    if (aggregateRows.isEmpty) {
      return const [];
    }

    final counts = <String, int>{};
    final lastDates = <String, PlainDate>{};
    for (final row in aggregateRows) {
      final choreId = row.read(db.choreOccurrences.choreId)!;
      counts[choreId] = row.read(doneCount) ?? 0;
      final iso = row.read(lastDone);
      if (iso != null) {
        lastDates[choreId] = PlainDate.parse(iso);
      }
    }

    final detail =
        db.select(db.chores).join([
            leftOuterJoin(
              db.categories,
              db.categories.id.equalsExp(db.chores.categoryId),
            ),
          ])
          ..where(db.chores.id.isIn(counts.keys))
          ..orderBy([OrderingTerm(expression: db.chores.title)]);

    final detailRows = await detail.get();
    return [
      for (final row in detailRows)
        if (lastDates[row.readTable(db.chores).id] case final PlainDate last)
          ChoreDoneRollup(
            chore: row.readTable(db.chores),
            category: row.readTableOrNull(db.categories),
            doneAllTime: counts[row.readTable(db.chores).id] ?? 0,
            lastDoneOn: last,
          ),
    ];
  }

  /// The all-time number of `done` occurrences of [choreId].
  Future<int> doneCountForChore(String choreId) async {
    final doneCount = db.choreOccurrences.id.count();
    final query = db.selectOnly(db.choreOccurrences)
      ..addColumns([doneCount])
      ..where(
        db.choreOccurrences.choreId.equals(choreId) &
            db.choreOccurrences.status.equalsValue(OccurrenceStatus.done),
      );
    final row = await query.getSingle();
    return row.read(doneCount) ?? 0;
  }

  /// The [limit] most recent `done` occurrences of [choreId], newest first
  /// (`closed_on` desc, then `updated_at` desc -- the same tiebreak
  /// `ChoreRepository.latestClosedOccurrence` uses).
  ///
  /// The `members` join is a DISPLAY join and deliberately does NOT filter
  /// `deleted_at`: a removed member's past work stays attributed (spec
  /// §2.1).
  Future<List<ChoreCompletion>> recentCompletions(
    String choreId, {
    int limit = 50,
  }) async {
    final query =
        db.select(db.choreOccurrences).join([
            leftOuterJoin(
              db.members,
              db.members.id.equalsExp(db.choreOccurrences.completedBy),
            ),
          ])
          ..where(
            db.choreOccurrences.choreId.equals(choreId) &
                db.choreOccurrences.status.equalsValue(OccurrenceStatus.done),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.choreOccurrences.closedOn,
              mode: OrderingMode.desc,
            ),
            OrderingTerm(
              expression: db.choreOccurrences.updatedAt,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit);

    final rows = await query.get();
    return [
      for (final row in rows)
        ChoreCompletion(
          occurrence: row.readTable(db.choreOccurrences),
          completedByMember: row.readTableOrNull(db.members),
        ),
    ];
  }
}
```

- [ ] **Step 4: Run the tests until green**

Run: `flutter test test/data/repositories/stats_repository_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze and format**

Run: `dart format lib/data/repositories/stats_repository.dart test/data/repositories/stats_repository_test.dart && flutter analyze --fatal-infos --fatal-warnings`
Expected: no changes reported by format after the first run; analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/stats_repository.dart \
        test/data/repositories/stats_repository_test.dart
git commit -m "feat(data): StatsRepository -- done-only aggregates for chore history"
```

---

## Task 4: `StatsService` — window math, clamp, roster-order assembly

**Files:**
- Create: `lib/application/stats_service.dart`
- Test: `test/application/stats_service_test.dart`

**Interfaces:**
- Consumes: `StatsRepository` (Task 3), `AppDatabase`, `package:clock`.
- Produces:
  - `const int statsWindowDays = 30;`
  - `class MemberShare { final Member? member; final int doneCount; }`
  - `class StatsOverview { final PlainDate windowStart; final PlainDate windowEnd; final bool windowClampedToHouseholdStart; final List<MemberShare> shares; final int totalDone; final List<ChoreDoneRollup> activeChores; final List<ChoreDoneRollup> deletedChores; }`
  - `class StatsService`, constructed as
    `StatsService({required AppDatabase database, required StatsRepository stats, Clock clock = const Clock()})`, with
    `Future<StatsOverview> overview(String householdId)`.

- [ ] **Step 1: Write the failing tests**

Create `test/application/stats_service_test.dart`:

```dart
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _household(
  AppDatabase db,
  String id, {
  required String createdAt,
}) async {
  await db.into(db.households).insert(
        HouseholdsCompanion.insert(
          id: id,
          name: 'H',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}

Future<void> _member(
  AppDatabase db,
  String id,
  String householdId, {
  required String createdAt,
  String? deletedAt,
}) async {
  await db.into(db.members).insert(
        MembersCompanion.insert(
          id: id,
          householdId: householdId,
          name: id,
          color: 0xFF6D9F71,
          role: MemberRole.member,
          createdAt: createdAt,
          updatedAt: createdAt,
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<void> _chore(
  AppDatabase db,
  String id,
  String householdId, {
  required String title,
  String? deletedAt,
}) async {
  await db.into(db.chores).insert(
        ChoresCompanion.insert(
          id: id,
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<void> _done(
  AppDatabase db,
  String id,
  String choreId, {
  required String closedOn,
  String? completedBy,
}) async {
  await db.into(db.choreOccurrences).insert(
        ChoreOccurrencesCompanion.insert(
          id: id,
          choreId: choreId,
          dueDate: PlainDate.parse(closedOn),
          status: const Value(OccurrenceStatus.done),
          completedBy: Value(completedBy),
          closedOn: Value(PlainDate.parse(closedOn)),
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
}

void main() {
  late AppDatabase db;

  StatsService serviceAt(DateTime now) => StatsService(
        database: db,
        stats: StatsRepository(db),
        clock: Clock.fixed(now),
      );

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('an old household gets the full 30-day window, unclamped', () async {
    await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
    final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

    expect(overview.windowStart, PlainDate(2026, 7, 13));
    expect(overview.windowEnd, PlainDate(2026, 8, 11));
    expect(overview.windowClampedToHouseholdStart, isFalse);
  });

  test(
    'a household younger than the window is clamped to its own start date',
    () async {
      await _household(db, 'hh', createdAt: '2026-08-09T10:00:00.000Z');
      final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

      expect(overview.windowStart, PlainDate(2026, 8, 9));
      expect(overview.windowClampedToHouseholdStart, isTrue);
    },
  );

  test(
    'shares are in roster order, keep zero-count members, append a departed '
    'contributor, and put the unattributed bucket last',
    () async {
      await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
      await _member(db, 'anna', 'hh', createdAt: '2026-01-01T10:00:00.000Z');
      await _member(db, 'ben', 'hh', createdAt: '2026-01-02T10:00:00.000Z');
      await _member(db, 'cara', 'hh',
          createdAt: '2026-01-03T10:00:00.000Z',
          deletedAt: '2026-08-01T10:00:00.000Z');
      await _chore(db, 'c1', 'hh', title: 'Bathroom');

      await _done(db, 'o1', 'c1', closedOn: '2026-08-01', completedBy: 'anna');
      await _done(db, 'o2', 'c1', closedOn: '2026-08-02', completedBy: 'cara');
      await _done(db, 'o3', 'c1', closedOn: '2026-08-03');

      final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

      expect(
        overview.shares.map((s) => s.member?.id).toList(),
        ['anna', 'ben', 'cara', null],
      );
      expect(overview.shares.map((s) => s.doneCount).toList(), [1, 0, 1, 1]);
      expect(overview.totalDone, 3);
    },
  );

  test('chores split into active and deleted, each alphabetical', () async {
    await _household(db, 'hh', createdAt: '2026-01-01T10:00:00.000Z');
    await _chore(db, 'a', 'hh', title: 'Bathroom');
    await _chore(db, 'b', 'hh', title: 'Attic',
        deletedAt: '2026-08-05T00:00:00.000Z');
    await _chore(db, 'c', 'hh', title: 'Garden');

    await _done(db, 'o1', 'a', closedOn: '2026-08-01');
    await _done(db, 'o2', 'b', closedOn: '2026-05-01');
    await _done(db, 'o3', 'c', closedOn: '2026-08-02');

    final overview = await serviceAt(DateTime(2026, 8, 11, 9)).overview('hh');

    expect(overview.activeChores.map((r) => r.chore.title), ['Bathroom', 'Garden']);
    expect(overview.deletedChores.map((r) => r.chore.title), ['Attic']);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/application/stats_service_test.dart`
Expected: FAIL at compile — `Target of URI doesn't exist:
'package:chore_app/application/stats_service.dart'`.

- [ ] **Step 3: Implement the service**

Create `lib/application/stats_service.dart`:

```dart
/// Assembles the chore-history overview (spec `docs/specs/stats.md` §2.2,
/// §3.1, §3.3) from [StatsRepository]'s raw aggregates: the share window and
/// its household-start clamp, the roster-order member share, and the
/// active/deleted chore split.
///
/// Application layer, like `ChoreService`: it may import the domain, the
/// data layer and `package:clock` -- never Flutter.
library;

import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

/// The length of the fairness window, in days, inclusive of today (spec
/// §2.2). Bounded on purpose: an all-time total would be a standing score.
const int statsWindowDays = 30;

/// One entry of the household share: a member (or the unattributed bucket)
/// and how many chores they completed in the window.
class MemberShare {
  /// Creates a share entry.
  const MemberShare({required this.member, required this.doneCount});

  /// The member, or `null` for the unattributed "Someone else" bucket.
  final Member? member;

  /// Completions credited to [member] in the window. May be 0 for a current
  /// roster member -- hiding a zero would make the card dishonest.
  final int doneCount;
}

/// Everything the chore-history overview screen renders.
class StatsOverview {
  /// Creates an overview.
  const StatsOverview({
    required this.windowStart,
    required this.windowEnd,
    required this.windowClampedToHouseholdStart,
    required this.shares,
    required this.totalDone,
    required this.activeChores,
    required this.deletedChores,
  });

  /// First day of the share window, inclusive.
  final PlainDate windowStart;

  /// Last day of the share window, inclusive (always today).
  final PlainDate windowEnd;

  /// Whether [windowStart] was moved forward because the household is
  /// younger than [statsWindowDays] -- the UI says so instead of implying a
  /// full month of data (spec §3.1).
  final bool windowClampedToHouseholdStart;

  /// Share entries in household roster order (member creation order), with
  /// any departed contributor appended and the unattributed bucket last
  /// (spec §3.1). NEVER sorted by count.
  final List<MemberShare> shares;

  /// Total completions in the window, across every entry in [shares].
  final int totalDone;

  /// Chores with completion history that are not deleted, alphabetical.
  final List<ChoreDoneRollup> activeChores;

  /// Soft-deleted chores with completion history, alphabetical. These are
  /// the reason this screen exists (triage D2).
  final List<ChoreDoneRollup> deletedChores;
}

/// Builds a [StatsOverview] for a household.
class StatsService {
  /// Creates a service reading through [stats] and [database].
  StatsService({
    required this.database,
    required this.stats,
    this.clock = const Clock(),
  });

  /// Used for the household row (its `created_at` drives the window clamp)
  /// and the member roster.
  final AppDatabase database;

  /// The aggregate queries.
  final StatsRepository stats;

  /// The app's injected clock; "today" is derived from it exactly once per
  /// [overview] call.
  final Clock clock;

  /// Reads everything the overview screen needs for [householdId].
  Future<StatsOverview> overview(String householdId) async {
    final today = PlainDate.fromDateTime(clock.now());
    final naturalStart = today.addDays(-(statsWindowDays - 1));

    final household = await (database.select(
      database.households,
    )..where((tbl) => tbl.id.equals(householdId))).getSingle();
    final householdStart = PlainDate.fromDateTime(
      DateTime.parse(household.createdAt).toLocal(),
    );
    final clamped = householdStart.isAfter(naturalStart);
    final windowStart = clamped ? householdStart : naturalStart;

    final counts = await stats.doneCountsByMember(
      householdId,
      windowStart: windowStart,
      windowEnd: today,
    );
    final countById = <String?, int>{
      for (final count in counts) count.memberId: count.doneCount,
    };

    // Roster order = member creation order, and deliberately unfiltered on
    // `deleted_at`: a member who has since left still shows the work they
    // did (spec §2.1). Current members appear even with a count of 0;
    // departed ones only when they contributed.
    final roster =
        await (database.select(database.members)
              ..where((tbl) => tbl.householdId.equals(householdId))
              ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt)]))
            .get();

    final shares = <MemberShare>[
      for (final member in roster)
        if (member.deletedAt == null || (countById[member.id] ?? 0) > 0)
          MemberShare(
            member: member,
            doneCount: countById[member.id] ?? 0,
          ),
    ];
    final unattributed = countById[null] ?? 0;
    if (unattributed > 0) {
      shares.add(MemberShare(member: null, doneCount: unattributed));
    }

    final rollups = await stats.choreRollups(householdId);

    return StatsOverview(
      windowStart: windowStart,
      windowEnd: today,
      windowClampedToHouseholdStart: clamped,
      shares: shares,
      totalDone: counts.fold(0, (sum, count) => sum + count.doneCount),
      activeChores: [
        for (final rollup in rollups)
          if (rollup.chore.deletedAt == null) rollup,
      ],
      deletedChores: [
        for (final rollup in rollups)
          if (rollup.chore.deletedAt != null) rollup,
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests until green**

Run: `flutter test test/application/stats_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/application/stats_service.dart test/application/stats_service_test.dart
flutter analyze --fatal-infos --fatal-warnings
git add lib/application/stats_service.dart test/application/stats_service_test.dart
git commit -m "feat(app): StatsService -- 30-day window, clamp, roster-order share"
```

---

## Task 5: Localized strings (EN + DE)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_de.arb`

**Interfaces:**
- Produces: the `l10n.stats*` getters every widget task uses. This task lands
  before the widgets so they compile.

Note: `choresDeleteDialogBody` is **not** touched here — that is Task 12, and
its ordering is a product requirement (spec §6).

- [ ] **Step 1: Add the EN keys**

In `lib/l10n/app_en.arb`, after the `settingsAboutSectionTitle` block (keep the
file's existing grouping style — a blank line between logical clusters):

```json
  "statsSettingsEntry": "Chore history",
  "@statsSettingsEntry": {
    "description": "Settings > Household row opening the chore-history screen. Code namespace is 'stats' but user-visible copy is always 'Chore history' -- see docs/specs/stats.md §1."
  },
  "statsTitle": "Chore history",
  "@statsTitle": {
    "description": "App bar title of the chore-history overview screen."
  },
  "statsWindowLast30Days": "In the last 30 days",
  "@statsWindowLast30Days": {
    "description": "Label above the household share card naming the window the counts cover."
  },
  "statsWindowSinceStart": "Since you started, {date}",
  "@statsWindowSinceStart": {
    "description": "Replaces statsWindowLast30Days when the household is younger than the 30-day window, so a short history is never presented as a full month.",
    "placeholders": {
      "date": {
        "type": "String",
        "example": "9 August"
      }
    }
  },
  "statsTotalDone": "{count, plural, one{1 chore done} other{{count} chores done}}",
  "@statsTotalDone": {
    "description": "Total completions in the share window; also the single-member household's replacement for the whole share card.",
    "placeholders": {
      "count": {
        "type": "int",
        "example": "12"
      }
    }
  },
  "statsShareUnknownMember": "Someone else",
  "@statsShareUnknownMember": {
    "description": "Label for the share bucket of completions whose completed_by is NULL (possible via sync or an imported archive)."
  },
  "statsChoresSectionTitle": "Chores",
  "@statsChoresSectionTitle": {
    "description": "Header above the per-chore list on the chore-history overview."
  },
  "statsChoreTimesDone": "{count, plural, one{Done once} other{Done {count} times}}",
  "@statsChoreTimesDone": {
    "description": "First half of a chore row's metadata line: how many times it has ever been completed (all-time, not windowed).",
    "placeholders": {
      "count": {
        "type": "int",
        "example": "8"
      }
    }
  },
  "statsChoreLastDone": "last {date}",
  "@statsChoreLastDone": {
    "description": "Second half of a chore row's metadata line, joined to statsChoreTimesDone with ' · '.",
    "placeholders": {
      "date": {
        "type": "String",
        "example": "4 Aug"
      }
    }
  },
  "statsDeletedSectionHeader": "{count, plural, one{Deleted chores (1)} other{Deleted chores ({count})}}",
  "@statsDeletedSectionHeader": {
    "description": "Header of the collapsed section holding deleted chores that still have history -- the surface that makes the delete dialog's 'history is kept' promise verifiable (triage D2).",
    "placeholders": {
      "count": {
        "type": "int",
        "example": "2"
      }
    }
  },
  "statsDeletedNotice": "This chore was deleted. Its history is kept here.",
  "@statsDeletedNotice": {
    "description": "Notice at the top of a deleted chore's history screen."
  },
  "statsHistoryTruncated": "Showing the {shown} most recent of {total}",
  "@statsHistoryTruncated": {
    "description": "Footer of a chore's history list when the completion count exceeds the 50-row cap.",
    "placeholders": {
      "shown": {
        "type": "int",
        "example": "50"
      },
      "total": {
        "type": "int",
        "example": "218"
      }
    }
  },
  "statsEmptyTitle": "No completed chores yet",
  "@statsEmptyTitle": {
    "description": "Empty-state headline on the chore-history overview when the household has never completed a chore."
  },
  "statsEmptyBody": "As your household ticks chores off, this is where you'll see who did what.",
  "@statsEmptyBody": {
    "description": "Empty-state body on the chore-history overview -- teaches what will appear rather than apologizing."
  },
  "statsErrorMessage": "Couldn't load the history.",
  "@statsErrorMessage": {
    "description": "Error state on the chore-history overview."
  },
```

- [ ] **Step 2: Add the DE keys (du-form)**

In `lib/l10n/app_de.arb`, in the matching position (the DE file carries values
only, no `@` blocks):

```json
  "statsSettingsEntry": "Aufgaben-Verlauf",
  "statsTitle": "Aufgaben-Verlauf",
  "statsWindowLast30Days": "In den letzten 30 Tagen",
  "statsWindowSinceStart": "Seit deinem Start am {date}",
  "statsTotalDone": "{count, plural, one{1 Aufgabe erledigt} other{{count} Aufgaben erledigt}}",
  "statsShareUnknownMember": "Jemand anderes",
  "statsChoresSectionTitle": "Aufgaben",
  "statsChoreTimesDone": "{count, plural, one{Einmal erledigt} other{{count}-mal erledigt}}",
  "statsChoreLastDone": "zuletzt {date}",
  "statsDeletedSectionHeader": "{count, plural, one{Gelöschte Aufgaben (1)} other{Gelöschte Aufgaben ({count})}}",
  "statsDeletedNotice": "Diese Aufgabe wurde gelöscht. Ihr Verlauf bleibt hier erhalten.",
  "statsHistoryTruncated": "Zeigt die {shown} neuesten von {total}",
  "statsEmptyTitle": "Noch nichts erledigt",
  "statsEmptyBody": "Sobald ihr Aufgaben abhakt, siehst du hier, wer was gemacht hat.",
  "statsErrorMessage": "Der Verlauf konnte nicht geladen werden.",
```

- [ ] **Step 3: Regenerate localizations and verify both locales resolve**

Run: `flutter gen-l10n && flutter analyze --fatal-infos --fatal-warnings`
Expected: generation succeeds with **no** "missing translation" warnings for
any `stats*` key; analyze clean.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb
git commit -m "i18n: chore-history strings (EN + DE)"
```

---

## Task 6: Providers

**Files:**
- Modify: `lib/app/providers.dart`

**Interfaces:**
- Consumes: `StatsRepository` (Task 3), `StatsService` (Task 4).
- Produces:
  - `final statsRepositoryProvider = Provider<StatsRepository>(...)`
  - `final statsServiceProvider = Provider<StatsService>(...)`
  - `final statsOverviewProvider = FutureProvider.autoDispose<StatsOverview>(...)`
  - `class ChoreHistoryView { final Chore chore; final int totalDone; final List<ChoreCompletion> recent; }`
  - `final choreHistoryProvider = FutureProvider.autoDispose.family<ChoreHistoryView, String>(...)`
  - `const int choreHistoryLimit = 50;`

- [ ] **Step 1: Add the providers**

In `lib/app/providers.dart`, add the imports
`package:chore_app/application/stats_service.dart` and
`package:chore_app/data/repositories/stats_repository.dart` alongside the
existing repository imports, then append after `pausedChoresProvider`:

```dart
/// Read-only reporting queries for the chore-history screens (spec
/// `docs/specs/stats.md`).
final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(ref.watch(appDatabaseProvider));
});

/// Assembles the chore-history overview (spec `docs/specs/stats.md` §2.2).
final statsServiceProvider = Provider<StatsService>((ref) {
  return StatsService(
    database: ref.watch(appDatabaseProvider),
    stats: ref.watch(statsRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

/// The chore-history overview for the bootstrap household.
///
/// `autoDispose` and one-shot on purpose (spec `docs/specs/stats.md` §2.3):
/// this screen is a snapshot of the past, so a drift `.watch()` would re-run
/// a whole-history aggregate on every unrelated occurrence write for the rest
/// of the session. Leaving the screen drops the result; re-entering re-reads.
final statsOverviewProvider = FutureProvider.autoDispose<StatsOverview>((
  ref,
) async {
  final householdId = await ref.watch(bootstrapProvider.future);
  return ref.watch(statsServiceProvider).overview(householdId);
});

/// The row cap on a single chore's completion log (spec
/// `docs/specs/stats.md` §5) -- an honest total is shown alongside it rather
/// than rendering a wall of entries.
const int choreHistoryLimit = 50;

/// One chore plus its capped completion log and untruncated total.
class ChoreHistoryView {
  /// Creates a chore-history view.
  const ChoreHistoryView({
    required this.chore,
    required this.totalDone,
    required this.recent,
  });

  /// The chore itself; may be soft-deleted (spec §5).
  final Chore chore;

  /// The chore's all-time `done` count, before [choreHistoryLimit] applies.
  final int totalDone;

  /// The most recent completions, newest first, at most [choreHistoryLimit].
  final List<ChoreCompletion> recent;
}

/// One chore's completion log, keyed by chore id. `autoDispose` for the same
/// reason as [statsOverviewProvider].
final choreHistoryProvider = FutureProvider.autoDispose
    .family<ChoreHistoryView, String>((ref, choreId) async {
      await ref.watch(bootstrapProvider.future);
      final database = ref.watch(appDatabaseProvider);
      final stats = ref.watch(statsRepositoryProvider);
      final chore = await (database.select(
        database.chores,
      )..where((tbl) => tbl.id.equals(choreId))).getSingle();
      return ChoreHistoryView(
        chore: chore,
        totalDone: await stats.doneCountForChore(choreId),
        recent: await stats.recentCompletions(
          choreId,
          limit: choreHistoryLimit,
        ),
      );
    });
```

- [ ] **Step 2: Verify the app still builds and the whole suite is green**

Run: `flutter analyze --fatal-infos --fatal-warnings && flutter test`
Expected: analyze clean; all existing tests still pass (this task adds no
behavior, only providers).

- [ ] **Step 3: Commit**

```bash
git add lib/app/providers.dart
git commit -m "feat(app): chore-history providers (autoDispose, one-shot reads)"
```

---

## Task 7: `StatsShareCard`

**Files:**
- Create: `lib/features/stats/stats_share_card.dart`
- Test: `test/features/stats/stats_screen_test.dart` (created here, extended in Task 9)

**Interfaces:**
- Consumes: `MemberShare` (Task 4), `l10n.stats*` (Task 5), `MemberAvatar`,
  `DepthCard`, `categoryTone`.
- Produces: `class StatsShareCard extends StatelessWidget` with the constructor
  `StatsShareCard({required List<MemberShare> shares, required int totalDone, required PlainDate windowStart, required bool clampedToHouseholdStart, super.key})`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/stats/stats_screen_test.dart`:

```dart
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/stats/stats_share_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Member _member(String id, String name) => Member(
      id: id,
      householdId: 'hh',
      name: name,
      color: 0xFF6D9F71,
      role: MemberRole.member,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      syncDirty: false,
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required List<MemberShare> shares,
  required int totalDone,
  required bool clamped,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: famdoLightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatsShareCard(
          shares: shares,
          totalDone: totalDone,
          windowStart: PlainDate(2026, 8, 9),
          clampedToHouseholdStart: clamped,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('share card names the window, the total, and every entry '
      'including a zero', (tester) async {
    final handle = tester.ensureSemantics();

    await _pumpCard(
      tester,
      shares: [
        MemberShare(member: _member('anna', 'Anna'), doneCount: 3),
        MemberShare(member: _member('ben', 'Ben'), doneCount: 0),
      ],
      totalDone: 3,
      clamped: false,
    );

    expect(find.bySemanticsIdentifier('stats.share'), findsOneWidget);
    expect(find.text('In the last 30 days'), findsOneWidget);
    expect(find.text('3 chores done'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('a clamped window says "since you started" instead',
      (tester) async {
    await _pumpCard(
      tester,
      shares: [
        MemberShare(member: _member('anna', 'Anna'), doneCount: 1),
        MemberShare(member: _member('ben', 'Ben'), doneCount: 1),
      ],
      totalDone: 2,
      clamped: true,
    );

    expect(find.text('In the last 30 days'), findsNothing);
    expect(find.textContaining('Since you started'), findsOneWidget);
  });

  testWidgets('the unattributed bucket renders as "Someone else"',
      (tester) async {
    await _pumpCard(
      tester,
      shares: [
        MemberShare(member: _member('anna', 'Anna'), doneCount: 1),
        const MemberShare(member: null, doneCount: 1),
      ],
      totalDone: 2,
      clamped: false,
    );

    expect(find.text('Someone else'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/stats/stats_screen_test.dart`
Expected: FAIL at compile — `Target of URI doesn't exist:
'package:chore_app/features/stats/stats_share_card.dart'`.

(If `famdoLightTheme` is not the exported name in `lib/app/theme.dart`, use
whatever that file exports for the light `ThemeData` — check it before
implementing and use the real symbol in the test.)

- [ ] **Step 3: Implement the card**

Create `lib/features/stats/stats_share_card.dart`:

```dart
/// The household share card on the chore-history overview (spec
/// `docs/specs/stats.md` §3.1).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/app/theme.dart';
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// How one month's completed chores divided across the household.
///
/// **This is deliberately not a leaderboard** (spec `docs/specs/stats.md`
/// §0): entries render in the order given -- household roster order, which
/// the service guarantees -- and are NEVER re-sorted by count here. No rank
/// numbers, no winner styling, no streaks. Only `done` occurrences are
/// counted; `skipped` and `missed` never reach this widget.
///
/// Semantic id `stats.share`. Like `ChoreProgressCard`, the card carries one
/// [Semantics] label made of the sentences already on screen and excludes
/// every descendant text node, so a screen reader announces it once.
class StatsShareCard extends StatelessWidget {
  /// Creates the share card.
  const StatsShareCard({
    required this.shares,
    required this.totalDone,
    required this.windowStart,
    required this.clampedToHouseholdStart,
    super.key,
  });

  /// Share entries, already in roster order (see the class doc).
  final List<MemberShare> shares;

  /// Total completions across [shares].
  final int totalDone;

  /// First day of the window, used only when [clampedToHouseholdStart].
  final PlainDate windowStart;

  /// Whether the window was shortened to the household's own start date.
  final bool clampedToHouseholdStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final percentFormat = NumberFormat.percentPattern(localeName);

    final windowLabel = clampedToHouseholdStart
        ? l10n.statsWindowSinceStart(
            DateFormat.MMMMd(localeName).format(
              DateTime(windowStart.year, windowStart.month, windowStart.day),
            ),
          )
        : l10n.statsWindowLast30Days;
    final totalLabel = l10n.statsTotalDone(totalDone);

    String nameOf(MemberShare share) =>
        share.member?.name ?? l10n.statsShareUnknownMember;

    return semantic(
      'stats.share',
      child: Semantics(
        label: [
          windowLabel,
          totalLabel,
          for (final share in shares) '${nameOf(share)}: ${share.doneCount}',
        ].join('. '),
        child: ExcludeSemantics(
          child: DepthCard(
            shadow: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    windowLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(totalLabel, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          for (final share in shares)
                            if (share.doneCount > 0)
                              Expanded(
                                flex: share.doneCount,
                                child: ColoredBox(
                                  color: share.member == null
                                      ? theme.colorScheme.outlineVariant
                                      : categoryTone(
                                          context,
                                          share.member!.color,
                                        ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final share in shares)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          if (share.member case final Member member)
                            MemberAvatar(member: member, radius: 12)
                          else
                            Icon(
                              Icons.help_outline,
                              size: 24,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nameOf(share),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          Text(
                            '${share.doneCount} · '
                            '${percentFormat.format(totalDone == 0 ? 0 : share.doneCount / totalDone)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests until green**

Run: `flutter test test/features/stats/stats_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/stats/ test/features/stats/
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/stats/stats_share_card.dart test/features/stats/stats_screen_test.dart
git commit -m "feat(stats): household share card -- proportional, roster-ordered, unranked"
```

---

## Task 8: `ChoreHistoryScreen` (the per-chore log)

**Files:**
- Create: `lib/features/stats/chore_history_screen.dart`
- Test: `test/features/stats/chore_history_screen_test.dart`

**Interfaces:**
- Consumes: `choreHistoryProvider`, `choreHistoryLimit`, `ChoreHistoryView`
  (Task 6); `l10n.stats*` (Task 5).
- Produces: `class ChoreHistoryScreen extends ConsumerWidget` with
  `const ChoreHistoryScreen({required String choreId, super.key})`.
- Semantic ids: `stats.history.deletedNotice`,
  `stats.history.row.<occurrenceId>`, `stats.history.truncated`,
  `stats.history.error.retry`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/stats/chore_history_screen_test.dart`:

```dart
import 'package:chore_app/data/db/app_database.dart';
import 'package:chore_app/domain/recurrence/plain_date.dart';
import 'package:chore_app/features/stats/chore_history_screen.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/pump_app.dart';

/// Seeds one chore and [count] `done` occurrences of it, closed on
/// consecutive days ending on [lastClosedOn].
Future<String> _seedChoreWithHistory(
  AppDatabase database, {
  required String title,
  required int count,
  required PlainDate lastClosedOn,
  bool deleted = false,
}) async {
  final householdId = await currentHouseholdId(database);
  final member = await (database.select(
    database.members,
  )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  const choreId = 'chore-history-test';
  await database.into(database.chores).insert(
        ChoresCompanion.insert(
          id: choreId,
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deleted ? '2026-08-10T00:00:00.000Z' : null),
        ),
      );
  for (var i = 0; i < count; i++) {
    final closedOn = lastClosedOn.addDays(-i);
    await database.into(database.choreOccurrences).insert(
          ChoreOccurrencesCompanion.insert(
            id: 'occ-$i',
            choreId: choreId,
            dueDate: closedOn,
            status: const Value(OccurrenceStatus.done),
            completedBy: Value(member.id),
            closedOn: Value(closedOn),
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        );
  }
  return choreId;
}

Future<void> _openHistory(WidgetTester tester, String choreId) async {
  final context = tester.element(find.byType(Navigator).first);
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChoreHistoryScreen(choreId: choreId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime(2026, 8, 11, 9);

  testChoreApp(
    'a chore log lists its completions newest first with the total',
    today: today,
    (tester, database) async {
      final choreId = await _seedChoreWithHistory(
        database,
        title: 'Bathroom',
        count: 3,
        lastClosedOn: PlainDate(2026, 8, 10),
      );

      await _openHistory(tester, choreId);

      expect(find.text('Bathroom'), findsOneWidget);
      expect(find.text('3 chores done'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.history.row.occ-0'),
          findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.history.truncated'),
          findsNothing);
    },
  );

  testChoreApp(
    'a deleted chore still shows its history, with the deleted notice',
    today: today,
    (tester, database) async {
      final choreId = await _seedChoreWithHistory(
        database,
        title: 'Attic',
        count: 2,
        lastClosedOn: PlainDate(2026, 8, 1),
        deleted: true,
      );

      await _openHistory(tester, choreId);

      expect(find.bySemanticsIdentifier('stats.history.deletedNotice'),
          findsOneWidget);
      expect(find.text('2 chores done'), findsOneWidget);
    },
  );

  testChoreApp(
    'more completions than the cap shows the truncation line',
    today: today,
    (tester, database) async {
      final choreId = await _seedChoreWithHistory(
        database,
        title: 'Dishes',
        count: 52,
        lastClosedOn: PlainDate(2026, 8, 10),
      );

      await _openHistory(tester, choreId);

      expect(find.text('52 chores done'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.history.truncated'),
          findsOneWidget);
    },
  );
}
```

Add `import 'dart:async';` at the top for `unawaited`, and remember every test
here needs `tester.ensureSemantics()` around the `bySemanticsIdentifier`
lookups — wrap each body in
`final handle = tester.ensureSemantics(); … handle.dispose();`.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/stats/chore_history_screen_test.dart`
Expected: FAIL at compile — `chore_history_screen.dart` does not exist.

- [ ] **Step 3: Implement the screen**

Create `lib/features/stats/chore_history_screen.dart`:

```dart
/// One chore's completion log (spec `docs/specs/stats.md` §5).
library;

import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/features/members/member_avatar.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Every recorded completion of one chore, newest first, capped at
/// [choreHistoryLimit] with an honest total above it.
///
/// Read-only by design: nothing here mutates an occurrence. Reopening a
/// completion lives where it always has (the chores list's Done-today
/// section, LIFO-restricted -- `docs/specs/occurrence-lifecycle.md`).
///
/// Reachable for a SOFT-DELETED chore too -- that is the entire point of
/// this screen (`docs/research/triage.md` D2): every other read path in the
/// app filters `deleted_at IS NULL`, which is what made "its history is
/// kept" unverifiable.
class ChoreHistoryScreen extends ConsumerWidget {
  /// Creates the log screen for [choreId].
  const ChoreHistoryScreen({required this.choreId, super.key});

  /// The chore whose completions are listed.
  final String choreId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final historyAsync = ref.watch(choreHistoryProvider(choreId));

    return Scaffold(
      appBar: AppBar(title: Text(historyAsync.valueOrNull?.chore.title ?? '')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.statsErrorMessage),
              const SizedBox(height: 8),
              semantic(
                'stats.history.error.retry',
                child: OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(choreHistoryProvider(choreId)),
                  child: Text(l10n.commonRetry),
                ),
              ),
            ],
          ),
        ),
        data: (history) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (history.chore.deletedAt != null)
              semantic(
                'stats.history.deletedNotice',
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.statsDeletedNotice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Text(
              l10n.statsTotalDone(history.totalDone),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final completion in history.recent)
              semantic(
                'stats.history.row.${completion.occurrence.id}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      if (completion.completedByMember case final member?)
                        MemberAvatar(member: member, radius: 12)
                      else
                        Icon(
                          Icons.help_outline,
                          size: 24,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          completion.completedByMember?.name ??
                              l10n.statsShareUnknownMember,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Text(
                        completion.occurrence.closedOn == null
                            ? ''
                            : DateFormat.yMMMd(localeName).format(
                                DateTime(
                                  completion.occurrence.closedOn!.year,
                                  completion.occurrence.closedOn!.month,
                                  completion.occurrence.closedOn!.day,
                                ),
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (history.totalDone > history.recent.length)
              semantic(
                'stats.history.truncated',
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.statsHistoryTruncated(
                      history.recent.length,
                      history.totalDone,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests until green**

Run: `flutter test test/features/stats/chore_history_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/stats/ test/features/stats/
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/stats/chore_history_screen.dart \
        test/features/stats/chore_history_screen_test.dart
git commit -m "feat(stats): per-chore completion log, reachable for deleted chores"
```

---

## Task 9: `StatsScreen` (the overview)

**Files:**
- Create: `lib/features/stats/stats_screen.dart`
- Test: `test/features/stats/stats_screen_test.dart` (extend Task 7's file)

**Interfaces:**
- Consumes: `statsOverviewProvider` (Task 6), `StatsShareCard` (Task 7),
  `ChoreHistoryScreen` (Task 8), `l10n.stats*` (Task 5).
- Produces: `class StatsScreen extends ConsumerWidget` with
  `const StatsScreen({super.key})`.
- Semantic ids: `stats.total`, `stats.empty`, `stats.error.retry`,
  `stats.chore.<choreId>`, `stats.deleted`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/stats/stats_screen_test.dart` (add the imports it
needs: `pump_app.dart`, `settings_test_utils.dart`, `app_database.dart`,
`drift`):

```dart
  testChoreApp(
    'a household with no completions shows the teaching empty state',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await openChoreHistory(tester);

      expect(find.bySemanticsIdentifier('stats.empty'), findsOneWidget);
      expect(find.text('No completed chores yet'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.share'), findsNothing);

      handle.dispose();
    },
  );

  testChoreApp(
    'a single-member household gets the total line, not the share card',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedDoneChore(database, title: 'Bathroom', closedOn: '2026-08-10');

      await openChoreHistory(tester);

      expect(find.bySemanticsIdentifier('stats.total'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.share'), findsNothing);
      expect(find.text('1 chore done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a chore row shows all-time count and last date, and opens the log',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await seedDoneChore(
        database,
        title: 'Bathroom',
        closedOn: '2026-08-10',
      );

      await openChoreHistory(tester);
      expect(find.textContaining('Done once'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier('stats.chore.$choreId'));
      await tester.pumpAndSettle();
      expect(find.text('1 chore done'), findsOneWidget);

      handle.dispose();
    },
  );

  testChoreApp(
    'a deleted chore with history appears under the deleted section, not '
    'the main list',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      final choreId = await seedDoneChore(
        database,
        title: 'Attic',
        closedOn: '2026-08-01',
        deleted: true,
      );

      await openChoreHistory(tester);

      expect(find.bySemanticsIdentifier('stats.deleted'), findsOneWidget);
      expect(find.text('Deleted chores (1)'), findsOneWidget);
      expect(find.bySemanticsIdentifier('stats.chore.$choreId'), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('stats.deleted'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('stats.chore.$choreId'), findsOneWidget);

      handle.dispose();
    },
  );
```

Add this seeding helper to the same test file:

```dart
/// Seeds one chore with exactly one `done` occurrence closed on [closedOn],
/// credited to the bootstrap member. Returns the chore id.
Future<String> seedDoneChore(
  AppDatabase database, {
  required String title,
  required String closedOn,
  bool deleted = false,
}) async {
  final householdId = await currentHouseholdId(database);
  final member = await (database.select(
    database.members,
  )..where((tbl) => tbl.householdId.equals(householdId))).getSingle();
  final choreId = 'chore-$title';
  await database.into(database.chores).insert(
        ChoresCompanion.insert(
          id: choreId,
          householdId: householdId,
          title: title,
          startDate: PlainDate(2026, 1, 1),
          assignmentMode: AssignmentMode.anyone,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          deletedAt: Value(deleted ? '2026-08-10T00:00:00.000Z' : null),
        ),
      );
  await database.into(database.choreOccurrences).insert(
        ChoreOccurrencesCompanion.insert(
          id: 'occ-$title',
          choreId: choreId,
          dueDate: PlainDate.parse(closedOn),
          status: const Value(OccurrenceStatus.done),
          completedBy: Value(member.id),
          closedOn: Value(PlainDate.parse(closedOn)),
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
  return choreId;
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/features/stats/stats_screen_test.dart`
Expected: FAIL — `openChoreHistory` is undefined and
`stats_screen.dart` does not exist. (`openChoreHistory` arrives in Task 11; for
now these four tests fail. That is expected and fine — Task 11 closes them. If
you prefer strictly-green intermediate commits, do Task 11's `settings_test_utils`
helper and Settings row **before** this task; the code is independent.)

- [ ] **Step 3: Implement the screen**

Create `lib/features/stats/stats_screen.dart`:

```dart
/// The chore-history overview (spec `docs/specs/stats.md` §3).
library;

import 'package:chore_app/app/depth_card.dart';
import 'package:chore_app/app/providers.dart';
import 'package:chore_app/app/semantics.dart';
import 'package:chore_app/application/stats_service.dart';
import 'package:chore_app/data/repositories/stats_repository.dart';
import 'package:chore_app/features/categories/category_badge.dart';
import 'package:chore_app/features/stats/chore_history_screen.dart';
import 'package:chore_app/features/stats/stats_share_card.dart';
import 'package:chore_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// "Who actually does the chores": a household share for the last 30 days,
/// then every chore that has ever been completed, then a collapsed section
/// of deleted chores whose history is still kept.
///
/// The anti-leaderboard rules that govern this screen are in spec
/// `docs/specs/stats.md` §0 and are binding: only `done` is attributed, the
/// share is roster-ordered rather than ranked, the chore list is
/// alphabetical rather than sorted by count, and there is no per-member
/// drill-down.
class StatsScreen extends ConsumerWidget {
  /// Creates the chore-history overview.
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final overviewAsync = ref.watch(statsOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: overviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.statsErrorMessage),
              const SizedBox(height: 8),
              semantic(
                'stats.error.retry',
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(statsOverviewProvider),
                  child: Text(l10n.commonRetry),
                ),
              ),
            ],
          ),
        ),
        data: (overview) => _Body(overview: overview),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.overview});

  final StatsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (overview.activeChores.isEmpty && overview.deletedChores.isEmpty) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        if (overview.shares.length >= 2)
          StatsShareCard(
            shares: overview.shares,
            totalDone: overview.totalDone,
            windowStart: overview.windowStart,
            clampedToHouseholdStart: overview.windowClampedToHouseholdStart,
          )
        else
          semantic(
            'stats.total',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 16, 8),
              child: Text(
                l10n.statsTotalDone(overview.totalDone),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
        _SectionHeader(label: l10n.statsChoresSectionTitle),
        for (final rollup in overview.activeChores) _ChoreRow(rollup: rollup),
        if (overview.deletedChores.isNotEmpty)
          DepthCard(
            child: semantic(
              'stats.deleted',
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  l10n.statsDeletedSectionHeader(
                    overview.deletedChores.length,
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  for (final rollup in overview.deletedChores)
                    _ChoreRow(rollup: rollup, insideCard: true),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// One chore's row: title, category badge, and "{n} times · last {date}" --
/// both figures all-time (spec §3.2), never windowed.
class _ChoreRow extends StatelessWidget {
  const _ChoreRow({required this.rollup, this.insideCard = false});

  final ChoreDoneRollup rollup;

  /// When true the row is already inside the deleted section's card, so it
  /// does not wrap itself in another [DepthCard].
  final bool insideCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final last = DateFormat.yMMMd(localeName).format(
      DateTime(
        rollup.lastDoneOn.year,
        rollup.lastDoneOn.month,
        rollup.lastDoneOn.day,
      ),
    );

    final tile = semantic(
      'stats.chore.${rollup.chore.id}',
      child: ListTile(
        title: Text(rollup.chore.title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          '${l10n.statsChoreTimesDone(rollup.doneAllTime)} · '
          '${l10n.statsChoreLastDone(last)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: rollup.category == null
            ? null
            : CategoryBadge(category: rollup.category!),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChoreHistoryScreen(choreId: rollup.chore.id),
          ),
        ),
      ),
    );

    return insideCard ? tile : DepthCard(child: tile);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final famdo = famdoColors(context);
    return semantic(
      'stats.empty',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: famdo.primaryOutline),
                ),
                child: Icon(
                  Icons.history_outlined,
                  size: 34,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.statsEmptyTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                l10n.statsEmptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add `import 'package:chore_app/app/famdo_colors.dart';` for `famdoColors`. If
`CategoryBadge`'s constructor differs from `CategoryBadge(category: ...)`, read
`lib/features/categories/category_badge.dart` and use its real signature —
do not invent one.

- [ ] **Step 4: Run the tests until green**

Run: `flutter test test/features/stats/stats_screen_test.dart`
Expected: the three Task-7 card tests PASS; the four new ones PASS once Task 11
lands `openChoreHistory`.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/stats/ test/features/stats/
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/stats/stats_screen.dart test/features/stats/stats_screen_test.dart
git commit -m "feat(stats): chore-history overview -- share, chore list, deleted section"
```

---

## Task 10: Text-scale and dark-mode gate for both screens

**Files:**
- Test: `test/features/stats/stats_screen_test.dart` (extend)

**Interfaces:**
- Consumes: Tasks 7–9's widgets.

`docs/specs/theme-v2.md` §5 makes text scale 2.0 a release gate, and every other
feature in this app has a `theme_and_scale_test.dart` equivalent. The share
card's percent column and the chore row's two-part metadata line are the two
overflow risks.

- [ ] **Step 1: Write the failing test**

Append to `test/features/stats/stats_screen_test.dart`:

```dart
  testChoreApp(
    'chore-history overview lays out at text scale 2.0 without overflow',
    today: DateTime(2026, 8, 11, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();
      await seedDoneChore(database, title: 'Bathroom', closedOn: '2026-08-10');

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openChoreHistory(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run it**

Run: `flutter test test/features/stats/stats_screen_test.dart`
Expected: FAIL with a `FlutterError` about a `RenderFlex` overflow **if** the
layout is too tight; PASS if it already fits.

- [ ] **Step 3: Fix any overflow found**

If the share-card row overflows, wrap the trailing count/percent `Text` so it can
shrink: replace it with

```dart
                          Flexible(
                            child: Text(
                              '${share.doneCount} · '
                              '${percentFormat.format(totalDone == 0 ? 0 : share.doneCount / totalDone)}',
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
```

If nothing overflows, make no change — the test is the gate, not a mandate to
edit.

- [ ] **Step 4: Re-run until green, then commit**

```bash
flutter test test/features/stats/stats_screen_test.dart
dart format lib/features/stats/ test/features/stats/
git add lib/features/stats/ test/features/stats/
git commit -m "test(stats): text-scale 2.0 gate for the chore-history screens"
```

---

## Task 11: The Settings entry point

**Files:**
- Modify: `lib/features/settings/settings_screen.dart` (the Household `SettingsGroup`, currently lines 56–87)
- Modify: `test/features/settings/settings_test_utils.dart`
- Test: `test/features/settings/settings_group_test.dart` (extend) or a new case in `test/features/stats/stats_screen_test.dart`

**Interfaces:**
- Consumes: `StatsScreen` (Task 9), `l10n.statsSettingsEntry` (Task 5).
- Produces: semantic id `settings.stats`; test helper
  `Future<void> openChoreHistory(WidgetTester tester)`.

- [ ] **Step 1: Add the test helper**

Append to `test/features/settings/settings_test_utils.dart`:

```dart
/// Opens the Settings tab, then the chore-history screen (spec
/// `docs/specs/stats.md` §1).
Future<void> openChoreHistory(WidgetTester tester) async {
  await openSettingsTab(tester);
  final handle = tester.ensureSemantics();
  await tester.tap(find.bySemanticsIdentifier('settings.stats'));
  await tester.pumpAndSettle();
  handle.dispose();
}
```

Import it in `test/features/stats/stats_screen_test.dart`:

```dart
import '../settings/settings_test_utils.dart';
```

- [ ] **Step 2: Run Task 9's tests and watch them fail on the missing row**

Run: `flutter test test/features/stats/stats_screen_test.dart`
Expected: FAIL — `find.bySemanticsIdentifier('settings.stats')` matches nothing.

- [ ] **Step 3: Add the Settings row**

In `lib/features/settings/settings_screen.dart`, add
`import 'package:chore_app/features/stats/stats_screen.dart';` and insert this
as the last child of the Household `SettingsGroup`, immediately after the
`settings.categories` row:

```dart
              semantic(
                'settings.stats',
                child: SettingsRow(
                  icon: Icons.history_outlined,
                  label: l10n.statsSettingsEntry,
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
                  ),
                ),
              ),
```

Extend the class doc comment with:

```dart
/// The Household group also carries the Chore history row (spec
/// `docs/specs/stats.md` §1) below Categories -- deliberately a quiet
/// Settings entry rather than a fourth tab, since a family opens it monthly
/// and the delete dialog names the path when it matters.
```

- [ ] **Step 4: Run the affected suites**

Run: `flutter test test/features/stats/ test/features/settings/`
Expected: PASS. Note `test/features/settings/settings_group_test.dart` and
`theme_and_scale_test.dart` may assert a row count in the Household group — if
one fails on an off-by-one, update the expected count; do not delete the
assertion.

- [ ] **Step 5: Commit**

```bash
dart format lib/features/settings/settings_screen.dart test/features/settings/settings_test_utils.dart
flutter analyze --fatal-infos --fatal-warnings
git add lib/features/settings/settings_screen.dart \
        test/features/settings/settings_test_utils.dart \
        test/features/stats/stats_screen_test.dart
git commit -m "feat(settings): Chore history row in the Household group"
```

---

## Task 12: Restore the delete promise (triage D2 step 2)

**Files:**
- Modify: `lib/l10n/app_en.arb:109-118` (`choresDeleteDialogBody` + its `@` block)
- Modify: `lib/l10n/app_de.arb:27`
- Modify: `docs/specs/design-language.md` (Interaction rules, item 3)
- Modify: `docs/backlog.md` (row G-1), `docs/research/triage.md` (T1.2 / D2)
- Test: `test/features/chores/menu_actions_test.dart` (extend)

**Interfaces:**
- Consumes: everything above. **This task may not be started until Tasks 8, 9
  and 11 are green** — that ordering is the product decision itself (spec §6,
  triage D2: shipping the strong copy before the mechanism would be knowingly
  keeping an empty promise).

- [ ] **Step 1: Write the failing test**

Append to `test/features/chores/menu_actions_test.dart`, inside `main()`,
following that file's existing pattern for opening a chore's action sheet and
its delete dialog:

```dart
  testChoreApp(
    'the delete dialog now promises history is kept AND names where to find '
    'it (triage D2 step 2 -- the promise is only made once the mechanism '
    'exists)',
    today: DateTime(2026, 7, 24, 9),
    (tester, database) async {
      final handle = tester.ensureSemantics();

      // (Reuse this file's existing helper for creating a chore and opening
      // its overflow menu; then:)
      await tester.tap(find.bySemanticsIdentifier('chores.menu.delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('history is kept'), findsOneWidget);
      expect(find.textContaining('Chore history'), findsOneWidget);
      expect(find.textContaining("can't view it again yet"), findsNothing);

      handle.dispose();
    },
  );
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/chores/menu_actions_test.dart`
Expected: FAIL — the dialog still says "You can't view it again yet."

- [ ] **Step 3: Restore the copy**

In `lib/l10n/app_en.arb`, replace the `choresDeleteDialogBody` value and its
description:

```json
  "choresDeleteDialogBody": "This removes '{choreTitle}' from your lists. Its history is kept — you'll find it under Settings › Chore history.",
  "@choresDeleteDialogBody": {
    "description": "Body of the chore delete-confirmation dialog. Restored to the stronger promise on 2026-08-11, when the chore-history screen shipped (docs/research/triage.md D2 step 2, docs/specs/stats.md §6): the claim that history is kept is now verifiable, because deleted chores are listed under Settings > Chore history and their completion log is readable there. Do NOT weaken or strengthen this copy without re-checking that screen still exists.",
    "placeholders": {
      "choreTitle": {
        "type": "String",
        "example": "Clean windows"
      }
    }
  },
```

(Preserve whatever `placeholders` block the file currently has — the key already
takes `choreTitle`.)

In `lib/l10n/app_de.arb`, line 27:

```json
  "choresDeleteDialogBody": "Damit entfernst du '{choreTitle}' aus deinen Listen. Der Verlauf bleibt erhalten — du findest ihn unter Einstellungen › Aufgaben-Verlauf.",
```

- [ ] **Step 4: Run the test until green, and the delete E2E's widget cousins**

Run: `flutter test test/features/chores/`
Expected: PASS. `e2e/flows/chores/delete_confirm_and_cancel.yaml` selects by
`chores.delete.cancel` / `chores.delete.confirm` ids and never asserts the body
text, so it is unaffected — verify by reading it, do not assume.

- [ ] **Step 5: Update the two docs that now state something false**

In `docs/specs/design-language.md`, Interaction rule 3, change

> chore delete confirms via dialog (it erases a pending occurrence and hides
> history)

to

> chore delete confirms via dialog (it erases a pending occurrence and removes
> the chore from every list; its completion history is kept and stays readable
> under Settings → Chore history, spec `docs/specs/stats.md`)

In `docs/backlog.md`, change row **G-1**'s Notes cell to record that it shipped
and that the strong delete copy was restored with it. In
`docs/research/triage.md`, append one line under **D2**:

```markdown
**Shipped 2026-08-11**: step 2 is done — `docs/specs/stats.md` /
`docs/plans/2026-08-08-stats-screen.md`. The stronger copy is back in
`choresDeleteDialogBody`, and it is now true.
```

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_de.arb docs/specs/design-language.md \
        docs/backlog.md docs/research/triage.md test/features/chores/menu_actions_test.dart
git commit -m "feat(chores): restore the 'history is kept' delete promise (triage D2 step 2)"
```

---

## Task 13: E2E flow — the D2 promise, end to end

**Files:**
- Create: `e2e/flows/settings/chore_history.yaml`

**Interfaces:**
- Consumes: ids `chores.add`, `chore_form.title`, `chore_form.save`,
  `chores.occurrence.<id>.complete`, `chores.occurrence.<id>.menu`,
  `chores.menu.delete`, `chores.delete.confirm`, `shell.tab.settings`,
  `settings.stats`, `stats.deleted`, `stats.chore.<id>`.
- Flows are discovered by directory (`maestro test … e2e/flows`), so no
  registration step exists.

- [ ] **Step 1: Write the flow**

Create `e2e/flows/settings/chore_history.yaml`:

```yaml
# Chore history: a completed chore shows up, and a DELETED chore's history is
# still findable -- the executable form of triage D2's promise
# (docs/specs/stats.md §3.3, §6).
appId: ${APP_ID}
tags:
  - happy
---
- launchApp:
    clearState: true
# First-frame settle (README convention 8).
- extendedWaitUntil:
    visible:
      id: "welcome.create"
    timeout: 60000
- runFlow: ../../common/onboard_fresh.yaml

# Create a chore and complete it, so there is history to show.
- tapOn:
    id: "chores.add"
- tapOn:
    id: "chore_form.title"
- inputText: "Clean windows"
- pressKey: Enter
- tapOn:
    id: "chore_form.save"
- assertVisible: "(?s).*Clean windows.*"
- tapOn:
    id: 'chores\.occurrence\..*\.complete'

# The completion is visible in Chore history.
- tapOn:
    id: "shell.tab.settings"
- tapOn:
    id: "settings.stats"
- assertVisible: "(?s).*Clean windows.*"
- assertVisible: "(?s).*Done once.*"

# Delete the chore, then prove its history survived and is findable.
- tapOn:
    id: "shell.tab.chores"
- tapOn:
    id: 'chores\.occurrence\..*\.menu'
- tapOn:
    id: "chores.menu.delete"
- assertVisible: "(?s).*Chore history.*"
- tapOn:
    id: "chores.delete.confirm"
- tapOn:
    id: "shell.tab.settings"
- tapOn:
    id: "settings.stats"
- tapOn:
    id: "stats.deleted"
- assertVisible: "(?s).*Clean windows.*"
```

- [ ] **Step 2: Run the flow locally**

Run (needs `JAVA_HOME` exported to the Homebrew JDK 21, or Maestro silently
runs 0 flows and still exits 0 — check the flow count in the output):

```bash
maestro test --env APP_ID=io.github.igorzamyslov.famdo e2e/flows/settings/chore_history.yaml
```
Expected: 1 flow, PASSED. If the "Done once" assertion is brittle in DE-locale
CI, drop that one line and keep the chore-title assertions — never loosen the
`stats.deleted` step, which is the point of the flow.

Per project convention, **the E2E gate is GitHub CI**, not this Mac. A local
failure caused by machine load is not evidence; push and read CI.

- [ ] **Step 3: Commit**

```bash
git add e2e/flows/settings/chore_history.yaml
git commit -m "test(e2e): chore history shows completions and survives deletion"
```

---

## Task 14: Full verification

**Files:** none modified unless a check fails.

- [ ] **Step 1: Format check**

Run: `dart format --set-exit-if-changed .`
Expected: exit 0.

- [ ] **Step 2: Analyze**

Run: `flutter analyze --fatal-infos --fatal-warnings`
Expected: "No issues found!"

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests pass, including the ~640 pre-existing ones. Any pre-existing
test that broke is a regression from this work — fix the code, or update the
assertion only when the change was intended (e.g. the Household group's row
count in Task 11).

- [ ] **Step 4: Visual QA (the `design-language.md` definition of visual done)**

On a Pixel-class emulator and an SE-class iPhone simulator, check both new
screens in **light and dark**, at text scale **1.0 and 2.0**:
- no overflow in the share card's rows or the chore rows;
- the share bar's segments are visible for a 1-of-many share;
- every tappable row is ≥ 48dp tall;
- the empty state reads calm, not error-like.

- [ ] **Step 5: E2E in CI**

Push the branch and confirm all Maestro flows (the 12 existing + the new one)
are green on the GitHub Android job before calling this done.

- [ ] **Step 6: Final commit if anything was touched**

```bash
git add -A
git commit -m "chore: verification pass for the chore-history feature"
```

---

## Self-review notes (for the executing agent)

Checked against the spec written in Task 1:

- §0 rules 1–5 → enforced in Task 3's query `WHERE` clauses (done-only),
  Task 4's roster-order assembly, Task 9's alphabetical chore list, and the
  absence of any per-member route anywhere in the plan.
- §1 placement → Task 11. §2.1 inclusion rules → Task 3 tests.
  §2.2 window + clamp → Task 4 tests. §2.3 index + one-shot reads → Tasks 2, 6.
- §3.1 share card → Task 7. §3.2 chore list → Task 9. §3.3 deleted section →
  Task 9 + Task 13. §3.4 empty state → Task 9. §3.5 error state → Task 9.
- §4 copy rules → Task 5 (all keys EN+DE, plurals both locales, `intl` for
  dates and percents).
- §5 per-chore log → Task 8. §6 restored delete copy → Task 12, gated on 8/9/11.
- §7 non-goals → nothing in the plan builds any of them.
- §8 testing → Tasks 3, 4, 7, 8, 9, 10, 13.

Type consistency spot-check: `MemberDoneCount` / `ChoreDoneRollup` /
`ChoreCompletion` (Task 3) are the exact names consumed by Task 4 and Task 6;
`MemberShare` / `StatsOverview` / `statsWindowDays` (Task 4) are the exact names
consumed by Tasks 6, 7 and 9; `ChoreHistoryView` / `choreHistoryLimit` (Task 6)
are the exact names consumed by Task 8.
